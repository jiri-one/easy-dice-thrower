import 'package:easy_dice_thrower/l10n/generated/app_localizations.dart';
import 'package:easy_dice_thrower/main.dart';
import 'package:easy_dice_thrower/models/dice.dart';
import 'package:easy_dice_thrower/models/tray_orientation.dart';
import 'package:easy_dice_thrower/platform/orientation_lock.dart';
import 'package:easy_dice_thrower/tray_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_store.dart';

Future<TrayController> openPortrait(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  String language = 'cs',
  double textScale = 1,
  FakeViewPadding padding = FakeViewPadding.zero,
  List<TrayOrientation>? requests,
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
  tray.setLanguage(language);
  final lock = OrientationLock(
    supported: requests != null,
    request: (orientation) async => requests?.add(orientation),
  );
  addTearDown(lock.dispose);
  await tester.pumpWidget(EasyDiceApp(controller: tray, orientationLock: lock));
  await tester.pumpAndSettle();
  return tray;
}

Future<void> choose(WidgetTester tester, Finder action) async {
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Future<void> menu(WidgetTester tester) =>
    choose(tester, find.byKey(const ValueKey('tray-menu')));

List<Rect> faces(WidgetTester tester, TrayController tray) => [
  for (final die in tray.dice)
    tester.getRect(find.byKey(ValueKey('die-outline-${die.id}'))),
];

void main() {
  for (final (size, scale, padding) in [
    (const Size(320, 568), 1.0, FakeViewPadding.zero),
    (const Size(320, 640), 1.0, const FakeViewPadding(top: 24, bottom: 24)),
    (const Size(390, 844), 1.3, const FakeViewPadding(top: 47, bottom: 34)),
  ]) {
    for (final language in ['en', 'cs']) {
      testWidgets('four $language dice fit $size at text scale $scale', (
        tester,
      ) async {
        final tray = await openPortrait(
          tester,
          size: size,
          language: language,
          textScale: scale,
          padding: padding,
        );
        expect(find.byKey(const ValueKey('portrait-tray')), findsOneWidget);
        expect(find.byType(IconButton), findsOneWidget);
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(OutlinedButton), findsNothing);
        final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
        expect(scroll.position.maxScrollExtent, closeTo(0, .1));
        final originalFaces = faces(tester, tray);
        for (final die in tray.dice) {
          final tile = tester.getRect(find.byKey(ValueKey(die.id)));
          expect(tile.top, greaterThanOrEqualTo(padding.top));
          expect(tile.bottom, lessThanOrEqualTo(size.height - padding.bottom));
          expect(tile.left, greaterThanOrEqualTo(0));
          expect(tile.right, lessThanOrEqualTo(size.width));
          expect(
            tester.getSize(find.byKey(ValueKey('die-outline-${die.id}'))).width,
            greaterThan((size.width - 80) / 2),
          );
        }
        await tray.rollAll();
        await tester.pumpAndSettle();
        expect(faces(tester, tray), originalFaces);
        expect(scroll.position.maxScrollExtent, closeTo(0, .1));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the labelled menu closes after rolling without moving dice', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final tray = await openPortrait(tester);
      final labels = await AppLocalizations.delegate.load(const Locale('cs'));
      final button = find.byKey(const ValueKey('tray-menu'));
      final data = tester.getSemantics(button).getSemanticsData();
      expect(data.label, contains(labels.trayMenuTitle));
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      final originalFaces = faces(tester, tray);
      expect(find.text(labels.rollAll), findsNothing);
      await menu(tester);
      for (final label in [
        labels.rollAll,
        labels.addDice,
        labels.sets,
        labels.edit,
        labels.save,
        labels.languageTitle,
        labels.rollHelpTitle,
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await choose(tester, find.text(labels.rollAll));
      expect(find.byType(Dialog), findsNothing);
      expect(tray.dice.map((die) => die.rollCount), [1, 1, 1, 1]);
      expect(faces(tester, tray), originalFaces);
      await menu(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tray.dice.map((die) => die.rollCount), [1, 1, 1, 1]);
      expect(faces(tester, tray), originalFaces);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('menu actions open one dialog and editing has a direct exit', (
    tester,
  ) async {
    final tray = await openPortrait(tester);
    await menu(tester);
    await choose(tester, find.text('Přidat kostky'));
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Počet stěn'), findsOneWidget);
    expect(find.text('Nabídka'), findsNothing);
    await choose(tester, find.text('Zrušit'));
    expect(find.byType(Dialog), findsNothing);
    await menu(tester);
    await choose(tester, find.text('Upravit'));
    expect(find.byType(Dialog), findsNothing);
    expect(find.byIcon(Icons.remove), findsNWidgets(4));
    await choose(tester, find.byKey(const ValueKey('portrait-done')));
    expect(find.byIcon(Icons.remove), findsNothing);
    expect(find.byKey(const ValueKey('portrait-done')), findsNothing);
    expect(tray.dice.map((die) => die.rollCount), [0, 0, 0, 0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('language, orientation and resizing preserve the current rolls', (
    tester,
  ) async {
    final requests = <TrayOrientation>[];
    final tray = await openPortrait(tester, requests: requests);
    await tray.rollAll();
    await tester.pumpAndSettle();
    final ids = tray.dice.map((die) => die.id).toList();
    await menu(tester);
    await choose(tester, find.byKey(const ValueKey('language-picker')));
    await choose(tester, find.text('English'));
    expect(find.byType(Dialog), findsNothing);
    expect(tray.language, 'en');
    await menu(tester);
    await choose(tester, find.byKey(const ValueKey('orientation-picker')));
    await choose(tester, find.byKey(const ValueKey('orientation-landscape')));
    expect(tray.orientation, TrayOrientation.landscape);
    expect(requests, [TrayOrientation.portrait, TrayOrientation.landscape]);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('landscape-tray')), findsOneWidget);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tray-menu')), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(tray.dice.map((die) => die.id), ids);
    expect(tray.dice.map((die) => die.value), [4, 4, 4, 4]);
    expect(tray.dice.map((die) => die.rollCount), [1, 1, 1, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('doubled text and a large tray stay readable and scrollable', (
    tester,
  ) async {
    final tray = await openPortrait(
      tester,
      size: const Size(320, 640),
      textScale: 2,
    );
    tray.addDice(DieDefinition.mercenary(), 8);
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    await tester.dragFrom(const Offset(160, 500), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(0));
    expect(tray.dice.every((die) => die.rollCount == 0), isTrue);
    final last = find.byKey(ValueKey('die-face-${tray.dice.last.id}'));
    await choose(tester, last);
    expect(tray.dice.last.rollCount, 1);
    await menu(tester);
    await choose(tester, find.byKey(const ValueKey('language-picker')));
    expect(find.text('Čeština'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long saved title leaves dice and editing controls reachable', (
    tester,
  ) async {
    final tray = await openPortrait(
      tester,
      size: const Size(320, 480),
      textScale: 2,
      padding: const FakeViewPadding(top: 24, bottom: 24),
    );
    tray.saveSet('W' * 48);
    await tester.pumpAndSettle();
    final title = find.byKey(const ValueKey('portrait-full-title'));
    expect(
      tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
      isFalse,
    );
    final header =
        find
            .descendant(
              of: find.byType(PinnedHeaderSliver),
              matching: find.byType(ColoredBox),
            )
            .first;
    expect(tester.getSize(header).height, lessThan(432 / 3));
    final last = find.byKey(ValueKey('die-face-${tray.dice.last.id}'));
    await tester.scrollUntilVisible(last, 100);
    await choose(tester, last);
    expect(tray.dice.map((die) => die.rollCount), [0, 0, 0, 1]);
    await menu(tester);
    await choose(tester, find.text('Upravit'));
    expect(tester.getSize(header).height, lessThan(432 / 3));
    await choose(tester, find.byKey(const ValueKey('portrait-done')));
    expect(find.byKey(const ValueKey('portrait-done')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 568),
    const Size(360, 800),
    const Size(375, 667),
    const Size(800, 360),
  ]) {
    testWidgets('seven dice keep a dense readable grid at $size', (
      tester,
    ) async {
      final tray = await openPortrait(tester, size: size);
      tray.loadSet(builtInSets[2]);
      await tester.pumpAndSettle();
      final tiles = [
        for (final die in tray.dice)
          tester.getRect(find.byKey(ValueKey(die.id))),
      ];
      final firstRow = tiles.where(
        (tile) => (tile.top - tiles.first.top).abs() < .1,
      );
      expect(
        firstRow.length,
        greaterThanOrEqualTo(size.width > size.height ? 6 : 2),
      );
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scroll.position.maxScrollExtent, lessThan(size.height));
      expect(tester.takeException(), isNull);
    });
  }
}
