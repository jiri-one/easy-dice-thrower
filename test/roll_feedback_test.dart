import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:easy_dice_thrower/main.dart';
import 'package:easy_dice_thrower/tray_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_store.dart';

Future<TrayController> openFeedbackTray(
  WidgetTester tester, {
  RollDie? roller,
}) async {
  final tray = TrayController(
    store: MemoryStore(),
    roller: roller ?? (_) async => 1,
  );
  await tray.load();
  tray.setLanguage('cs');
  addTearDown(tray.dispose);
  await tester.pumpWidget(EasyDiceApp(controller: tray));
  await tester.pumpAndSettle();
  return tray;
}

Finder feedback(int id) => find.byKey(ValueKey('roll-feedback-$id'));

Color? feedbackColor(WidgetTester tester, int id) =>
    (tester.widget<Container>(feedback(id)).decoration as BoxDecoration).color;

Finder confirmation(int id) =>
    find.descendant(of: feedback(id), matching: find.byIcon(Icons.check));

void main() {
  testWidgets(
    'every blank outcome visibly changes the persistent confirmation',
    (tester) async {
      final results = [1, 1, 2, 3].iterator;
      final tray = await openFeedbackTray(
        tester,
        roller: (_) async {
          results.moveNext();
          return results.current;
        },
      );
      final id = tray.dice[1].id;
      final face = find.byKey(ValueKey('die-face-$id'));
      await tester.ensureVisible(face);
      expect(confirmation(id), findsNothing);
      var previousColor = feedbackColor(tester, id);
      for (var count = 1; count <= 4; count++) {
        await tester.tap(face);
        await tester.pumpAndSettle();
        expect(tray.dice[1].rollCount, count);
        expect(tray.dice[1].face!.asset, 'assets/mercenary/blank.jpg');
        expect(confirmation(id), findsOneWidget);
        final color = feedbackColor(tester, id);
        expect(color, isNot(previousColor));
        expect(
          find.descendant(
            of: feedback(id),
            matching: find.textContaining('hod $count'),
          ),
          findsOneWidget,
        );
        previousColor = color;
      }
      expect(
        tray.dice
            .where((die) => die.id != id)
            .every((die) => die.value == null),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 5));
      expect(feedbackColor(tester, id), previousColor);
      expect(confirmation(id), findsOneWidget);
      await tester.drag(face, const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(tray.dice[1].rollCount, 4);
      expect(feedbackColor(tester, id), previousColor);
      expect(tester.takeException(), isNull);
    },
  );

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets(
      '$kind press is immediate but cancellation never confirms a roll',
      (tester) async {
        final tray = await openFeedbackTray(tester);
        final id = tray.dice.first.id;
        final face = find.byKey(ValueKey('die-face-$id'));
        final outline = find.byKey(ValueKey('die-outline-$id'));
        Color outlineColor() =>
            ((tester.widget<DecoratedBox>(outline).decoration as BoxDecoration)
                        .border
                    as Border)
                .top
                .color;
        await tester.ensureVisible(face);
        expect(outlineColor(), Colors.transparent);
        final cancelled = await tester.startGesture(
          tester.getCenter(face),
          kind: kind,
        );
        await tester.pump();
        expect(outlineColor(), Colors.black);
        expect(tray.dice.first.rollCount, 0);
        expect(confirmation(id), findsNothing);
        await cancelled.cancel();
        await tester.pumpAndSettle();
        expect(outlineColor(), Colors.transparent);
        expect(tray.dice.first.rollCount, 0);
        expect(confirmation(id), findsNothing);
        final accepted = await tester.startGesture(
          tester.getCenter(face),
          kind: kind,
        );
        await tester.pump();
        expect(outlineColor(), Colors.black);
        await accepted.up();
        await tester.pumpAndSettle();
        expect(tray.dice.first.rollCount, 1);
        expect(confirmation(id), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'roll all, swipe, keyboard and confirmation strip acknowledge rolls',
    (tester) async {
      final tray = await openFeedbackTray(tester);
      await tester.tap(find.text('Hodit všemi'));
      await tester.pumpAndSettle();
      for (final die in tray.dice) {
        expect(die.rollCount, 1);
        expect(confirmation(die.id), findsOneWidget);
        expect(feedbackColor(tester, die.id), Colors.black);
      }
      final id = tray.dice.first.id;
      final face = find.byKey(ValueKey('die-face-$id'));
      await tester.ensureVisible(face);
      await tester.drag(face, const Offset(80, 0));
      await tester.pumpAndSettle();
      for (final die in tray.dice) {
        expect(die.rollCount, 2);
        expect(feedbackColor(tester, die.id), Colors.white);
      }
      await tester.tap(face);
      await tester.pumpAndSettle();
      expect(tray.dice.first.rollCount, 3);
      expect(feedbackColor(tester, id), Colors.black);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(tray.dice.first.rollCount, 4);
      expect(feedbackColor(tester, id), Colors.white);
      await tester.tap(feedback(id));
      await tester.pumpAndSettle();
      expect(tray.dice.first.rollCount, 5);
      expect(feedbackColor(tester, id), Colors.black);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending and failed rolls never claim another successful roll', (
    tester,
  ) async {
    var pending = Completer<int>();
    final tray = await openFeedbackTray(tester, roller: (_) => pending.future);
    final id = tray.dice.first.id;
    final face = find.byKey(ValueKey('die-face-$id'));
    await tester.ensureVisible(face);
    await tester.tap(face);
    await tester.pump();
    expect(tray.isRolling(id), isTrue);
    expect(tray.dice.first.rollCount, 0);
    expect(confirmation(id), findsNothing);
    expect(find.text('Hážu…'), findsOneWidget);
    pending.completeError(StateError('Unavailable'));
    await tester.pumpAndSettle();
    expect(tray.operationError, TrayMessage.rollFailed);
    expect(tray.dice.first.rollCount, 0);
    expect(confirmation(id), findsNothing);
    pending = Completer<int>();
    await tester.ensureVisible(face);
    await tester.tap(face);
    await tester.pump();
    pending.complete(1);
    await tester.pumpAndSettle();
    expect(tray.dice.first.rollCount, 1);
    expect(confirmation(id), findsOneWidget);
    final color = feedbackColor(tester, id);
    pending = Completer<int>();
    await tester.tap(face);
    await tester.pump();
    expect(confirmation(id), findsNothing);
    expect(tray.dice.first.rollCount, 1);
    pending.completeError(StateError('Unavailable'));
    await tester.pumpAndSettle();
    expect(tray.dice.first.rollCount, 1);
    expect(confirmation(id), findsOneWidget);
    expect(feedbackColor(tester, id), color);
    expect(tester.takeException(), isNull);
  });
}
