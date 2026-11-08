import 'package:characters/characters.dart';

enum DieKind { numeric, mercenary, text }

enum FaceKind { numeric, text, blank, oneSword, twoSwords }

enum DicePreset { mercenaries, classic, rpg, empty }

const legacyPresetNames = {
  'Žoldnéři': DicePreset.mercenaries,
  'Klasické kostky': DicePreset.classic,
  'RPG': DicePreset.rpg,
  'Prázdná sestava': DicePreset.empty,
};

class DieFace {
  const DieFace(this.label, {required this.kind, this.asset});

  final String label;
  final FaceKind kind;
  final String? asset;
}

class DieDefinition {
  DieDefinition._(this.kind, this.sides, this.customName, this.labels);

  factory DieDefinition.numeric(int sides, {String? name}) {
    _checkSides(sides);
    return DieDefinition._(DieKind.numeric, sides, _name(name), const []);
  }

  factory DieDefinition.mercenary({String? name}) =>
      DieDefinition._(DieKind.mercenary, 6, _name(name), const []);

  factory DieDefinition.text(String name, List<String> faces) {
    if (faces.length < 2 || faces.length > 100) {
      throw const FormatException('A text die needs 2 to 100 faces.');
    }
    if (faces.any((face) => face.characters.length > 80)) {
      throw const FormatException('A face label cannot exceed 80 characters.');
    }
    return DieDefinition._(
      DieKind.text,
      faces.length,
      _name(name),
      List.unmodifiable(faces),
    );
  }

  final DieKind kind;
  final int sides;
  final String? customName;
  final List<String> labels;

  String get name =>
      customName ??
      switch (kind) {
        DieKind.numeric => 'd$sides',
        DieKind.mercenary => 'Mercenary d6',
        DieKind.text => 'Custom d$sides',
      };

  static String? _name(String? value) {
    final name = value?.trim() ?? '';
    if (name.characters.length > 48) {
      throw const FormatException('A name cannot exceed 48 characters.');
    }
    return name.isEmpty ? null : name;
  }

  static void _checkSides(int value) {
    if (value < 2 || value > 1000000) {
      throw const FormatException(
        'The side count must be between 2 and 1000000.',
      );
    }
  }

  DieFace faceFor(int value) {
    if (value < 1 || value > sides) {
      throw RangeError.range(value, 1, sides);
    }
    return switch (kind) {
      DieKind.numeric => DieFace('$value', kind: FaceKind.numeric),
      DieKind.text => DieFace(
        labels[value - 1],
        kind: labels[value - 1].isEmpty ? FaceKind.blank : FaceKind.text,
      ),
      DieKind.mercenary when value <= 3 => const DieFace(
        '',
        kind: FaceKind.blank,
        asset: 'assets/mercenary/blank.jpg',
      ),
      DieKind.mercenary when value <= 5 => const DieFace(
        '',
        kind: FaceKind.oneSword,
        asset: 'assets/mercenary/one_sword.jpg',
      ),
      DieKind.mercenary => const DieFace(
        '',
        kind: FaceKind.twoSwords,
        asset: 'assets/mercenary/two_swords.jpg',
      ),
    };
  }

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'sides': sides,
    'name': customName,
    if (kind == DieKind.text) 'labels': labels,
  };

  factory DieDefinition.fromJson(
    Map<String, dynamic> json, {
    bool legacy = false,
  }) {
    final kind = DieKind.values.byName(json['kind'] as String);
    var name = json['name'] as String?;
    final sides = json['sides'] as int;
    if (legacy &&
        name ==
            switch (kind) {
              DieKind.numeric => 'd$sides',
              DieKind.mercenary => 'Žoldnéřská d6',
              DieKind.text => 'Vlastní d$sides',
            }) {
      name = null;
    }
    final definition = switch (kind) {
      DieKind.numeric => DieDefinition.numeric(sides, name: name),
      DieKind.mercenary => DieDefinition.mercenary(name: name),
      DieKind.text => DieDefinition.text(
        name ?? '',
        (json['labels'] as List).cast<String>(),
      ),
    };
    if (definition.sides != sides) {
      throw const FormatException(
        'The saved side count does not match the definition.',
      );
    }
    return definition;
  }
}

class TrayDie {
  const TrayDie({
    required this.id,
    required this.definition,
    this.value,
    this.rollCount = 0,
  });

  final int id;
  final DieDefinition definition;
  final int? value;
  final int rollCount;

  DieFace? get face => value == null ? null : definition.faceFor(value!);

  TrayDie rolled(int result) {
    definition.faceFor(result);
    return TrayDie(
      id: id,
      definition: definition,
      value: result,
      rollCount: rollCount + 1,
    );
  }

  Map<String, Object?> toJson() => {
    'definition': definition.toJson(),
    'value': value,
    'rollCount': rollCount,
  };

  factory TrayDie.fromJson(
    int id,
    Map<String, dynamic> json, {
    bool legacy = false,
  }) {
    final definition = DieDefinition.fromJson(
      json['definition'] as Map<String, dynamic>,
      legacy: legacy,
    );
    final value = json['value'] as int?;
    final count = json['rollCount'] as int;
    if (count < 0 || (value == null && count != 0)) {
      throw const FormatException('Invalid saved roll state.');
    }
    if (value != null) definition.faceFor(value);
    return TrayDie(
      id: id,
      definition: definition,
      value: value,
      rollCount: count,
    );
  }
}

class DiceSet {
  DiceSet(String name, List<DieDefinition> dice, {this.preset})
    : name = name.trim(),
      dice = List.unmodifiable(dice) {
    if (this.name.isEmpty ||
        this.name.characters.length > 48 ||
        dice.length > 100) {
      throw const FormatException('Invalid dice set.');
    }
  }

  final String name;
  final List<DieDefinition> dice;
  final DicePreset? preset;

  Map<String, Object> toJson() => {
    'name': name,
    'dice': dice.map((definition) => definition.toJson()).toList(),
  };

  factory DiceSet.fromJson(Map<String, dynamic> json, {bool legacy = false}) =>
      DiceSet(
        json['name'] as String,
        (json['dice'] as List)
            .map(
              (item) => DieDefinition.fromJson(
                item as Map<String, dynamic>,
                legacy: legacy,
              ),
            )
            .toList(),
      );
}

final builtInSets = List<DiceSet>.unmodifiable([
  DiceSet('Mercenaries', [
    DieDefinition.numeric(20),
    ...List.generate(3, (_) => DieDefinition.mercenary()),
  ], preset: DicePreset.mercenaries),
  DiceSet(
    'Classic dice',
    List.generate(2, (_) => DieDefinition.numeric(6)),
    preset: DicePreset.classic,
  ),
  DiceSet('RPG', [
    for (final sides in [4, 6, 8, 10, 12, 20, 100])
      DieDefinition.numeric(sides),
  ], preset: DicePreset.rpg),
  DiceSet('Empty tray', [], preset: DicePreset.empty),
]);
