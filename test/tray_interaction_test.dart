import 'dart:async';

import 'package:easy_dice_thrower/app_theme.dart';
import 'package:easy_dice_thrower/main.dart';
import 'package:easy_dice_thrower/models/dice.dart';
import 'package:easy_dice_thrower/platform/orientation_lock.dart';
import 'package:easy_dice_thrower/tray_controller.dart';
import 'package:easy_dice_thrower/widgets/tray_option.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_store.dart';

Future<TrayController> openInteractionTray(
  WidgetTester tester, {
  MemoryStore? store,
  RollDie? roller,
  DiceSet? set,
  String language = 'en',
  OrientationLock? lock,
}) async {
  final tray = TrayController(
    store: store ?? MemoryStore(),
    roller: roller ?? (_) async => 1,
  );
  addTearDown(tray.dispose);
  await tray.load();
  if (set != null) tray.loadSet(set);
  tray.setLanguage(language);
  await tester.pumpWidget(EasyDiceApp(controller: tray, orientationLock: lock));
  await tester.pumpAndSettle();
  return tray;
}

Future<void> use(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder dialogCard() => find.descendant(
  of: find.byType(Dialog),
  matching: find.byWidgetPredicate(
    (widget) => widget is Material && widget.type == MaterialType.card,
  ),
);

void main() {
  testWidgets('changing a rolled modified tray requires confirmation', (
    tester,
  ) async {
    final tray = await openInteractionTray(tester);
    tray.addDice(DieDefinition.numeric(12), 1);
    await tray.rollAll();
    await tester.pumpAndSettle();
    final ids = tray.dice.map((die) => die.id).toList();
    await use(tester, find.text('Sets'));
    await use(tester, find.text('Classic dice'));
    expect(find.text('Replace the current tray?'), findsOneWidget);
    await use(tester, find.text('Cancel'));
    expect(tray.dice.map((die) => die.id), ids);
    expect(tray.dice.every((die) => die.value == 1), isTrue);
    await use(tester, find.text('Classic dice'));
    await use(tester, find.text('Load set'));
    expect(tray.preset, DicePreset.classic);
    expect(tray.dice, hasLength(2));
    expect(tray.dice.every((die) => die.value == null), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'transparent dialog stays modal without rolling the visible background',
    (tester) async {
      final tray = await openInteractionTray(tester);
      await use(tester, find.text('Add dice'));
      final dialog = find.byType(Dialog);
      final route = ModalRoute.of(tester.element(dialog))!;
      expect(route.barrierColor, Colors.transparent);
      final face = tester.getRect(
        find.byKey(ValueKey('die-face-${tray.dice.first.id}')),
      );
      final point = face.topLeft + const Offset(8, 8);
      expect(tester.getRect(dialogCard()).contains(point), isFalse);
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tray.dice.every((die) => die.rollCount == 0), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  test('focused black controls have a contrasting static stroke', () {
    final styles = [
      buildAppTheme().filledButtonTheme.style!,
      choiceButtonStyle(selected: true),
      choiceButtonStyle(selected: false),
    ];
    for (final style in styles) {
      final states = {WidgetState.focused};
      expect(
        style.side!.resolve(states)!.color,
        isNot(style.backgroundColor!.resolve(states)),
      );
      expect(style.side!.resolve(states)!.width, greaterThanOrEqualTo(3));
      for (final state in [
        WidgetState.focused,
        WidgetState.hovered,
        WidgetState.pressed,
      ]) {
        expect(style.overlayColor!.resolve({state}), Colors.transparent);
      }
      expect(style.animationDuration, Duration.zero);
    }
  });

  for (final size in [const Size(640, 320), const Size(390, 844)]) {
    testWidgets('long outcomes remain inspectable without rolling at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final outcomes = ['${'A' * 79}1', '${'A' * 79}2'];
      var value = 0;
      final tray = await openInteractionTray(
        tester,
        roller: (_) async => ++value,
        set: DiceSet('Long labels', [DieDefinition.text('Outcome', outcomes)]),
      );
      final face = find.byKey(ValueKey('die-face-${tray.dice.single.id}'));
      for (final outcome in outcomes) {
        await use(tester, face);
        final count = tray.dice.single.rollCount;
        await use(tester, find.text('Full result'));
        final full = tester.widget<SelectableText>(find.byType(SelectableText));
        expect(full.data, outcome);
        expect(full.maxLines, isNull);
        expect(tray.dice.single.rollCount, count);
        await use(tester, find.text('Close'));
        expect(tray.dice.single.rollCount, count);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'pending success and failure preserve keyboard focus without stealing it',
    (tester) async {
      var pending = Completer<int>();
      var requests = 0;
      final tray = await openInteractionTray(
        tester,
        roller: (_) {
          requests++;
          return pending.future;
        },
      );
      FocusNode node(int id) =>
          tester
              .widget<FocusableActionDetector>(
                find
                    .ancestor(
                      of: find.byKey(ValueKey('die-face-$id')),
                      matching: find.byType(FocusableActionDetector),
                    )
                    .first,
              )
              .focusNode!;
      final focus = node(tray.dice.first.id);
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(requests, 1);
      pending.complete(1);
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      pending = Completer<int>();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(requests, 2);
      pending.completeError(StateError('Roll failed'));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(tray.dice.first.rollCount, 1);
      pending = Completer<int>();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      final other = node(tray.dice[1].id);
      other.requestFocus();
      await tester.pump();
      pending.complete(1);
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
      expect(other.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['en', 'cs']) {
    testWidgets('delete confirmation fits 320px and large text in $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final tray = await openInteractionTray(tester, language: language);
      tray.saveSet('Campaign');
      await tester.pumpAndSettle();
      await use(tester, find.byKey(const ValueKey('tray-menu')));
      await use(tester, find.text(language == 'en' ? 'Sets' : 'Sady'));
      await use(tester, find.byIcon(Icons.delete_outline));
      expect(tester.takeException(), isNull);
      await use(tester, find.text(language == 'en' ? 'Cancel' : 'Zrušit'));
      expect(tray.savedSets.single.name, 'Campaign');
      await use(tester, find.byIcon(Icons.delete_outline));
      await use(tester, find.text(language == 'en' ? 'Delete' : 'Smazat'));
      expect(tray.savedSets, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed-load replacement requires the in-app confirmation', (
    tester,
  ) async {
    final store = MemoryStore('{bad data');
    final tray = await openInteractionTray(tester, store: store);
    expect(tray.recoveryRequired, isTrue);
    await use(tester, find.text('Replace saved data'));
    await use(tester, find.text('Cancel'));
    expect(store.value, '{bad data');
    expect(store.writes, isEmpty);
    await use(tester, find.text('Replace saved data'));
    await use(tester, find.widgetWithText(FilledButton, 'Replace saved data'));
    expect(tray.recoveryRequired, isFalse);
    expect(store.value, isNot('{bad data'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('language and orientation expose their selected option', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final lock = OrientationLock(supported: true, request: (_) async {});
      addTearDown(lock.dispose);
      await openInteractionTray(tester, lock: lock);
      await use(tester, find.byKey(const ValueKey('language-picker')));
      expect(
        tester
            .getSemantics(find.widgetWithText(TrayOption, 'English'))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isTrue,
      );
      expect(
        tester
            .getSemantics(find.widgetWithText(TrayOption, 'Čeština'))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isFalse,
      );
      await use(tester, find.text('Close'));
      await use(tester, find.byKey(const ValueKey('orientation-picker')));
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('orientation-portrait')))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isTrue,
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('orientation-landscape')))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('keyboard insets change dialog geometry in the first frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final tray = await openInteractionTray(tester);
    await use(tester, find.byKey(const ValueKey('tray-menu')));
    await use(tester, find.text('Add dice'));
    final faces = [
      for (final die in tray.dice)
        tester.getRect(find.byKey(ValueKey('die-outline-${die.id}'))),
    ];
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump();
    final immediate = tester.getRect(dialogCard());
    expect([
      for (final die in tray.dice)
        tester.getRect(find.byKey(ValueKey('die-outline-${die.id}'))),
    ], faces);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getRect(dialogCard()), immediate);
    expect(
      tester.widget<Dialog>(find.byType(Dialog)).insetAnimationDuration,
      Duration.zero,
    );
    expect(tester.takeException(), isNull);
  });
}
