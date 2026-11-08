import 'package:easy_dice_thrower/models/dice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('names and text labels count user-visible characters consistently', () {
    final name = '🎲' * 48;
    final label = 'e\u0301' * 80;
    final die = DieDefinition.text(name, [label, '']);
    final restored = DieDefinition.fromJson(die.toJson());
    expect(restored.name, name);
    expect(restored.labels.first, label);
    expect(DiceSet(name, [die]).name, name);
    expect(
      () => DieDefinition.numeric(6, name: '🎲' * 49),
      throwsFormatException,
    );
    expect(
      () => DieDefinition.text('', ['e\u0301' * 81, '']),
      throwsFormatException,
    );
  });
  test('all six physical mercenary faces retain the 3/2/1 distribution', () {
    final die = DieDefinition.mercenary();
    expect(
      [for (var value = 1; value <= 6; value++) die.faceFor(value).kind],
      [
        FaceKind.blank,
        FaceKind.blank,
        FaceKind.blank,
        FaceKind.oneSword,
        FaceKind.oneSword,
        FaceKind.twoSwords,
      ],
    );
    expect(die.faceFor(1).asset, endsWith('/blank.jpg'));
    expect(die.faceFor(4).asset, endsWith('/one_sword.jpg'));
    expect(die.faceFor(6).asset, endsWith('/two_swords.jpg'));
  });

  test(
    'numeric dice accept custom side counts and reject impossible results',
    () {
      final die = DieDefinition.numeric(37);
      expect(die.faceFor(37).label, '37');
      expect(() => die.faceFor(0), throwsRangeError);
      expect(() => die.faceFor(38), throwsRangeError);
      expect(() => DieDefinition.numeric(1), throwsFormatException);
      expect(() => DieDefinition.numeric(1000001), throwsFormatException);
    },
  );

  test('custom text faces keep repeats and blanks through serialization', () {
    final labels = ['Ano', 'Ano', 'Ne', ''];
    final die = DieDefinition.text('Odpověď', labels);
    labels[0] = 'Změna';
    final restored = DieDefinition.fromJson(die.toJson());
    expect(restored.labels, ['Ano', 'Ano', 'Ne', '']);
    expect(restored.faceFor(4).kind, FaceKind.blank);
    expect(restored.name, 'Odpověď');
    expect(() => restored.labels.add('Nová'), throwsUnsupportedError);
  });

  test('malformed definitions and mismatched saved results are rejected', () {
    expect(
      () => DieDefinition.fromJson({
        'kind': 'mercenary',
        'sides': 20,
        'name': 'Chybná',
      }),
      throwsFormatException,
    );
    expect(() => DieDefinition.text('Jedna', ['A']), throwsFormatException);
    expect(
      () => TrayDie.fromJson(1, {
        'definition': DieDefinition.numeric(6).toJson(),
        'value': 7,
        'rollCount': 1,
      }),
      throwsRangeError,
    );
    expect(
      () => TrayDie.fromJson(1, {
        'definition': DieDefinition.numeric(6).toJson(),
        'value': null,
        'rollCount': 2,
      }),
      throwsFormatException,
    );
  });
}
