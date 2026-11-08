import 'dart:async';
import 'dart:convert';

import 'package:easy_dice_thrower/main.dart';
import 'package:easy_dice_thrower/models/dice.dart';
import 'package:easy_dice_thrower/models/tray_orientation.dart';
import 'package:easy_dice_thrower/platform/orientation_lock.dart';
import 'package:easy_dice_thrower/tray_controller.dart';
import 'package:easy_dice_thrower/widgets/die_tile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'an unknown saved orientation falls back without discarding the tray',
    () async {
      final store = MemoryStore();
      final tray = TrayController(store: store, roller: (_) async => 4);
      addTearDown(tray.dispose);
      await tray.load();
      await tray.rollAll();
      await tray.saved;
      final data = jsonDecode(store.value!) as Map<String, dynamic>;
      data['orientation'] = 'unknown';
      store.value = jsonEncode(data);
      final restored = TrayController(store: store);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.storageWarning, isNull);
      expect(restored.orientation, TrayOrientation.portrait);
      expect(restored.dice.map((die) => die.value), [4, 4, 4, 4]);
    },
  );

  testWidgets('landscape controls remain usable with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final tray = TrayController(store: MemoryStore());
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
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('landscape-add')));
    await tester.pumpAndSettle();
    expect(find.text('Number of sides'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tray.saved;
  });

  test(
    'native phone requests exactly one fixed direction for each mode',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final calls = <List<Object?>>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          calls.add((call.arguments as List).cast<Object?>());
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final lock = OrientationLock();
      addTearDown(lock.dispose);
      expect(lock.supported, isTrue);
      lock.apply(TrayOrientation.portrait);
      await lock.settled;
      lock.apply(TrayOrientation.landscape);
      await lock.settled;
      lock.apply(TrayOrientation.landscape);
      await lock.settled;
      expect(calls, [
        ['DeviceOrientation.portraitUp'],
        ['DeviceOrientation.landscapeLeft'],
      ]);
      expect(lock.failed, isFalse);
    },
  );

  test('desktop never requests device orientation changes', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var called = false;
    final lock = OrientationLock(request: (_) async => called = true);
    addTearDown(lock.dispose);
    expect(lock.supported, isFalse);
    lock.apply(TrayOrientation.landscape);
    await lock.settled;
    expect(called, isFalse);
  });

  test('rapid changes finish in the last chosen orientation', () async {
    final first = Completer<void>();
    final calls = <TrayOrientation>[];
    final lock = OrientationLock(
      supported: true,
      request: (orientation) async {
        calls.add(orientation);
        if (calls.length == 1) await first.future;
      },
    );
    addTearDown(lock.dispose);
    lock.apply(TrayOrientation.portrait);
    await Future<void>.delayed(Duration.zero);
    lock.apply(TrayOrientation.landscape);
    lock.apply(TrayOrientation.portrait);
    lock.apply(TrayOrientation.landscape);
    first.complete();
    await lock.settled;
    expect(calls, [TrayOrientation.portrait, TrayOrientation.landscape]);
  });

  test('a failed request is reported and can be retried', () async {
    var fail = true;
    final lock = OrientationLock(
      supported: true,
      request: (_) async {
        if (fail) throw PlatformException(code: 'orientation');
      },
    );
    addTearDown(lock.dispose);
    lock.apply(TrayOrientation.portrait);
    await lock.settled;
    expect(lock.failed, isTrue);
    fail = false;
    lock.apply(TrayOrientation.portrait, retry: true);
    await lock.settled;
    expect(lock.failed, isFalse);
  });

  test(
    'the orientation preference survives loading sets and restarting',
    () async {
      final store = MemoryStore();
      final tray = TrayController(store: store, roller: (_) async => 4);
      addTearDown(tray.dispose);
      await tray.load();
      expect(tray.orientation, TrayOrientation.portrait);
      tray.setLanguage('cs');
      tray.loadSet(builtInSets[1]);
      await tray.rollAll();
      tray.setOrientation(TrayOrientation.landscape);
      await tray.saved;
      final restored = TrayController(store: store);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.orientation, TrayOrientation.landscape);
      expect(restored.language, 'cs');
      expect(restored.preset, DicePreset.classic);
      expect(restored.dice.map((die) => die.value), [4, 4]);
      expect(restored.dice.map((die) => die.rollCount), [1, 1]);
      restored.loadSet(builtInSets.first);
      expect(restored.orientation, TrayOrientation.landscape);
      await restored.saved;
    },
  );

  for (final size in [const Size(844, 390), const Size(640, 320)]) {
    testWidgets('four dice fit in one row on a $size landscape phone', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tray = TrayController(store: MemoryStore(), roller: (_) async => 4);
      addTearDown(tray.dispose);
      await tray.load();
      tray.setLanguage('en');
      tray.setOrientation(TrayOrientation.landscape);
      final requests = <TrayOrientation>[];
      final lock = OrientationLock(
        supported: true,
        request: (value) async => requests.add(value),
      );
      addTearDown(lock.dispose);
      await tester.pumpWidget(
        EasyDiceApp(controller: tray, orientationLock: lock),
      );
      await tester.pumpAndSettle();
      await lock.settled;
      expect(find.byKey(const ValueKey('landscape-tray')), findsOneWidget);
      final rectangles =
          find
              .byType(DieTile)
              .evaluate()
              .map((element) => tester.getRect(find.byWidget(element.widget)))
              .toList();
      expect(rectangles, hasLength(4));
      for (final rectangle in rectangles) {
        expect(rectangle.top, closeTo(rectangles.first.top, .1));
        expect(rectangle.bottom, lessThanOrEqualTo(size.height));
        expect(rectangle.left, greaterThanOrEqualTo(0));
        expect(rectangle.right, lessThanOrEqualTo(size.width));
      }
      await tester.tap(find.byKey(const ValueKey('landscape-roll-all')));
      await tester.pumpAndSettle();
      expect(tray.dice.every((die) => die.rollCount == 1), isTrue);
      expect(requests, [TrayOrientation.landscape]);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(tray.dice.every((die) => die.rollCount == 1), isTrue);
      expect(requests, [TrayOrientation.landscape]);
      expect(tester.takeException(), isNull);
      await tray.saved;
    });
  }

  testWidgets('a manual switch applies portrait without resetting the tray', (
    tester,
  ) async {
    final tray = TrayController(store: MemoryStore(), roller: (_) async => 6);
    addTearDown(tray.dispose);
    await tray.load();
    tray.setLanguage('cs');
    await tray.rollAll();
    final requests = <TrayOrientation>[];
    final lock = OrientationLock(
      supported: true,
      request: (value) async => requests.add(value),
    );
    addTearDown(lock.dispose);
    await tester.pumpWidget(
      EasyDiceApp(controller: tray, orientationLock: lock),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('orientation-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('orientation-landscape')));
    await tester.pumpAndSettle();
    await lock.settled;
    expect(tray.orientation, TrayOrientation.landscape);
    await tester.tap(find.byKey(const ValueKey('orientation-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('orientation-portrait')));
    await tester.pumpAndSettle();
    await lock.settled;
    expect(requests, [
      TrayOrientation.portrait,
      TrayOrientation.landscape,
      TrayOrientation.portrait,
    ]);
    expect(tray.dice.every((die) => die.rollCount == 1), isTrue);
    expect(tray.dice.map((die) => die.value), [6, 6, 6, 6]);
    expect(tester.takeException(), isNull);
    await tray.saved;
  });
}
