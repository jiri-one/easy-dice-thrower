import 'package:easy_dice_thrower/main.dart';
import 'package:easy_dice_thrower/platform/orientation_lock.dart';
import 'package:easy_dice_thrower/tray_controller.dart';
import 'package:easy_dice_thrower/widgets/die_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_store.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('mobile web controls fit $size with safe insets', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding =
          size.width > size.height
              ? const FakeViewPadding(left: 44, right: 44, bottom: 21)
              : const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      final tray = TrayController(store: MemoryStore(), roller: (_) async => 1);
      addTearDown(tray.dispose);
      await tray.load();
      tray.setLanguage('en');
      final lock = OrientationLock(supported: false);
      addTearDown(lock.dispose);
      await tester.pumpWidget(
        EasyDiceApp(controller: tray, orientationLock: lock),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('orientation-picker')), findsNothing);
      final face = find.byKey(ValueKey('die-face-${tray.dice.first.id}'));
      await tester.ensureVisible(face);
      await tester.tap(face);
      await tester.pumpAndSettle();
      expect(tray.dice.first.rollCount, 1);
      expect(find.byType(DieTile), findsNWidgets(4));
      if (size.width <= size.height) {
        await tester.tap(find.byKey(const ValueKey('tray-menu')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('orientation-picker')), findsNothing);
      }
      final add =
          size.width > size.height
              ? find.byKey(const ValueKey('landscape-add'))
              : find.text('Add dice');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('Number of sides'), findsOneWidget);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = Size(size.height, size.width);
      await tester.pumpAndSettle();
      expect(tray.dice.first.rollCount, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
