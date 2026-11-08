import 'dart:async';
import 'dart:convert';

import 'package:easy_dice_thrower/models/dice.dart';
import 'package:easy_dice_thrower/models/tray_orientation.dart';
import 'package:easy_dice_thrower/tray_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_store.dart';

void main() {
  test(
    'emoji set names accepted by the counter survive storage and limits',
    () async {
      final store = MemoryStore();
      final tray = TrayController(store: store);
      addTearDown(tray.dispose);
      await tray.load();
      final name = '🎲' * 48;
      expect(tray.saveSet(name), isTrue);
      await tray.saved;
      final restored = TrayController(store: store);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.savedSets.single.name, name);
      expect(restored.storageWarning, isNull);
      expect(restored.saveSet('🎲' * 49), isFalse);
    },
  );
  test('the mercenary preset never locks or limits d20 dice', () async {
    final tray = TrayController(store: MemoryStore());
    addTearDown(tray.dispose);
    await tray.load();
    expect(tray.dice.map((die) => die.definition.sides), [20, 6, 6, 6]);
    final original = tray.dice.first.id;
    tray.duplicateDie(original);
    expect(tray.dice.where((die) => die.definition.sides == 20), hasLength(2));
    tray.replaceDie(original, DieDefinition.numeric(37));
    tray.removeDie(tray.dice[1].id);
    expect(tray.dice.map((die) => die.definition.sides), [37, 6, 6, 6]);
    expect(tray.modified, isTrue);
    await tray.saved;
  });

  test(
    'identical rolls are counted and restored with the current tray',
    () async {
      final store = MemoryStore();
      final tray = TrayController(store: store, roller: (_) async => 4);
      addTearDown(tray.dispose);
      await tray.load();
      final id = tray.dice[1].id;
      await tray.rollDie(id);
      await tray.rollDie(id);
      await tray.saved;
      final restored = TrayController(store: store);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.dice[1].face!.kind, FaceKind.oneSword);
      expect(restored.dice[1].rollCount, 2);
      expect(restored.dice.first.value, isNull);
      expect(restored.modified, isFalse);
    },
  );

  test(
    'rolling all uses each physical side count and leaves definitions intact',
    () async {
      final sides = <int>[];
      final tray = TrayController(
        store: MemoryStore(),
        roller: (count) async {
          sides.add(count);
          return count;
        },
      );
      addTearDown(tray.dispose);
      await tray.load();
      await tray.rollAll();
      expect(sides, [20, 6, 6, 6]);
      expect(tray.dice.map((die) => die.value), [20, 6, 6, 6]);
      expect(tray.dice.map((die) => die.rollCount), [1, 1, 1, 1]);
      expect(tray.modified, isFalse);
      await tray.saved;
    },
  );

  test(
    'reset counters preserves results, composition and saved state',
    () async {
      final store = MemoryStore();
      final tray = TrayController(store: store, roller: (sides) async => sides);
      addTearDown(tray.dispose);
      await tray.load();
      tray.addDice(DieDefinition.text('Odpověď', ['Ano', 'Ne', '']), 1);
      tray.setLanguage('cs');
      tray.setOrientation(TrayOrientation.landscape);
      tray.saveSet('Campaign');
      await tray.rollAll();
      await tray.rollDie(tray.dice.first.id);
      tray.addDice(DieDefinition.numeric(8), 1);
      final ids = tray.dice.map((die) => die.id).toList();
      final definitions =
          tray.dice.map((die) => die.definition.toJson()).toList();
      final values = tray.dice.map((die) => die.value).toList();
      expect(tray.canResetRollCounts, isTrue);
      expect(tray.resetRollCounts(), isTrue);
      expect(tray.dice.map((die) => die.id), ids);
      expect(tray.dice.map((die) => die.definition.toJson()), definitions);
      expect(tray.dice.map((die) => die.value), values);
      expect(tray.dice.every((die) => die.rollCount == 0), isTrue);
      expect(tray.canResetRollCounts, isFalse);
      await tray.saved;
      final writes = store.writes.length;
      expect(tray.resetRollCounts(), isFalse);
      await tray.saved;
      expect(store.writes, hasLength(writes));
      final restored = TrayController(
        store: store,
        roller: (sides) async => sides,
      );
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.storageWarning, isNull);
      expect(restored.dice.map((die) => die.value), values);
      expect(restored.dice.every((die) => die.rollCount == 0), isTrue);
      expect(restored.dice.map((die) => die.definition.toJson()), definitions);
      expect(restored.setName, 'Campaign');
      expect(restored.savedSets.single.dice, hasLength(5));
      expect(restored.modified, isTrue);
      expect(restored.language, 'cs');
      expect(restored.orientation, TrayOrientation.landscape);
      await restored.rollDie(restored.dice.first.id);
      expect(restored.dice.first.rollCount, 1);
      expect(restored.dice.skip(1).every((die) => die.rollCount == 0), isTrue);
      await restored.saved;
    },
  );

  test('reset counters never races an unfinished roll', () async {
    Completer<int>? pending;
    final tray = TrayController(
      store: MemoryStore(),
      roller: (_) => pending?.future ?? Future.value(4),
    );
    addTearDown(tray.dispose);
    await tray.load();
    await tray.rollAll();
    pending = Completer<int>();
    final roll = tray.rollDie(tray.dice.first.id);
    expect(tray.canResetRollCounts, isFalse);
    expect(tray.resetRollCounts(), isFalse);
    expect(tray.dice.map((die) => die.rollCount), [1, 1, 1, 1]);
    pending.complete(4);
    await roll;
    expect(tray.dice.map((die) => die.rollCount), [2, 1, 1, 1]);
    expect(tray.resetRollCounts(), isTrue);
    expect(tray.dice.map((die) => die.value), [4, 4, 4, 4]);
    expect(tray.dice.map((die) => die.rollCount), [0, 0, 0, 0]);
    await tray.saved;
  });

  test('removing a die discards an in-flight result', () async {
    final result = Completer<int>();
    final tray = TrayController(
      store: MemoryStore(),
      roller: (_) => result.future,
    );
    addTearDown(tray.dispose);
    await tray.load();
    final id = tray.dice.first.id;
    final pending = tray.rollDie(id);
    tray.removeDie(id);
    result.complete(20);
    await pending;
    expect(tray.dice, hasLength(3));
    expect(tray.dice.every((die) => die.value == null), isTrue);
    expect(tray.busy, isFalse);
    await tray.saved;
  });

  test('switching presets cannot receive an old roll', () async {
    final result = Completer<int>();
    final tray = TrayController(
      store: MemoryStore(),
      roller: (_) => result.future,
    );
    addTearDown(tray.dispose);
    await tray.load();
    final pending = tray.rollDie(tray.dice.first.id);
    tray.loadSet(builtInSets[1]);
    result.complete(20);
    await pending;
    expect(tray.preset, DicePreset.classic);
    expect(tray.dice.every((die) => die.value == null), isTrue);
    expect(tray.busy, isFalse);
    await tray.saved;
  });

  test('rapid repeated activation only requests one pending roll', () async {
    final result = Completer<int>();
    var requests = 0;
    final tray = TrayController(
      store: MemoryStore(),
      roller: (_) {
        requests++;
        return result.future;
      },
    );
    addTearDown(tray.dispose);
    await tray.load();
    final id = tray.dice.first.id;
    final first = tray.rollDie(id);
    await tray.rollDie(id);
    result.complete(8);
    await first;
    expect(requests, 1);
    expect(tray.dice.first.rollCount, 1);
    await tray.saved;
  });

  test(
    'saved sets capture composition independently from later edits and rolls',
    () async {
      final store = MemoryStore();
      final tray = TrayController(store: store, roller: (_) async => 3);
      addTearDown(tray.dispose);
      await tray.load();
      await tray.rollAll();
      expect(tray.saveSet('Moje hra'), isTrue);
      tray.removeDie(tray.dice.first.id);
      tray.loadSet(tray.savedSets.single);
      expect(tray.dice, hasLength(4));
      expect(
        tray.dice.every((die) => die.value == null && die.rollCount == 0),
        isTrue,
      );
      expect(tray.modified, isFalse);
      await tray.saved;
      final restored = TrayController(store: store);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.savedSets.single.name, 'Moje hra');
      restored.deleteSet('Moje hra');
      expect(restored.dice, hasLength(4));
      expect(restored.savedSets, isEmpty);
      expect(restored.saveSet('Žoldnéři'), isTrue);
      expect(restored.preset, isNull);
      await restored.saved;
    },
  );

  test(
    'invalid stored data falls back without silently overwriting the source',
    () async {
      final store = MemoryStore('{bad data');
      final tray = TrayController(store: store);
      addTearDown(tray.dispose);
      await tray.load();
      expect(tray.ready, isTrue);
      expect(tray.dice, hasLength(4));
      expect(tray.storageWarning, isNotNull);
      expect(store.writes, isEmpty);
    },
  );

  test('failed persistence is visible and a later write can recover', () async {
    final store = MemoryStore()..failWrites = true;
    final tray = TrayController(store: store);
    addTearDown(tray.dispose);
    await tray.load();
    tray.addDice(DieDefinition.numeric(8), 1);
    await tray.saved;
    expect(tray.storageWarning, isNotNull);
    expect(tray.dice, hasLength(5));
    store.failWrites = false;
    tray.addDice(DieDefinition.numeric(4), 1);
    await tray.saved;
    expect(tray.storageWarning, isNull);
    expect((jsonDecode(store.value!) as Map)['dice'], hasLength(6));
  });

  test(
    'failed reads preserve stored data across edits, settings and rolls',
    () async {
      final store = _UnreadableStore();
      final original = TrayController(store: store, roller: (_) async => 3);
      addTearDown(original.dispose);
      await original.load();
      original.saveSet('Stored campaign');
      await original.rollAll();
      await original.saved;
      final source = store.value;
      final writes = store.writes.length;
      store.failReads = true;
      final tray = TrayController(store: store, roller: (_) async => 1);
      addTearDown(tray.dispose);
      await tray.load();
      expect(tray.recoveryRequired, isTrue);
      tray.setLanguage('en');
      tray.setOrientation(TrayOrientation.landscape);
      tray.addDice(DieDefinition.numeric(8), 1);
      tray.saveSet('Temporary');
      await tray.rollAll();
      await tray.saved;
      expect(store.value, source);
      expect(store.writes, hasLength(writes));
      expect(tray.storageWarning, TrayMessage.loadFailed);
      store.failReads = false;
      await tray.retryLoad();
      expect(tray.recoveryRequired, isFalse);
      expect(tray.storageWarning, isNull);
      expect(tray.savedSets.single.name, 'Stored campaign');
      expect(tray.dice.map((die) => die.value), [3, 3, 3, 3]);
      expect(store.value, source);
    },
  );

  test('malformed storage changes only after explicit replacement', () async {
    final store = MemoryStore('{bad data');
    final tray = TrayController(store: store, roller: (_) async => 1);
    addTearDown(tray.dispose);
    await tray.load();
    tray.setLanguage('en');
    await tray.rollAll();
    await tray.saved;
    expect(store.value, '{bad data');
    expect(store.writes, isEmpty);
    await tray.retryLoad();
    expect(tray.recoveryRequired, isTrue);
    expect(store.writes, isEmpty);
    tray.replaceUnreadData();
    await tray.saved;
    expect(tray.recoveryRequired, isFalse);
    expect(tray.storageWarning, isNull);
    expect((jsonDecode(store.value!) as Map)['language'], 'en');
    expect(store.writes, hasLength(1));
  });

  test(
    'a storage queue preserves the newest state during slow writes',
    () async {
      final store = _DelayedStore();
      final tray = TrayController(store: store);
      addTearDown(tray.dispose);
      await tray.load();
      tray.addDice(DieDefinition.numeric(8), 1);
      tray.addDice(DieDefinition.numeric(12), 1);
      await Future<void>.delayed(Duration.zero);
      expect(store.started, 1);
      store.release.complete();
      await tray.saved;
      expect(store.started, 2);
      expect((jsonDecode(store.value!) as Map)['dice'], hasLength(6));
    },
  );

  test(
    'bad roller results are rejected without recording a successful roll',
    () async {
      final tray = TrayController(store: MemoryStore(), roller: (_) async => 0);
      addTearDown(tray.dispose);
      await tray.load();
      await tray.rollDie(tray.dice.first.id);
      expect(tray.dice.first.value, isNull);
      expect(tray.dice.first.rollCount, 0);
      expect(tray.operationError, isNotNull);
      expect(tray.busy, isFalse);
    },
  );

  test(
    'late results after disposal do not notify listeners or throw',
    () async {
      final result = Completer<int>();
      final tray = TrayController(
        store: MemoryStore(),
        roller: (_) => result.future,
      );
      await tray.load();
      final pending = tray.rollDie(tray.dice.first.id);
      tray.dispose();
      result.complete(4);
      await pending;
    },
  );
}

class _DelayedStore extends MemoryStore {
  final release = Completer<void>();
  int started = 0;

  @override
  Future<void> write(String value) async {
    started++;
    if (started == 1) await release.future;
    await super.write(value);
  }
}

class _UnreadableStore extends MemoryStore {
  bool failReads = false;

  @override
  Future<String?> read() async {
    if (failReads) throw StateError('Read failed');
    return super.read();
  }
}
