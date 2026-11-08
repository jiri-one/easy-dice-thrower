import 'dart:async';

import 'package:easy_dice_thrower/main.dart';
import 'package:easy_dice_thrower/models/dice.dart';
import 'package:easy_dice_thrower/platform/orientation_lock.dart';
import 'package:easy_dice_thrower/tray_controller.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_store.dart';

Future<TrayController> openSwipeTray(
  WidgetTester tester, {
  Size size = const Size(844, 390),
  RollDie? roller,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final tray = TrayController(
    store: MemoryStore(),
    roller: roller ?? (_) async => 4,
  );
  addTearDown(tray.dispose);
  await tray.load();
  tray.setLanguage('cs');
  final lock = OrientationLock(supported: false);
  addTearDown(lock.dispose);
  await tester.pumpWidget(EasyDiceApp(controller: tray, orientationLock: lock));
  await tester.pumpAndSettle();
  return tray;
}

void expectRolls(TrayController tray, List<int> counts) =>
    expect(tray.dice.map((die) => die.rollCount), counts);

void main() {
  for (final size in [
    const Size(844, 390),
    const Size(640, 320),
    const Size(390, 844),
    const Size(1600, 1000),
  ]) {
    testWidgets(
      'swipes from either margin roll every die exactly once at $size',
      (tester) async {
        final tray = await openSwipeTray(tester, size: size);
        final surface = tester.getRect(
          find.byKey(const ValueKey('roll-surface')),
        );
        expect(surface.size, size);
        await tester.dragFrom(
          Offset(surface.left + 4, surface.bottom - 4),
          const Offset(120, 0),
        );
        await tester.pumpAndSettle();
        expectRolls(tray, [1, 1, 1, 1]);
        await tester.dragFrom(
          Offset(surface.right - 4, surface.bottom - 4),
          const Offset(-120, 0),
        );
        await tester.pumpAndSettle();
        expectRolls(tray, [2, 2, 2, 2]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a swipe across a die rolls all; a tap still rolls just that die',
    (tester) async {
      final tray = await openSwipeTray(tester);
      final face = find.byKey(ValueKey('die-face-${tray.dice[1].id}'));
      await tester.drag(face, const Offset(-100, 0));
      await tester.pumpAndSettle();
      expectRolls(tray, [1, 1, 1, 1]);
      await tester.tap(face);
      await tester.pumpAndSettle();
      expectRolls(tray, [1, 2, 1, 1]);
      final feedback = find.byKey(ValueKey('roll-feedback-${tray.dice[2].id}'));
      await tester.drag(feedback, const Offset(100, 0));
      await tester.pumpAndSettle();
      expectRolls(tray, [2, 3, 2, 2]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('swiping the toolbar rolls once without activating its button', (
    tester,
  ) async {
    final tray = await openSwipeTray(tester);
    await tester.drag(
      find.byKey(const ValueKey('landscape-add')),
      const Offset(-100, 0),
    );
    await tester.pumpAndSettle();
    expectRolls(tray, [1, 1, 1, 1]);
    expect(find.text('Počet stěn'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('landscape-add')));
    await tester.pumpAndSettle();
    expect(find.text('Počet stěn'), findsOneWidget);
    await tester.dragFrom(const Offset(20, 200), const Offset(100, 0));
    await tester.pumpAndSettle();
    expectRolls(tray, [1, 1, 1, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short, vertical and cancelled background gestures do not roll', (
    tester,
  ) async {
    final tray = await openSwipeTray(tester);
    final origin =
        tester.getBottomLeft(find.byKey(const ValueKey('roll-surface'))) +
        const Offset(4, -4);
    final short = await tester.startGesture(origin);
    await short.moveBy(const Offset(24, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await short.up();
    await tester.pumpAndSettle();
    expectRolls(tray, [0, 0, 0, 0]);
    final cancelled = await tester.startGesture(origin);
    await cancelled.moveBy(const Offset(100, 0));
    await cancelled.cancel();
    await tester.pumpAndSettle();
    expectRolls(tray, [0, 0, 0, 0]);
    final face = find.byKey(ValueKey('die-face-${tray.dice.first.id}'));
    await tester.drag(face, const Offset(0, -100));
    await tester.pumpAndSettle();
    expectRolls(tray, [0, 0, 0, 0]);
    await tester.dragFrom(origin, const Offset(100, 0));
    await tester.pumpAndSettle();
    expectRolls(tray, [1, 1, 1, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vertical scrolling a large tray never rolls any dice', (
    tester,
  ) async {
    final tray = await openSwipeTray(tester);
    tray.addDice(DieDefinition.mercenary(), 20);
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, 0);
    await tester.dragFrom(const Offset(300, 280), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(0));
    expect(tray.dice.every((die) => die.rollCount == 0), isTrue);
    await tester.dragFrom(const Offset(300, 200), const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(tray.dice.every((die) => die.rollCount == 1), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swipes do not roll in edit mode or during a pending roll', (
    tester,
  ) async {
    final pending = Completer<int>();
    var calls = 0;
    final tray = await openSwipeTray(
      tester,
      roller: (_) {
        calls++;
        return pending.future;
      },
    );
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(4, 300), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('die-face-${tray.dice.first.id}')));
    await tester.pump();
    expect(calls, 1);
    await tester.dragFrom(const Offset(4, 300), const Offset(120, 0));
    await tester.pump();
    expect(calls, 1);
    pending.complete(4);
    await tester.pumpAndSettle();
    expectRolls(tray, [1, 0, 0, 0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gesture help opens on demand without rolling any dice', (
    tester,
  ) async {
    final tray = await openSwipeTray(tester);
    const hint =
        'Klepnutí hodí jednou kostkou. Přejetí do strany kdekoli hodí všemi.';
    expect(find.text(hint), findsNothing);
    await tester.tap(find.byKey(const ValueKey('landscape-help')));
    await tester.pumpAndSettle();
    expect(find.text(hint), findsOneWidget);
    await tester.tap(find.text('Zavřít'));
    await tester.pumpAndSettle();
    expect(find.text(hint), findsNothing);
    expectRolls(tray, [0, 0, 0, 0]);
    expect(tester.takeException(), isNull);
  });

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('tilted vertical $kind drags never roll dice', (tester) async {
      final tray = await openSwipeTray(tester, size: const Size(390, 844));
      for (final origin in [
        const Offset(20, 800),
        tester.getCenter(find.byKey(ValueKey('die-face-${tray.dice.last.id}'))),
      ]) {
        final gesture = await tester.startGesture(origin, kind: kind);
        for (var i = 0; i < 10; i++) {
          await gesture.moveBy(const Offset(4, -30));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expectRolls(tray, [0, 0, 0, 0]);
      }
      final horizontal = await tester.startGesture(
        const Offset(20, 800),
        kind: kind,
      );
      for (var i = 0; i < 10; i++) {
        await horizontal.moveBy(const Offset(10, -2));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await horizontal.up();
      await tester.pumpAndSettle();
      expectRolls(tray, [1, 1, 1, 1]);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (initialPan, closeBeforeEnd) in [
    (80.0, false),
    (80.0, true),
    (10.0, true),
  ]) {
    testWidgets(
      'opening a menu cancels a trackpad gesture ($initialPan, $closeBeforeEnd)',
      (tester) async {
        final tray = await openSwipeTray(tester, size: const Size(390, 844));
        final menu = find.byKey(const ValueKey('tray-menu'));
        final icon = find.descendant(
          of: menu,
          matching: find.byIcon(Icons.menu),
        );
        Focus.of(tester.element(icon)).requestFocus();
        await tester.pump();
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        const origin = Offset(20, 800);
        await gesture.panZoomStart(origin);
        await gesture.panZoomUpdate(origin, pan: Offset(initialPan, 0));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        if (closeBeforeEnd) {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          await gesture.panZoomUpdate(origin, pan: const Offset(100, 0));
        }
        await gesture.panZoomEnd();
        await tester.pumpAndSettle();
        expectRolls(tray, [0, 0, 0, 0]);
        if (!closeBeforeEnd) {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        }
        await tester.dragFrom(origin, const Offset(100, 0));
        await tester.pumpAndSettle();
        expectRolls(tray, [1, 1, 1, 1]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a full-result dialog also cancels an active trackpad gesture', (
    tester,
  ) async {
    final tray = await openSwipeTray(
      tester,
      size: const Size(390, 844),
      roller: (_) async => 1,
    );
    tray.loadSet(
      DiceSet('Text', [
        DieDefinition.text('Odpověď', ['Ano', 'Ne']),
      ]),
    );
    await tray.rollAll();
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('Celý výsledek'))).requestFocus();
    await tester.pump();
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    const origin = Offset(20, 800);
    await gesture.panZoomStart(origin);
    await gesture.panZoomUpdate(origin, pan: const Offset(80, 0));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();
    expectRolls(tray, [1]);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.dragFrom(origin, const Offset(100, 0));
    await tester.pumpAndSettle();
    expectRolls(tray, [2]);
    expect(tester.takeException(), isNull);
  });
}
