import 'dart:collection';
import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:dice_thrower/dice_thrower.dart' show oneDiceThrower;
import 'package:flutter/foundation.dart';

import 'data/tray_store.dart';
import 'models/dice.dart';
import 'models/tray_orientation.dart';

enum TrayMessage {
  loadFailed,
  saveFailed,
  rollFailed,
  trayFull,
  invalidSetName,
}

typedef RollDie = Future<int> Function(int sides);

class TrayController extends ChangeNotifier {
  TrayController({
    required TrayStore store,
    RollDie? roller,
    DicePreset initialPreset = DicePreset.mercenaries,
  }) : _store = store,
       _roller = roller ?? oneDiceThrower {
    _replaceTray(builtInSets.firstWhere((set) => set.preset == initialPreset));
  }

  final TrayStore _store;
  final RollDie _roller;
  List<TrayDie> _dice = [];
  List<DiceSet> _savedSets = [];
  final Set<int> _rolling = {};
  int _nextId = 0;
  String? _setName;
  DicePreset? _preset;
  String? _language;
  TrayOrientation _orientation = TrayOrientation.portrait;
  bool _modified = false;
  bool _ready = false;
  bool _loadFailed = false;
  bool _disposed = false;
  TrayMessage? _storageWarning;
  TrayMessage? _operationError;
  Future<void>? _loadFuture;
  Future<void> _saveTail = Future.value();

  List<TrayDie> get dice => UnmodifiableListView(_dice);
  List<DiceSet> get savedSets => UnmodifiableListView(_savedSets);
  String? get setName => _setName;
  DicePreset? get preset => _preset;
  String? get language => _language;
  TrayOrientation get orientation => _orientation;
  bool get modified => _modified;
  bool get ready => _ready;
  bool get recoveryRequired => _loadFailed;
  bool get busy => _rolling.isNotEmpty;
  bool get canResetRollCounts =>
      _ready && !_disposed && !busy && _dice.any((die) => die.rollCount > 0);
  TrayMessage? get storageWarning => _storageWarning;
  TrayMessage? get operationError => _operationError;
  Future<void> get saved => _saveTail;
  bool isRolling(int id) => _rolling.contains(id);

  Future<void> load() => _loadFuture ??= _load();

  Future<void> retryLoad() {
    if (!_loadFailed || !_ready) return _loadFuture ?? Future.value();
    _ready = false;
    _emit();
    return _loadFuture = _load();
  }

  void replaceUnreadData() {
    if (!_loadFailed || !_ready) return;
    _loadFailed = false;
    _storageWarning = null;
    _save();
    _emit();
  }

  Future<void> _load() async {
    try {
      final value = await _store.read();
      if (value != null) {
        final json = jsonDecode(value) as Map<String, dynamic>;
        final version = json['version'];
        if (version != 1 && version != 2) throw const FormatException();
        final legacy = version == 1;
        final items = json['dice'] as List;
        if (items.length > 100) throw const FormatException();
        final dice = [
          for (final item in items)
            TrayDie.fromJson(
              _nextId++,
              item as Map<String, dynamic>,
              legacy: legacy,
            ),
        ];
        final sets =
            (json['savedSets'] as List)
                .map(
                  (item) => DiceSet.fromJson(
                    item as Map<String, dynamic>,
                    legacy: legacy,
                  ),
                )
                .toList();
        var name = json['setName'] as String?;
        final modified = json['modified'] as bool;
        if (name != null &&
            (name.trim().isEmpty || name.characters.length > 48)) {
          throw const FormatException();
        }
        DicePreset? preset;
        if (legacy) {
          if (!sets.any((set) => set.name == name)) {
            preset = legacyPresetNames[name];
            if (preset != null || name == 'Vlastní sestava') name = null;
          }
        } else {
          final id = json['preset'] as String?;
          preset = id == null ? null : DicePreset.values.byName(id);
          if (preset != null && name != null) throw const FormatException();
        }
        if (sets.map((set) => set.name).toSet().length != sets.length) {
          throw const FormatException();
        }
        final language = json['language'] as String?;
        final preferredOrientation = TrayOrientation.values.firstWhere(
          (orientation) => orientation.name == json['orientation'],
          orElse: () => TrayOrientation.portrait,
        );
        _dice = dice;
        _savedSets = sets;
        _setName = name;
        _preset = preset;
        _language = language;
        _orientation = preferredOrientation;
        _modified = modified;
      }
      _loadFailed = false;
      _storageWarning = null;
    } catch (_) {
      _loadFailed = true;
      _storageWarning = TrayMessage.loadFailed;
    }
    _ready = true;
    _emit();
  }

  void _replaceTray(DiceSet set) {
    _dice = [
      for (final definition in set.dice)
        TrayDie(id: _nextId++, definition: definition),
    ];
    _preset = set.preset;
    _setName = set.preset == null ? set.name : null;
    _modified = false;
    _rolling.clear();
    _operationError = null;
  }

  void loadSet(DiceSet set) {
    _replaceTray(set);
    _changed();
  }

  bool addDice(DieDefinition definition, int count) {
    if (count < 1 || _dice.length + count > 100) {
      return _reject(TrayMessage.trayFull);
    }
    _dice.addAll([
      for (var i = 0; i < count; i++)
        TrayDie(id: _nextId++, definition: definition),
    ]);
    _changed(composition: true);
    return true;
  }

  void removeDie(int id) {
    final index = _dice.indexWhere((die) => die.id == id);
    if (index < 0) return;
    _dice.removeAt(index);
    _rolling.remove(id);
    _changed(composition: true);
  }

  bool duplicateDie(int id) {
    final index = _dice.indexWhere((die) => die.id == id);
    if (index < 0) return false;
    if (_dice.length == 100) {
      return _reject(TrayMessage.trayFull);
    }
    _dice.insert(
      index + 1,
      TrayDie(id: _nextId++, definition: _dice[index].definition),
    );
    _changed(composition: true);
    return true;
  }

  void replaceDie(int id, DieDefinition definition) {
    final index = _dice.indexWhere((die) => die.id == id);
    if (index < 0) return;
    _rolling.remove(id);
    _dice[index] = TrayDie(id: _nextId++, definition: definition);
    _changed(composition: true);
  }

  bool saveSet(String value) {
    final name = value.trim();
    if (name.isEmpty || name.characters.length > 48) {
      return _reject(TrayMessage.invalidSetName);
    }
    final set = DiceSet(name, _dice.map((die) => die.definition).toList());
    final index = _savedSets.indexWhere((item) => item.name == name);
    if (index < 0) {
      _savedSets.add(set);
    } else {
      _savedSets[index] = set;
    }
    _setName = name;
    _preset = null;
    _modified = false;
    _changed();
    return true;
  }

  void deleteSet(String name) {
    _savedSets.removeWhere((set) => set.name == name);
    if (_setName == name) {
      _setName = null;
      _modified = true;
    }
    _changed();
  }

  Future<void> rollDie(int id) async {
    if (await _roll(id)) _save();
  }

  bool resetRollCounts() {
    if (!canResetRollCounts) return false;
    _dice = [
      for (final die in _dice)
        TrayDie(id: die.id, definition: die.definition, value: die.value),
    ];
    _changed();
    return true;
  }

  Future<void> rollAll() async {
    final ids = _dice.map((die) => die.id).toList();
    final changed = await Future.wait(ids.map(_roll));
    if (changed.any((value) => value)) _save();
  }

  Future<bool> _roll(int id) async {
    final index = _dice.indexWhere((die) => die.id == id);
    if (_disposed || index < 0 || _rolling.contains(id)) return false;
    final die = _dice[index];
    _rolling.add(id);
    _operationError = null;
    _emit();
    try {
      final result = await _roller(die.definition.sides);
      if (_disposed) return false;
      final current = _dice.indexWhere((item) => item.id == id);
      if (current < 0) return false;
      _dice[current] = die.rolled(result);
      return true;
    } catch (_) {
      if (_dice.any((die) => die.id == id)) {
        _operationError = TrayMessage.rollFailed;
      }
      return false;
    } finally {
      _rolling.remove(id);
      _emit();
    }
  }

  bool _reject(TrayMessage message) {
    _operationError = message;
    _emit();
    return false;
  }

  void setLanguage(String? language) {
    if (language != null &&
        !RegExp(r'^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$').hasMatch(language)) {
      throw ArgumentError.value(language, 'language');
    }
    if (_language == language) return;
    _language = language;
    _changed();
  }

  void setOrientation(TrayOrientation orientation) {
    if (_orientation == orientation) return;
    _orientation = orientation;
    _changed();
  }

  void dismissError() {
    _operationError = null;
    _emit();
  }

  void _changed({bool composition = false}) {
    if (composition) _modified = true;
    _operationError = null;
    _save();
    _emit();
  }

  void _save() {
    if (_disposed || !_ready || _loadFailed) return;
    final snapshot = jsonEncode({
      'version': 2,
      'dice': _dice.map((die) => die.toJson()).toList(),
      'savedSets': _savedSets.map((set) => set.toJson()).toList(),
      'setName': _setName,
      'preset': _preset?.name,
      'language': _language,
      'orientation': _orientation.name,
      'modified': _modified,
    });
    _saveTail = _saveTail.then((_) async {
      try {
        await _store.write(snapshot);
        if (_storageWarning == TrayMessage.saveFailed) {
          _storageWarning = null;
          _emit();
        }
      } catch (_) {
        _storageWarning = TrayMessage.saveFailed;
        _emit();
      }
    });
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
