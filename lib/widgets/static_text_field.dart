import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

class StaticTextField extends StatefulWidget {
  const StaticTextField({
    super.key,
    this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.validator,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.onFieldSubmitted,
  });

  final TextEditingController? controller;
  final String label;
  final String? hint;
  final String? helper;
  final FormFieldValidator<String>? validator;
  final int? minLines;
  final int? maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  State<StaticTextField> createState() => _StaticTextFieldState();
}

class _StaticTextFieldState extends State<StaticTextField> {
  final _focusNode = FocusNode();
  late TextEditingController _controller;
  late String _initialValue;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _initialValue = _controller.text;
    _focusNode.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(StaticTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      final previous = _controller;
      _controller =
          widget.controller ?? TextEditingController.fromValue(previous.value);
      _initialValue = _controller.text;
      if (oldWidget.controller == null) previous.dispose();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _focusChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final detailsStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: Colors.black);
    return _ControllerFormField(
      controller: _controller,
      initialValue: _initialValue,
      validator: widget.validator,
      builder: (field) {
        final text = field.value ?? '';
        final hint = text.isEmpty ? widget.hint : null;
        final maxLength = widget.maxLength;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(child: Text(widget.label)),
            const SizedBox(height: 8),
            Semantics(
              container: true,
              label: widget.label,
              hint: field.errorText ?? hint,
              validationResult:
                  field.hasError
                      ? SemanticsValidationResult.invalid
                      : SemanticsValidationResult.valid,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: _focusNode.requestFocus,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.black,
                      width: _focusNode.hasFocus || field.hasError ? 2.5 : 1.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      decoration: null,
                      style: const TextStyle(color: Colors.black),
                      cursorColor: Colors.black,
                      minLines: widget.minLines,
                      maxLines: widget.maxLines,
                      maxLength: maxLength,
                      keyboardType: widget.keyboardType,
                      inputFormatters: widget.inputFormatters,
                      onChanged: widget.onChanged,
                      onSubmitted: widget.onFieldSubmitted,
                    ),
                  ),
                ),
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              ExcludeSemantics(child: Text(hint, style: detailsStyle)),
            ],
            if (widget.helper != null) ...[
              const SizedBox(height: 6),
              Text(widget.helper!, style: detailsStyle),
            ],
            if (field.errorText != null) ...[
              const SizedBox(height: 6),
              Semantics(
                container: true,
                liveRegion: true,
                child: Text(
                  field.errorText!,
                  style: detailsStyle?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
            if (maxLength != null) ...[
              const SizedBox(height: 6),
              Text(
                maxLength > 0
                    ? '${text.characters.length}/$maxLength'
                    : '${text.characters.length}',
                textAlign: TextAlign.end,
                style: detailsStyle,
                semanticsLabel:
                    maxLength > 0
                        ? MaterialLocalizations.of(
                          context,
                        ).remainingTextFieldCharacterCount(
                          (maxLength - text.characters.length).clamp(
                            0,
                            maxLength,
                          ),
                        )
                        : null,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ControllerFormField extends FormField<String> {
  const _ControllerFormField({
    required this.controller,
    required super.initialValue,
    required super.builder,
    super.validator,
  });

  final TextEditingController controller;

  @override
  FormFieldState<String> createState() => _ControllerFormFieldState();
}

class _ControllerFormFieldState extends FormFieldState<String> {
  TextEditingController get _controller =>
      (widget as _ControllerFormField).controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_textChanged);
  }

  @override
  void didUpdateWidget(_ControllerFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_textChanged);
      _controller.addListener(_textChanged);
      setValue(_controller.text);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_textChanged);
    super.dispose();
  }

  @override
  void reset() {
    _controller.value = TextEditingValue(text: widget.initialValue ?? '');
    super.reset();
  }

  void _textChanged() {
    if (_controller.text == value) return;
    didChange(_controller.text);
    if (hasError) validate();
  }
}
