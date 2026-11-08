import 'package:easy_dice_thrower/l10n/generated/app_localizations.dart';
import 'package:easy_dice_thrower/main.dart';
import 'package:easy_dice_thrower/platform/orientation_lock.dart';
import 'package:easy_dice_thrower/tray_controller.dart';
import 'package:easy_dice_thrower/widgets/die_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_store.dart';

Future<TrayController> openControls(
  WidgetTester tester, {
  String language = 'en',
  RollDie? roller,
}) async {
  final tray = TrayController(
    store: MemoryStore(),
    roller: roller ?? (_) async => 1,
  );
  addTearDown(tray.dispose);
  await tray.load();
  tray.setLanguage(language);
  final lock = OrientationLock(supported: true, request: (_) async {});
  addTearDown(lock.dispose);
  await tester.pumpWidget(EasyDiceApp(controller: tray, orientationLock: lock));
  await tester.pumpAndSettle();
  return tray;
}

Future<void> activate(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void expectAction(WidgetTester tester, Finder target, String label) {
  final data = tester.getSemantics(target).getSemanticsData();
  expect(data.label, contains(label));
  expect(data.flagsCollection.isButton, isTrue);
  expect(data.hasAction(SemanticsAction.tap), isTrue);
}

void main() {
  testWidgets(
    'die controls, saved-set delete and error dismiss are labelled actions',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        final labels = await AppLocalizations.delegate.load(const Locale('en'));
        final tray = await openControls(
          tester,
          roller: (_) async => throw StateError('Failed'),
        );
        tray.saveSet('Campaign');
        await tester.pumpAndSettle();
        expectAction(
          tester,
          find.byKey(const ValueKey('language-picker')),
          labels.languageTitle,
        );
        await activate(tester, find.text('Edit'));
        final tile = find.byType(DieTile).first;
        for (final (icon, label) in [
          (Icons.remove, labels.removeDieAction(1)),
          (Icons.edit_outlined, labels.editDieAction(1)),
          (Icons.add, labels.duplicateDieAction(1)),
        ]) {
          final target = find.descendant(of: tile, matching: find.byIcon(icon));
          await tester.ensureVisible(target);
          await tester.pump();
          expectAction(tester, target, label);
        }
        await activate(tester, find.text('Done'));
        await activate(tester, find.text('Sets'));
        final delete = find.byIcon(Icons.delete_outline);
        await tester.ensureVisible(delete);
        await tester.pump();
        expectAction(tester, delete, labels.deleteSetAction('Campaign'));
        await activate(tester, find.text('Close'));
        await tray.rollDie(tray.dice.first.id);
        await tester.pumpAndSettle();
        final dismiss = find.byIcon(Icons.close);
        await tester.ensureVisible(dismiss);
        await tester.pump();
        expectAction(tester, dismiss, labels.dismissMessage);
        expect(
          tester
              .getSemantics(find.text(labels.rollFailed))
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets(
    'landscape icons expose the label and activation on the same node',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final handle = tester.ensureSemantics();
      try {
        final labels = await AppLocalizations.delegate.load(const Locale('en'));
        await openControls(tester);
        for (final (key, label) in [
          ('landscape-roll-all', labels.rollAll),
          ('landscape-add', labels.addDice),
          ('language-picker', labels.languageTitle),
          ('orientation-picker', labels.orientationTitle),
        ]) {
          expectAction(tester, find.byKey(ValueKey(key)), label);
        }
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets('Czech portrait menu keeps whole labels with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final labels = await AppLocalizations.delegate.load(const Locale('cs'));
    await openControls(tester, language: 'cs');
    await activate(tester, find.byKey(const ValueKey('tray-menu')));
    for (final label in [
      labels.rollAll,
      labels.addDice,
      labels.sets,
      labels.edit,
      labels.save,
    ]) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      expect(paragraph.overflow, isNot(TextOverflow.ellipsis), reason: label);
    }
    await activate(tester, find.text(labels.edit));
    await activate(tester, find.byKey(const ValueKey('tray-menu')));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text(labels.done),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.takeException(), isNull);
  });
}
