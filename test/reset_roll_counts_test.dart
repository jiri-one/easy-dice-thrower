import 'dart:async';

import 'package:easy_dice_thrower/main.dart';
import 'package:easy_dice_thrower/platform/orientation_lock.dart';
import 'package:easy_dice_thrower/tray_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_store.dart';

Future<void> press(WidgetTester tester, Finder button) async {
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

VoidCallback? callback(WidgetTester tester, Finder button) {
  final widget = tester.widget(button);
  return widget is IconButton
      ? widget.onPressed
      : (widget as ButtonStyleButton).onPressed;
}

Future<void> openMenu(WidgetTester tester) =>
    press(tester, find.byKey(const ValueKey('tray-menu')));

Future<TrayController> openResetTray(
  WidgetTester tester,
  Size size, {
  RollDie? roller,
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(1024, 768),
  ]) {
    testWidgets('reset button clears only the counters at $size', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final tray = await openResetTray(tester, size);
        await tray.rollAll();
        await tray.rollDie(tray.dice.first.id);
        await tester.pumpAndSettle();
        final ids = tray.dice.map((die) => die.id).toList();
        final values = tray.dice.map((die) => die.value).toList();
        if (size.width < size.height) await openMenu(tester);
        final reset = find.byKey(const ValueKey('reset-roll-counts'));
        await tester.ensureVisible(reset);
        await tester.pumpAndSettle();
        expect(callback(tester, reset), isNotNull);
        final data = tester.getSemantics(reset).getSemanticsData();
        expect(data.label, contains('Vynulovat počítadla'));
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        await press(tester, reset);
        expect(find.byType(Dialog), findsNothing);
        expect(tray.dice.map((die) => die.id), ids);
        expect(tray.dice.map((die) => die.value), values);
        expect(tray.dice.map((die) => die.rollCount), [0, 0, 0, 0]);
        if (size.width < size.height) await openMenu(tester);
        expect(callback(tester, reset), isNull);
        if (size.width < size.height) await press(tester, find.text('Zavřít'));
        await press(
          tester,
          find.byKey(ValueKey('die-face-${tray.dice.first.id}')),
        );
        expect(tray.dice.map((die) => die.rollCount), [1, 0, 0, 0]);
        expect(tester.takeException(), isNull);
        await tray.saved;
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('reset is disabled during a roll and updates in the open menu', (
    tester,
  ) async {
    Completer<int>? pending;
    final tray = await openResetTray(
      tester,
      const Size(390, 844),
      roller: (_) => pending?.future ?? Future.value(4),
    );
    await tray.rollAll();
    await tester.pumpAndSettle();
    pending = Completer<int>();
    final roll = tray.rollDie(tray.dice.first.id);
    await tester.pump();
    await openMenu(tester);
    final reset = find.byKey(const ValueKey('reset-roll-counts'));
    expect(callback(tester, reset), isNull);
    pending.complete(4);
    await roll;
    await tester.pumpAndSettle();
    expect(callback(tester, reset), isNotNull);
    await press(tester, reset);
    expect(tray.dice.map((die) => die.rollCount), [0, 0, 0, 0]);
    expect(tray.dice.map((die) => die.value), [4, 4, 4, 4]);
    expect(tester.takeException(), isNull);
    await tray.saved;
  });

  testWidgets('the reset label stays readable with doubled system text', (
    tester,
  ) async {
    final tray = await openResetTray(tester, const Size(320, 640), scale: 2);
    await tray.rollAll();
    await tester.pumpAndSettle();
    await openMenu(tester);
    final label = find.text('Vynulovat počítadla');
    await tester.ensureVisible(label);
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(label);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
    await press(tester, find.byKey(const ValueKey('reset-roll-counts')));
    expect(tray.dice.every((die) => die.rollCount == 0), isTrue);
    expect(tester.takeException(), isNull);
    await tray.saved;
  });
}
