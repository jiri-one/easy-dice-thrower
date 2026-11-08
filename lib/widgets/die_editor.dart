import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../l10n/localized_labels.dart';
import '../models/dice.dart';
import 'static_text_field.dart';

class DieEditResult {
  const DieEditResult(this.definition, this.count);

  final DieDefinition definition;
  final int count;
}

class DieEditor extends StatefulWidget {
  const DieEditor({
    super.key,
    this.initial,
    this.maxCount = 100,
    this.onSubmit,
  });

  final DieDefinition? initial;
  final int maxCount;
  final bool Function(DieEditResult)? onSubmit;

  @override
  State<DieEditor> createState() => _DieEditorState();
}

class _DieEditorState extends State<DieEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _sides;
  late final TextEditingController _faces;
  final _count = TextEditingController(text: '1');
  late DieKind _kind;
  bool _submissionRejected = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _kind = initial?.kind ?? DieKind.numeric;
    _name = TextEditingController(text: initial?.customName ?? '');
    _sides = TextEditingController(text: '${initial?.sides ?? 6}');
    _faces = TextEditingController(
      text:
          initial?.kind == DieKind.text
              ? initial!.labels
                  .map((face) => face.isEmpty ? '—' : face)
                  .join('\n')
              : '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _sides.dispose();
    _faces.dispose();
    _count.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final definition = switch (_kind) {
      DieKind.numeric => DieDefinition.numeric(
        int.parse(_sides.text),
        name: _name.text,
      ),
      DieKind.mercenary => DieDefinition.mercenary(name: _name.text),
      DieKind.text => DieDefinition.text(_name.text, _parseFaces(_faces.text)),
    };
    final result = DieEditResult(
      definition,
      widget.initial == null ? int.parse(_count.text) : 1,
    );
    if (widget.onSubmit?.call(result) == false) {
      setState(() => _submissionRejected = true);
      return;
    }
    Navigator.of(context).pop(result);
  }

  List<String> _parseFaces(String text) =>
      text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n').map((
        line,
      ) {
        final label = line.trim();
        return label == '—' ? '' : label;
      }).toList();

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.initial == null
                ? context.l10n.addDice
                : context.l10n.editDieTitle,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              for (final (kind, label) in [
                (DieKind.numeric, context.l10n.numericKind),
                (DieKind.mercenary, context.l10n.mercenaryKind),
                (DieKind.text, context.l10n.textKind),
              ]) ...[
                if (kind != DieKind.numeric) const SizedBox(width: 8),
                Expanded(
                  child: MergeSemantics(
                    child: Semantics(
                      selected: _kind == kind,
                      inMutuallyExclusiveGroup: true,
                      child: OutlinedButton(
                        style: choiceButtonStyle(
                          selected: _kind == kind,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () => setState(() => _kind = kind),
                        child: Text(label),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          if (_kind == DieKind.numeric) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final sides in [4, 6, 8, 10, 12, 20, 100])
                  MergeSemantics(
                    child: Semantics(
                      selected: int.tryParse(_sides.text) == sides,
                      inMutuallyExclusiveGroup: true,
                      child: OutlinedButton(
                        style: choiceButtonStyle(
                          selected: int.tryParse(_sides.text) == sides,
                          minimumSize: const Size(48, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: () => setState(() => _sides.text = '$sides'),
                        child: Text('d$sides'),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            StaticTextField(
              key: const ValueKey('die-sides'),
              controller: _sides,
              label: context.l10n.sidesLabel,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              validator: (text) {
                final count = int.tryParse(text ?? '');
                return count == null || count < 2 || count > 1000000
                    ? context.l10n.invalidSides
                    : null;
              },
            ),
          ] else if (_kind == DieKind.mercenary) ...[
            Row(
              children: [
                for (final (file, label) in [
                  ('blank', context.l10n.blankFace),
                  ('one_sword', context.l10n.oneSword),
                  ('two_swords', context.l10n.twoSwords),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Image.asset(
                        'assets/mercenary/$file.jpg',
                        semanticLabel: label,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(context.l10n.mercenaryMappingHelp),
          ] else ...[
            StaticTextField(
              key: const ValueKey('die-faces'),
              controller: _faces,
              minLines: 4,
              maxLines: 8,
              label: context.l10n.facesLabel,
              hint: context.l10n.facesHint,
              helper: context.l10n.facesHelp,
              validator: (text) {
                final lines = _parseFaces(text ?? '');
                if (lines.length < 2 || lines.length > 100) {
                  return context.l10n.invalidFaceCount;
                }
                if (lines.any((line) => line.characters.length > 80)) {
                  return context.l10n.faceTextTooLong;
                }
                return null;
              },
            ),
            const SizedBox(height: 6),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _faces,
              builder: (context, value, _) {
                final faces = _parseFaces(value.text);
                return Semantics(
                  liveRegion: true,
                  child: Text(
                    context.l10n.faceCountSummary(
                      faces.length,
                      faces.where((face) => face.isEmpty).length,
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 20),
          StaticTextField(
            key: const ValueKey('die-name'),
            controller: _name,
            label: context.l10n.dieNameLabel,
            validator:
                (text) =>
                    (text?.trim().characters.length ?? 0) > 48
                        ? context.l10n.nameTooLong
                        : null,
          ),
          if (widget.initial == null) ...[
            const SizedBox(height: 20),
            StaticTextField(
              key: const ValueKey('die-count'),
              controller: _count,
              label: context.l10n.diceCountLabel,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onFieldSubmitted: (_) => _submit(),
              validator: (text) {
                final count = int.tryParse(text ?? '');
                if (count == null || count < 1 || count > 100) {
                  return context.l10n.invalidDiceCount;
                }
                return count > widget.maxCount
                    ? context.l10n.remainingDice(widget.maxCount)
                    : null;
              },
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(context.l10n.resetRollHelp),
          ],
          if (_submissionRejected) ...[
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(context.l10n.trayFull)),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.cancel),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(
                    widget.initial == null
                        ? context.l10n.add
                        : context.l10n.saveChanges,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
