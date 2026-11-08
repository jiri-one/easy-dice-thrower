import 'package:easy_dice_thrower/main.dart';
import 'package:easy_dice_thrower/models/dice.dart';
import 'package:easy_dice_thrower/tray_controller.dart';
import 'package:easy_dice_thrower/widgets/die_tile.dart';
import 'package:easy_dice_thrower/widgets/static_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_store.dart';

Future<TrayController> openTray(WidgetTester tester, {int result = 4}) async {
  final tray = TrayController(
    store: MemoryStore(),
    roller: (_) async => result,
  );
  await tray.load();
  tray.setLanguage('cs');
  addTearDown(tray.dispose);
  await tester.pumpWidget(EasyDiceApp(controller: tray));
  await tester.pumpAndSettle();
  return tray;
}

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is StaticTextField && widget.label == label,
);

Future<void> activate(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('large system text remains usable on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openTray(tester);
    expect(tester.takeException(), isNull);
    await activate(tester, find.byKey(const ValueKey('tray-menu')));
    await activate(tester, find.text('Přidat kostky'));
    expect(tester.takeException(), isNull);
    await activate(tester, find.text('Zrušit'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a tap rolls only its die, including repeated identical results',
    (tester) async {
      final tray = await openTray(tester);
      expect(find.byType(DieTile), findsNWidgets(4));
      final face = find.byKey(ValueKey('die-face-${tray.dice.first.id}'));
      await activate(tester, face);
      expect(find.text('4'), findsOneWidget);
      expect(tray.dice.first.rollCount, 1);
      expect(tray.dice.skip(1).every((die) => die.value == null), isTrue);
      await activate(tester, face);
      expect(find.text('Hod 2'), findsOneWidget);
      expect(tray.dice.first.rollCount, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(tray.dice.first.rollCount, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'horizontal swipe rolls every die once; vertical drag never rolls',
    (tester) async {
      final tray = await openTray(tester);
      final face = find.byKey(ValueKey('die-face-${tray.dice.first.id}'));
      await tester.ensureVisible(face);
      await tester.drag(face, const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(tray.dice.map((die) => die.rollCount), [1, 1, 1, 1]);
      await tester.drag(face, const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(tray.dice.map((die) => die.rollCount), [1, 1, 1, 1]);
    },
  );

  testWidgets('adding multiple d20 dice through the editor is unrestricted', (
    tester,
  ) async {
    final tray = await openTray(tester);
    await activate(tester, find.text('Přidat kostky'));
    await activate(tester, find.text('d20').last);
    await tester.enterText(field('Počet kostek'), '2');
    await activate(tester, find.text('Přidat'));
    expect(tray.dice, hasLength(6));
    expect(tray.dice.where((die) => die.definition.sides == 20), hasLength(3));
    expect(find.text('Upravená sestava'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing can replace and remove the original d20', (
    tester,
  ) async {
    final tray = await openTray(tester);
    await activate(tester, find.text('Upravit'));
    await activate(tester, find.byIcon(Icons.edit_outlined).first);
    await activate(tester, find.text('Meče'));
    await activate(tester, find.text('Uložit změny'));
    expect(tray.dice.first.definition.kind, DieKind.mercenary);
    await activate(tester, find.byIcon(Icons.remove).first);
    expect(tray.dice, hasLength(3));
    await activate(tester, find.text('Hotovo'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom text dice retain repeated and blank physical faces', (
    tester,
  ) async {
    final tray = await openTray(tester);
    await activate(tester, find.text('Přidat kostky'));
    await activate(tester, find.text('Text'));
    await tester.enterText(field('Stěny kostky'), 'Ano\nAno\nNe\n—');
    await tester.enterText(field('Název kostky (volitelný)'), 'Odpověď');
    await activate(tester, find.text('Přidat'));
    expect(tray.dice.last.definition.labels, ['Ano', 'Ano', 'Ne', '']);
    expect(tray.dice.last.definition.name, 'Odpověď');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sets can be saved, changed, and loaded without preserving old rolls',
    (tester) async {
      final tray = await openTray(tester);
      await activate(tester, find.text('Uložit'));
      await tester.enterText(field('Název sady'), 'Večerní hra');
      await activate(tester, find.text('Uložit').last);
      expect(tray.savedSets.single.name, 'Večerní hra');
      tray.loadSet(builtInSets.last);
      await tester.pumpAndSettle();
      expect(find.text('Místo pro tvoje kostky'), findsOneWidget);
      await activate(tester, find.text('Sady'));
      await activate(tester, find.text('Večerní hra'));
      expect(tray.dice, hasLength(4));
      expect(tray.setName, 'Večerní hra');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('small screens keep the board and editor usable', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openTray(tester);
    expect(tester.takeException(), isNull);
    await activate(tester, find.byKey(const ValueKey('tray-menu')));
    await activate(tester, find.text('Přidat kostky'));
    await activate(tester, find.text('Meče'));
    expect(tester.takeException(), isNull);
    await activate(tester, find.text('Zrušit'));
    await activate(tester, find.byKey(const ValueKey('tray-menu')));
    await activate(tester, find.text('Upravit'));
    expect(tester.takeException(), isNull);
  });
}
