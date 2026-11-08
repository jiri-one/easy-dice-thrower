import 'dart:convert';
import 'dart:io';

import 'package:easy_dice_thrower/l10n/generated/app_localizations.dart';
import 'package:easy_dice_thrower/l10n/localized_labels.dart';
import 'package:easy_dice_thrower/main.dart';
import 'package:easy_dice_thrower/models/dice.dart';
import 'package:easy_dice_thrower/tray_controller.dart';
import 'package:easy_dice_thrower/widgets/static_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_store.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('English controls fit a small screen at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final tray = TrayController(store: MemoryStore());
      addTearDown(tray.dispose);
      await tray.load();
      tray.setLanguage('en');
      await tester.pumpWidget(EasyDiceApp(controller: tray));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('tray-menu')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add dice'));
      await tester.tap(find.text('Add dice'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Swords'));
      await tester.tap(find.text('Swords'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tray-menu')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('language-picker')));
      await tester.tap(find.byKey(const ValueKey('language-picker')));
      await tester.pumpAndSettle();
      expect(find.text('Use device language'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Čeština'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Close'));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tray.saved;
    });
  }

  test('both officially supported catalogs contain every message', () {
    Set<String> keys(String code) {
      final data =
          jsonDecode(File('lib/l10n/app_$code.arb').readAsStringSync()) as Map;
      return data.keys
          .cast<String>()
          .where((key) => !key.startsWith('@'))
          .toSet();
    }

    expect(keys('cs'), keys('en'));
    expect(
      AppLocalizations.supportedLocales.map((locale) => locale.languageCode),
      containsAll(['cs', 'en']),
    );
  });

  test('English and Czech use the correct plural forms', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final cs = await AppLocalizations.delegate.load(const Locale('cs'));
    expect(en.diceOnTray(1), startsWith('1 die on the tray'));
    expect(en.diceOnTray(2), startsWith('2 dice on the tray'));
    expect(cs.diceOnTray(1), startsWith('1 kostka na ploše'));
    expect(cs.diceOnTray(2), startsWith('2 kostky na ploše'));
    expect(cs.diceOnTray(4), startsWith('4 kostky na ploše'));
    expect(cs.diceOnTray(5), startsWith('5 kostek na ploše'));
  });

  test('v1 data migrates without losing dice, rolls or custom text', () async {
    final source = {
      'version': 1,
      'setName': 'Žoldnéři',
      'modified': true,
      'dice': [
        {
          'definition': {'kind': 'numeric', 'sides': 20, 'name': 'd20'},
          'value': 7,
          'rollCount': 2,
        },
        {
          'definition': {
            'kind': 'mercenary',
            'sides': 6,
            'name': 'Žoldnéřská d6',
          },
          'value': 6,
          'rollCount': 4,
        },
        {
          'definition': {
            'kind': 'text',
            'sides': 4,
            'name': 'Vlastní d4',
            'labels': ['Ano', 'Ano', 'Ne', ''],
          },
          'value': 1,
          'rollCount': 1,
        },
        {
          'definition': {'kind': 'numeric', 'sides': 6, 'name': 'Moje šestka'},
          'value': 3,
          'rollCount': 8,
        },
      ],
      'savedSets': [
        {
          'name': 'Páteční hra',
          'dice': [
            {'kind': 'mercenary', 'sides': 6, 'name': 'Žoldnéřská d6'},
            {'kind': 'numeric', 'sides': 6, 'name': 'Moje šestka'},
          ],
        },
      ],
    };
    final store = MemoryStore(jsonEncode(source));
    final tray = TrayController(store: store);
    addTearDown(tray.dispose);
    await tray.load();
    expect(tray.storageWarning, isNull);
    expect(tray.preset, DicePreset.mercenaries);
    expect(tray.dice.map((die) => die.value), [7, 6, 1, 3]);
    expect(tray.dice.map((die) => die.rollCount), [2, 4, 1, 8]);
    expect(
      tray.dice.take(3).every((die) => die.definition.customName == null),
      isTrue,
    );
    expect(tray.dice.last.definition.customName, 'Moje šestka');
    expect(tray.dice[2].definition.labels, ['Ano', 'Ano', 'Ne', '']);
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(en.trayTitle(tray), 'Mercenaries');
    expect(en.dieName(tray.dice[1].definition), 'Mercenary d6');
    expect(en.dieName(tray.dice.last.definition), 'Moje šestka');
    expect(en.faceLabel(tray.dice[2].face!), 'Ano');
    tray.setLanguage('en');
    await tray.saved;
    expect((jsonDecode(store.value!) as Map)['version'], 2);
    final restored = TrayController(store: store);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.storageWarning, isNull);
    expect(restored.language, 'en');
    expect(restored.preset, DicePreset.mercenaries);
    expect(restored.modified, isTrue);
    expect(restored.dice.map((die) => die.value), [7, 6, 1, 3]);
    expect(restored.dice.map((die) => die.rollCount), [2, 4, 1, 8]);
    expect(restored.savedSets.single.name, 'Páteční hra');
    expect(restored.savedSets.single.dice.last.customName, 'Moje šestka');
  });

  test(
    'a user set named like a preset remains a distinct custom set',
    () async {
      final store = MemoryStore();
      final tray = TrayController(store: store);
      addTearDown(tray.dispose);
      await tray.load();
      expect(tray.saveSet('Žoldnéři'), isTrue);
      tray.setLanguage('en');
      await tray.saved;
      final restored = TrayController(store: store);
      addTearDown(restored.dispose);
      await restored.load();
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      expect(restored.preset, isNull);
      expect(en.trayTitle(restored), 'Žoldnéři');
      expect(en.setTitle(builtInSets.first), 'Mercenaries');
      expect(en.setTitle(restored.savedSets.single), 'Žoldnéři');
    },
  );

  testWidgets(
    'the language picker translates defaults while preserving user content',
    (tester) async {
      final tray = TrayController(store: MemoryStore(), roller: (_) async => 4);
      addTearDown(tray.dispose);
      await tray.load();
      tray.setLanguage('cs');
      tray.addDice(
        DieDefinition.text('Moje kostka', ['Ano', 'Ne', '', 'Řeka']),
        1,
      );
      tray.saveSet('Česká hra');
      await tray.rollAll();
      await tester.pumpWidget(EasyDiceApp(controller: tray));
      await tester.pumpAndSettle();
      expect(find.text('Hodit všemi'), findsOneWidget);
      final rolls = tray.dice.map((die) => die.rollCount).toList();
      await tester.tap(find.byKey(const ValueKey('language-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('Roll all'), findsOneWidget);
      expect(find.text('Mercenary d6'), findsNWidgets(3));
      expect(find.text('One sword · roll 1'), findsNWidgets(3));
      expect(find.text('Česká hra'), findsOneWidget);
      expect(find.text('Moje kostka'), findsOneWidget);
      expect(find.text('Řeka'), findsOneWidget);
      expect(tray.dice.map((die) => die.rollCount), rolls);
      expect(tray.language, 'en');
      await tester.tap(find.text('Add dice'));
      await tester.pumpAndSettle();
      expect(find.text('Number of sides'), findsOneWidget);
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is StaticTextField && widget.label == 'Number of sides',
        ),
        '1',
      );
      await tester.ensureVisible(find.text('Add'));
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a side count from 2 to 1,000,000.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('language-picker')));
      await tester.tap(find.byKey(const ValueKey('language-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Čeština'));
      await tester.pumpAndSettle();
      expect(find.text('Hodit všemi'), findsOneWidget);
      expect(find.text('Žoldnéřská d6'), findsNWidgets(3));
      expect(tray.dice.map((die) => die.rollCount), rolls);
      expect(tester.takeException(), isNull);
      await tray.saved;
    },
  );

  testWidgets(
    'device language is used, with English as the unsupported-locale fallback',
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('de')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final tray = TrayController(store: MemoryStore());
      addTearDown(tray.dispose);
      await tray.load();
      await tester.pumpWidget(EasyDiceApp(controller: tray));
      await tester.pumpAndSettle();
      expect(find.text('Roll all'), findsOneWidget);
      expect(find.text('Mercenaries'), findsOneWidget);
      tester.platformDispatcher.localesTestValue = const [Locale('cs')];
      await tester.pumpAndSettle();
      expect(find.text('Hodit všemi'), findsOneWidget);
      expect(tray.language, isNull);
    },
  );
}
