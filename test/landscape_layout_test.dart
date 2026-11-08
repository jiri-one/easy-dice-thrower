import 'package:easy_dice_thrower/main.dart';
import 'package:easy_dice_thrower/models/dice.dart';
import 'package:easy_dice_thrower/platform/orientation_lock.dart';
import 'package:easy_dice_thrower/tray_controller.dart';
import 'package:easy_dice_thrower/widgets/die_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_store.dart';

Future<TrayController> openLandscape(
  WidgetTester tester, {
  required Size size,
  DiceSet? set,
  double textScale = 1,
  FakeViewPadding padding = FakeViewPadding.zero,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = padding;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final tray = TrayController(store: MemoryStore(), roller: (_) async => 4);
  addTearDown(tray.dispose);
  await tray.load();
  tray.setLanguage('cs');
  if (set != null) tray.loadSet(set);
  final lock = OrientationLock(supported: true, request: (_) async {});
  addTearDown(lock.dispose);
  await tester.pumpWidget(EasyDiceApp(controller: tray, orientationLock: lock));
  await tester.pumpAndSettle();
  return tray;
}

Rect dieFace(WidgetTester tester, int id) =>
    tester.getRect(find.byKey(ValueKey('die-outline-$id')));

void main() {
  for (final size in [const Size(844, 390), const Size(640, 320)]) {
    testWidgets('four Czech dice use the landscape width at $size', (
      tester,
    ) async {
      final tray = await openLandscape(tester, size: size);
      expect(
        find.text(
          'Klepnutí hodí jednou kostkou. Přejetí do strany kdekoli hodí všemi.',
        ),
        findsNothing,
      );
      for (final die in tray.dice) {
        final face = dieFace(tester, die.id);
        expect(face.width, greaterThan((size.width - 80) / 4));
        final tile = find.byKey(ValueKey(die.id));
        final bounds = tester.getRect(tile);
        expect(bounds.bottom, lessThanOrEqualTo(size.height));
        final labels = find.descendant(of: tile, matching: find.byType(Text));
        for (final label in labels.evaluate()) {
          expect(
            (label.renderObject! as RenderParagraph).didExceedMaxLines,
            isFalse,
          );
        }
      }
      await tray.rollAll();
      await tester.pumpAndSettle();
      expect(tray.dice.every((die) => die.rollCount == 1), isTrue);
      expect(tester.takeException(), isNull);
    });

    for (final count in [1, 2]) {
      testWidgets('$count dice grow to the available height at $size', (
        tester,
      ) async {
        final tray = await openLandscape(
          tester,
          size: size,
          set: DiceSet('Kostky', [
            for (var i = 0; i < count; i++) DieDefinition.mercenary(),
          ]),
        );
        for (final die in tray.dice) {
          final face = dieFace(tester, die.id);
          expect(face.height, greaterThan(size.height - 180));
          expect(face.width, closeTo(face.height, .1));
          final bounds = tester.getRect(find.byKey(ValueKey(die.id)));
          expect(bounds.top, greaterThanOrEqualTo(0));
          expect(bounds.bottom, lessThanOrEqualTo(size.height));
        }
        final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
        expect(scroll.position.maxScrollExtent, closeTo(0, .1));
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('long names wrap without clipping at text scale $scale', (
      tester,
    ) async {
      const setName = 'Dlouhý název mé vlastní uložené sady kostek';
      const dieName = 'Moje žoldnéřská kostka s dlouhým názvem';
      await openLandscape(
        tester,
        size: const Size(640, 320),
        textScale: scale,
        set: DiceSet(setName, [DieDefinition.mercenary(name: dieName)]),
      );
      expect(
        tester.getSize(find.text(setName)).width,
        greaterThanOrEqualTo(320),
      );
      for (final text in [setName, dieName]) {
        await tester.scrollUntilVisible(find.text(text), 100);
        final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
      }
      final add = find.byKey(const ValueKey('landscape-add'));
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      expect(tester.getRect(add).right, lessThanOrEqualTo(640));
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('Počet stěn'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dice fit around a phone notch and enlarged text', (
    tester,
  ) async {
    final tray = await openLandscape(
      tester,
      size: const Size(844, 390),
      textScale: 1.3,
      padding: const FakeViewPadding(left: 44, right: 44, bottom: 21),
    );
    for (final die in tray.dice) {
      final tile = tester.getRect(find.byKey(ValueKey(die.id)));
      expect(tile.left, greaterThanOrEqualTo(44));
      expect(tile.right, lessThanOrEqualTo(800));
      expect(tile.bottom, lessThanOrEqualTo(369));
    }
    expect(find.byType(DieTile), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a very narrow landscape window keeps every action accessible', (
    tester,
  ) async {
    await openLandscape(tester, size: const Size(360, 240));
    for (final key in [
      'landscape-roll-all',
      'landscape-add',
      'landscape-help',
    ]) {
      final action = find.byKey(ValueKey(key));
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(action);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(360));
    }
    expect(tester.takeException(), isNull);
  });
}
