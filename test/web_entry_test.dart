import 'package:easy_dice_thrower/models/dice.dart';
import 'package:easy_dice_thrower/platform/web_entry.dart';
import 'package:easy_dice_thrower/tray_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_store.dart';

void main() {
  test('only the mercenary host selects mercenary dice on a fresh visit', () {
    for (final host in ['zoldneri.jiri.one', 'ZOLDNERI.JIRI.ONE:443']) {
      expect(
        webEntryPreset(Uri.parse('https://$host/')),
        DicePreset.mercenaries,
      );
    }
    for (final url in [
      'https://easy-dice-thrower.jiri.one/',
      'https://jiri-one.github.io/easy-dice-thrower/',
      'http://localhost:8767/',
      'https://zoldneri.jiri.one.example.com/',
      'https://example.com/?host=zoldneri.jiri.one',
    ]) {
      expect(webEntryPreset(Uri.parse(url)), DicePreset.classic);
    }
  });

  for (final host in ['easy-dice-thrower.jiri.one', 'zoldneri.jiri.one']) {
    test(
      '$host uses its initial preset and then restores user changes',
      () async {
        final store = MemoryStore();
        final preset = webEntryPreset(Uri.parse('https://$host/'));
        final tray = TrayController(
          store: store,
          initialPreset: preset,
          roller: (_) async => 1,
        );
        addTearDown(tray.dispose);
        await tray.load();
        expect(tray.preset, preset);
        expect(tray.dice, hasLength(preset == DicePreset.mercenaries ? 4 : 2));
        tray.loadSet(
          builtInSets.singleWhere((set) => set.preset == DicePreset.rpg),
        );
        await tray.rollAll();
        tray.setLanguage('en');
        await tray.saved;
        final restored = TrayController(store: store, initialPreset: preset);
        addTearDown(restored.dispose);
        await restored.load();
        expect(restored.preset, DicePreset.rpg);
        expect(restored.language, 'en');
        expect(restored.dice.map((die) => die.value), everyElement(1));
        expect(restored.dice.map((die) => die.rollCount), everyElement(1));
      },
    );
  }
}
