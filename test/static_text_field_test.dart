import 'package:easy_dice_thrower/app_theme.dart';
import 'package:easy_dice_thrower/widgets/static_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _openField(WidgetTester tester, Widget field) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Center(child: SizedBox(width: 300, child: field))),
    ),
  );
}

Finder get _field => find.byType(StaticTextField);

Finder get _border => find.descendant(
  of: _field,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).border != null,
  ),
);

double _borderWidth(WidgetTester tester) =>
    ((tester.widget<DecoratedBox>(_border).decoration as BoxDecoration).border!
            as Border)
        .top
        .width;

void main() {
  testWidgets(
    'the painted padding focuses the input without changing selection',
    (tester) async {
      final controller = TextEditingController(text: 'Alpha beta');
      addTearDown(controller.dispose);
      await _openField(
        tester,
        StaticTextField(controller: controller, label: 'Name'),
      );
      final input = tester.widget<TextField>(find.byType(TextField));
      final border = tester.getRect(_border);
      const selection = TextSelection(baseOffset: 1, extentOffset: 4);
      for (final position in [
        Offset(border.left + 2, border.center.dy),
        Offset(border.right - 2, border.center.dy),
        Offset(border.center.dx, border.top + 2),
        Offset(border.center.dx, border.bottom - 2),
      ]) {
        input.focusNode!.unfocus();
        await tester.idle();
        await tester.pump();
        controller.selection = selection;
        await tester.tapAt(position);
        await tester.idle();
        await tester.pump();
        expect(input.focusNode!.hasFocus, isTrue);
        expect(controller.selection, selection);
      }
      final editable = tester.getRect(find.byType(TextField));
      await tester.tapAt(Offset(editable.right - 2, editable.center.dy));
      await tester.pump();
      expect(controller.selection.isCollapsed, isTrue);
      expect(controller.selection.baseOffset, controller.text.length);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'focus border changes on the first frame without moving the label',
    (tester) async {
      await _openField(tester, const StaticTextField(label: 'Name'));
      final labelRect = tester.getRect(find.text('Name'));
      final inputRect = tester.getRect(_border);
      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.decoration, isNull);
      expect(find.byType(InputDecorator), findsNothing);
      expect(_borderWidth(tester), 1.5);
      input.focusNode!.requestFocus();
      await tester.idle();
      expect(input.focusNode!.hasFocus, isTrue);
      await tester.pump();
      expect(_borderWidth(tester), 2.5);
      expect(tester.getRect(find.text('Name')), labelRect);
      expect(tester.getRect(_border), inputRect);
      input.focusNode!.unfocus();
      await tester.idle();
      expect(input.focusNode!.hasFocus, isFalse);
      await tester.pump();
      expect(_borderWidth(tester), 1.5);
      expect(tester.getRect(find.text('Name')), labelRect);
      expect(tester.getRect(_border), inputRect);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'errors appear and clear on the first frame with field semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final form = GlobalKey<FormState>();
        await _openField(
          tester,
          Form(
            key: form,
            child: StaticTextField(
              label: 'Name',
              validator: (value) => value!.isEmpty ? 'Enter a name.' : null,
            ),
          ),
        );
        expect(form.currentState!.validate(), isFalse);
        await tester.pump();
        expect(find.text('Enter a name.'), findsOneWidget);
        expect(_borderWidth(tester), 2.5);
        expect(
          tester.getSemantics(find.byType(TextField)),
          isSemantics(
            label: 'Name',
            value: '',
            hint: 'Enter a name.',
            isTextField: true,
            validationResult: SemanticsValidationResult.invalid,
          ),
        );
        for (final type in [FadeTransition, SlideTransition, AnimatedOpacity]) {
          expect(
            find.ancestor(
              of: find.text('Enter a name.'),
              matching: find.byType(type),
            ),
            findsNothing,
          );
        }
        await tester.enterText(_field, 'Ada');
        await tester.pump();
        expect(find.text('Enter a name.'), findsNothing);
        expect(
          tester.getSemantics(find.byType(TextField)),
          isSemantics(
            label: 'Name',
            value: 'Ada',
            isTextField: true,
            validationResult: SemanticsValidationResult.valid,
          ),
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'programmatic controller updates validate the new value immediately',
    (tester) async {
      final controller = TextEditingController(text: '1');
      addTearDown(controller.dispose);
      final form = GlobalKey<FormState>();
      await _openField(
        tester,
        Form(
          key: form,
          child: StaticTextField(
            controller: controller,
            label: 'Sides',
            validator:
                (value) =>
                    (int.tryParse(value ?? '') ?? 0) < 2 ? 'Too few.' : null,
          ),
        ),
      );
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Too few.'), findsOneWidget);
      controller.text = '20';
      expect(form.currentState!.validate(), isTrue);
      await tester.pump();
      expect(find.text('Too few.'), findsNothing);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '20',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hints and helpers stay outside the editable value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _openField(
        tester,
        StaticTextField(
          controller: controller,
          label: 'Faces',
          hint: 'Yes\nNo',
          helper: 'One row per face.',
          minLines: 2,
          maxLines: 4,
          maxLength: 12,
        ),
      );
      expect(find.text('Yes\nNo'), findsOneWidget);
      expect(
        tester.getRect(find.text('Yes\nNo')).top,
        greaterThan(tester.getRect(_border).bottom),
      );
      expect(find.text('0/12'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(TextField)),
        isSemantics(
          label: 'Faces',
          value: '',
          hint: 'Yes\nNo',
          isTextField: true,
        ),
      );
      controller.text = '\n';
      await tester.pump();
      expect(find.text('Yes\nNo'), findsNothing);
      expect(find.text('One row per face.'), findsOneWidget);
      expect(find.text('1/12'), findsOneWidget);
      expect(
        tester.getRect(find.text('One row per face.')).top,
        greaterThan(tester.getRect(_border).bottom),
      );
      controller.text = '👩‍💻é';
      await tester.pump();
      expect(find.text('2/12'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(TextField)),
        isSemantics(label: 'Faces', value: '👩‍💻é', isTextField: true),
      );
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'replacing a controller and resetting preserve form synchronization',
    (tester) async {
      final first = TextEditingController(text: 'first');
      final second = TextEditingController(text: 'second');
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      var current = first;
      late StateSetter rebuild;
      final form = GlobalKey<FormState>();
      await _openField(
        tester,
        Form(
          key: form,
          child: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return StaticTextField(
                controller: current,
                label: 'Name',
                validator: (value) => value == 'second' ? null : 'Use second.',
              );
            },
          ),
        ),
      );
      rebuild(() => current = second);
      await tester.pump();
      expect(form.currentState!.validate(), isTrue);
      second.text = 'changed';
      expect(form.currentState!.validate(), isFalse);
      form.currentState!.reset();
      expect(second.text, 'second');
      expect(form.currentState!.validate(), isTrue);
      await tester.pump();
      expect(find.text('Use second.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
