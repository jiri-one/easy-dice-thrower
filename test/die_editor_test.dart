import 'package:easy_dice_thrower/app_theme.dart';
import 'package:easy_dice_thrower/l10n/generated/app_localizations.dart';
import 'package:easy_dice_thrower/models/dice.dart';
import 'package:easy_dice_thrower/widgets/die_editor.dart';
import 'package:easy_dice_thrower/widgets/static_text_field.dart';
import 'package:easy_dice_thrower/widgets/tray_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is StaticTextField && widget.label == label,
);

String _text(WidgetTester tester, String label) =>
    tester.widget<StaticTextField>(_field(label)).controller!.text;

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> _openEditor(
  WidgetTester tester, {
  DieDefinition? initial,
  int maxCount = 100,
  Locale locale = const Locale('en'),
  bool Function(DieEditResult)? onSubmit,
  ValueChanged<DieEditResult?>? onClosed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder:
            (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final result = await showTrayDialog<DieEditResult>(
                    context,
                    (_) => DieEditor(
                      initial: initial,
                      maxCount: maxCount,
                      onSubmit: onSubmit,
                    ),
                  );
                  onClosed?.call(result);
                },
                child: const Text('Open editor'),
              ),
            ),
      ),
    ),
  );
  await _tap(tester, 'Open editor');
}

void main() {
  for (final code in ['en', 'cs']) {
    testWidgets('mercenary previews expose their meanings in $code', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final locale = Locale(code);
        final labels = await AppLocalizations.delegate.load(locale);
        await _openEditor(
          tester,
          initial: DieDefinition.mercenary(),
          locale: locale,
        );
        for (final label in [
          labels.blankFace,
          labels.oneSword,
          labels.twoSwords,
        ]) {
          expect(
            tester.getSemantics(
              find.byWidgetPredicate(
                (widget) => widget is Image && widget.semanticLabel == label,
              ),
            ),
            isSemantics(label: label, isImage: true),
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('physical face and blank counts update before saving', (
    tester,
  ) async {
    final labels = await AppLocalizations.delegate.load(const Locale('en'));
    await _openEditor(tester, initial: DieDefinition.text('', ['Hit', 'Miss']));
    expect(find.text(labels.faceCountSummary(2, 0)), findsOneWidget);
    for (final (text, count, blanks) in [
      ('Hit\nMiss\n', 3, 1),
      ('\r\nHit\r\n\r\n—\r\n', 5, 4),
      ('\n\n', 3, 3),
    ]) {
      await tester.enterText(_field('Die faces'), text);
      await tester.pump();
      expect(find.text(labels.faceCountSummary(count, blanks)), findsOneWidget);
      expect(find.byType(DieEditor), findsOneWidget);
    }
    tester.widget<StaticTextField>(_field('Die faces')).controller!.text =
        'Hit\n';
    await tester.pump();
    expect(find.text(labels.faceCountSummary(2, 1)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('name and face limits count whole grapheme characters', (
    tester,
  ) async {
    DieEditResult? result;
    await _openEditor(
      tester,
      initial: DieDefinition.text('', ['Hit', 'Miss']),
      onClosed: (value) => result = value,
    );
    final face = '👩‍💻' * 80;
    final name = 'e\u0301' * 48;
    await tester.enterText(
      _field('Die faces'),
      '$face👩‍💻\n${'e\u0301' * 80}',
    );
    await tester.enterText(_field('Die name (optional)'), '${name}e\u0301');
    await _tap(tester, 'Save changes');
    expect(result, isNull);
    expect(
      find.text('A face label can have at most 80 characters.'),
      findsOneWidget,
    );
    expect(
      find.text('The name can have at most 48 characters.'),
      findsOneWidget,
    );
    await tester.enterText(_field('Die faces'), '$face\n${'e\u0301' * 80}');
    await tester.enterText(_field('Die name (optional)'), name);
    await _tap(tester, 'Save changes');
    expect(result?.definition.labels, [face, 'e\u0301' * 80]);
    expect(result?.definition.customName, name);
    expect(find.byType(DieEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (description, source, expected) in [
    ('leading', '\nHit\nMiss', ['', 'Hit', 'Miss']),
    ('trailing', 'Hit\nMiss\n', ['Hit', 'Miss', '']),
    ('middle', 'Hit\n\nMiss', ['Hit', '', 'Miss']),
    ('repeated', '\nHit\n\nHit\n', ['', 'Hit', '', 'Hit', '']),
    ('all blank', '\n\n', ['', '', '']),
    ('two blank', '\n', ['', '']),
    ('dash aliases', '—\nHit\n—', ['', 'Hit', '']),
    ('CRLF', '\r\nHit\r\n\r\nMiss\r\n', ['', 'Hit', '', 'Miss', '']),
    ('CR', '\rHit\r\rMiss\r', ['', 'Hit', '', 'Miss', '']),
  ]) {
    testWidgets('$description rows preserve every physical face', (
      tester,
    ) async {
      DieEditResult? result;
      await _openEditor(
        tester,
        initial: DieDefinition.text('Custom die', ['Hit', 'Miss']),
        onClosed: (value) => result = value,
      );
      await tester.enterText(_field('Die faces'), source);
      await _tap(tester, 'Save changes');
      expect(result?.definition.labels, expected);
      expect(result?.definition.sides, expected.length);
      expect(find.byType(DieEditor), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the physical row limit counts blank edge rows', (tester) async {
    DieEditResult? result;
    final hundredFaces = ['', ...List.filled(98, 'Hit'), ''];
    await _openEditor(
      tester,
      initial: DieDefinition.text('Custom die', ['Hit', 'Miss']),
      onClosed: (value) => result = value,
    );
    await tester.enterText(
      _field('Die faces'),
      ['', ...hundredFaces].join('\n'),
    );
    await _tap(tester, 'Save changes');
    expect(result, isNull);
    expect(find.byType(DieEditor), findsOneWidget);
    expect(
      find.text('Enter 2 to 100 faces, each on a separate line.'),
      findsOneWidget,
    );
    await tester.enterText(_field('Die faces'), hundredFaces.join('\n'));
    await _tap(tester, 'Save changes');
    expect(result?.definition.labels, hundredFaces);
    expect(result?.definition.sides, 100);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each face still respects the 80 character limit', (
    tester,
  ) async {
    DieEditResult? result;
    await _openEditor(
      tester,
      initial: DieDefinition.text('', ['Hit', 'Miss']),
      onClosed: (value) => result = value,
    );
    await tester.enterText(_field('Die faces'), '${'A' * 81}\n');
    await _tap(tester, 'Save changes');
    expect(result, isNull);
    expect(
      find.text('A face label can have at most 80 characters.'),
      findsOneWidget,
    );
    await tester.enterText(_field('Die faces'), '${'A' * 80}\n');
    await _tap(tester, 'Save changes');
    expect(result?.definition.labels, ['A' * 80, '']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remaining capacity validation retains the full draft', (
    tester,
  ) async {
    final attempts = <DieEditResult>[];
    DieEditResult? result;
    const faces = '\nHit\nHit\n—\nMiss\n';
    await _openEditor(
      tester,
      maxCount: 1,
      onSubmit: (value) {
        attempts.add(value);
        return true;
      },
      onClosed: (value) => result = value,
    );
    await _tap(tester, 'Text');
    await tester.enterText(_field('Die faces'), faces);
    await tester.enterText(_field('Die name (optional)'), 'Keep my draft');
    await tester.enterText(_field('Number of dice'), '2');
    await _tap(tester, 'Add');
    expect(attempts, isEmpty);
    expect(result, isNull);
    expect(find.byType(DieEditor), findsOneWidget);
    expect(find.text('There is room for only one more die.'), findsOneWidget);
    expect(_text(tester, 'Die faces'), faces);
    expect(_text(tester, 'Die name (optional)'), 'Keep my draft');
    expect(_text(tester, 'Number of dice'), '2');
    await tester.enterText(_field('Number of dice'), '1');
    await _tap(tester, 'Add');
    expect(attempts, hasLength(1));
    expect(result?.count, 1);
    expect(result?.definition.customName, 'Keep my draft');
    expect(result?.definition.labels, ['', 'Hit', 'Hit', '', 'Miss', '']);
    expect(find.byType(DieEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rejected submission retains the draft until accepted', (
    tester,
  ) async {
    final attempts = <DieEditResult>[];
    DieEditResult? result;
    const faces = '\nOne\nTwo\n';
    await _openEditor(
      tester,
      onSubmit: (value) {
        attempts.add(value);
        return value.count == 1;
      },
      onClosed: (value) => result = value,
    );
    await _tap(tester, 'Text');
    await tester.enterText(_field('Die faces'), faces);
    await tester.enterText(_field('Die name (optional)'), 'Retry me');
    await tester.enterText(_field('Number of dice'), '2');
    await _tap(tester, 'Add');
    expect(attempts.map((attempt) => attempt.count), [2]);
    expect(result, isNull);
    expect(find.text('The tray can hold at most 100 dice.'), findsOneWidget);
    expect(_text(tester, 'Die faces'), faces);
    expect(_text(tester, 'Die name (optional)'), 'Retry me');
    expect(_text(tester, 'Number of dice'), '2');
    await tester.enterText(_field('Number of dice'), '1');
    await _tap(tester, 'Add');
    expect(attempts.map((attempt) => attempt.count), [2, 1]);
    expect(result?.definition.customName, 'Retry me');
    expect(result?.definition.labels, ['', 'One', 'Two', '']);
    expect(find.byType(DieEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kind and side choices expose their current selection', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      DieEditResult? result;
      await _openEditor(tester, onClosed: (value) => result = value);

      void expectChoice(String label, bool selected) {
        expect(
          tester.getSemantics(find.widgetWithText(OutlinedButton, label)),
          isSemantics(
            label: label,
            hasSelectedState: true,
            isSelected: selected,
            isInMutuallyExclusiveGroup: true,
            isButton: true,
            hasTapAction: true,
          ),
        );
      }

      expectChoice('Numbers', true);
      expectChoice('Text', false);
      expectChoice('d6', true);
      expectChoice('d20', false);
      await tester.enterText(_field('Number of sides'), '7');
      await tester.pump();
      for (final sides in [4, 6, 8, 10, 12, 20, 100]) {
        expectChoice('d$sides', false);
      }
      await tester.enterText(_field('Number of sides'), '020');
      await tester.pump();
      expectChoice('d20', true);
      expectChoice('d6', false);
      await _tap(tester, 'Text');
      expectChoice('Numbers', false);
      expectChoice('Text', true);
      await _tap(tester, 'Numbers');
      expectChoice('Numbers', true);
      expectChoice('d20', true);
      await tester.enterText(_field('Number of sides'), '1');
      await _tap(tester, 'Add');
      expect(find.byType(DieEditor), findsOneWidget);
      await _tap(tester, 'd8');
      expect(_text(tester, 'Number of sides'), '8');
      expectChoice('d8', true);
      await _tap(tester, 'Add');
      expect(result?.definition.sides, 8);
      expect(find.byType(DieEditor), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
