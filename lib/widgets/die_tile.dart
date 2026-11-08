import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/localized_labels.dart';
import '../models/dice.dart';
import 'tray_dialog.dart';

class DieTile extends StatefulWidget {
  const DieTile({
    super.key,
    required this.die,
    required this.position,
    required this.editing,
    required this.busy,
    required this.onRoll,
    required this.onEdit,
    required this.onRemove,
    required this.onDuplicate,
    this.compact = false,
  });

  final TrayDie die;
  final int position;
  final bool editing;
  final bool busy;
  final VoidCallback onRoll;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback onDuplicate;
  final bool compact;

  static const _nameStyle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
  );

  double heightForWidth(BuildContext context, double width) {
    double textHeight(String text, TextStyle style, double maxWidth) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: maxWidth);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    var height =
        math.max(
          28,
          textHeight(context.l10n.dieName(die.definition), _nameStyle, width),
        ) +
        4 +
        width;
    if (editing) return height + 6 + 48;
    height += 6 + math.max(36, MediaQuery.textScalerOf(context).scale(16) + 16);
    if (die.face != null && die.definition.kind == DieKind.text) {
      height +=
          4 +
          math.max(
            48,
            textHeight(
                  context.l10n.fullResult,
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  width - 32,
                ) +
                24,
          );
    }
    return height;
  }

  @override
  State<DieTile> createState() => _DieTileState();
}

class _DieTileState extends State<DieTile> {
  final _focus = FocusNode();
  bool _focused = false;
  bool _pressed = false;

  @override
  void didUpdateWidget(covariant DieTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editing || widget.busy) _pressed = false;
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _setPressed(bool pressed) {
    if (mounted && _pressed != pressed) setState(() => _pressed = pressed);
  }

  void _roll() {
    if (widget.editing || widget.busy) return;
    _focus.requestFocus();
    widget.onRoll();
  }

  @override
  Widget build(BuildContext context) {
    final die = widget.die;
    final face = die.face;
    final name = context.l10n.dieName(die.definition);
    final faceLabel = face == null ? null : context.l10n.faceLabel(face);
    final enabled = !widget.editing && !widget.busy;
    return Column(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 28),
          child: Center(
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: DieTile._nameStyle,
            ),
          ),
        ),
        const SizedBox(height: 4),
        FocusableActionDetector(
          focusNode: _focus,
          enabled: !widget.editing,
          mouseCursor:
              enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _roll();
                return null;
              },
            ),
          },
          child: Semantics(
            button: true,
            enabled: enabled,
            liveRegion: true,
            label: context.l10n.dieSemantics(
              widget.position,
              name,
              widget.busy
                  ? context.l10n.rolling
                  : face == null
                  ? context.l10n.notRolled
                  : context.l10n.rolledSemantics(faceLabel!, die.rollCount),
            ),
            onTap: enabled ? _roll : null,
            child: ExcludeSemantics(
              child: Listener(
                onPointerDown: (event) {
                  if (enabled && (event.buttons & kPrimaryButton) != 0) {
                    _setPressed(true);
                  }
                },
                onPointerUp: (_) => _setPressed(false),
                onPointerCancel: (_) => _setPressed(false),
                child: GestureDetector(
                  key: ValueKey('die-face-${die.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: enabled ? _roll : null,
                  onTapCancel: () => _setPressed(false),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _face(face),
                      if (!widget.editing) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _confirmation(faceLabel),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!widget.editing &&
            face != null &&
            die.definition.kind == DieKind.text) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => _showResult(face),
            child: Text(
              context.l10n.fullResult,
              semanticsLabel: context.l10n.showResultAction(widget.position),
            ),
          ),
        ],
        if (widget.editing) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _control(
                context.l10n.removeDieAction(widget.position),
                Icons.remove,
                widget.onRemove,
              ),
              _control(
                context.l10n.editDieAction(widget.position),
                Icons.edit_outlined,
                widget.onEdit,
              ),
              _control(
                context.l10n.duplicateDieAction(widget.position),
                Icons.add,
                widget.onDuplicate,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _showResult(DieFace face) => showTrayDialog<void>(
    context,
    (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.dieName(widget.die.definition),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        SelectableText(
          context.l10n.faceLabel(face),
          style: const TextStyle(fontSize: 24),
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    ),
  );

  Widget _face(DieFace? face) {
    final faceLabel = face == null ? null : context.l10n.faceLabel(face);
    return DecoratedBox(
      key: ValueKey('die-outline-${widget.die.id}'),
      decoration: BoxDecoration(
        border: Border.all(
          color:
              _focused || _pressed || widget.busy
                  ? Colors.black
                  : Colors.transparent,
          width: 3,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: AspectRatio(
          aspectRatio: 1,
          child:
              widget.die.definition.kind == DieKind.mercenary
                  ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        face?.asset ?? 'assets/mercenary/blank.jpg',
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                      if (face == null)
                        const Center(
                          child: Text('—', style: TextStyle(fontSize: 48)),
                        ),
                    ],
                  )
                  : DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child:
                            widget.die.definition.kind == DieKind.numeric
                                ? FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    faceLabel ?? '—',
                                    style: const TextStyle(
                                      fontSize: 96,
                                      fontWeight: FontWeight.w500,
                                      height: 1,
                                    ),
                                  ),
                                )
                                : Text(
                                  faceLabel ?? '—',
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                      ),
                    ),
                  ),
        ),
      ),
    );
  }

  Widget _confirmation(String? faceLabel) {
    final die = widget.die;
    final confirmed = faceLabel != null && !widget.busy;
    // Alternating contrast acknowledges identical rolls without motion.
    final inverted = confirmed && die.rollCount.isOdd;
    final foreground = inverted ? Colors.white : Colors.black;
    return LayoutBuilder(
      builder: (context, constraints) {
        final label =
            widget.busy
                ? context.l10n.rolling
                : faceLabel == null
                ? context.l10n.rollPrompt
                : !widget.compact &&
                    constraints.maxWidth >= 176 &&
                    die.definition.kind == DieKind.mercenary
                ? context.l10n.faceRollNumber(faceLabel, die.rollCount)
                : context.l10n.rollNumber(die.rollCount);
        return Container(
          key: ValueKey('roll-feedback-${die.id}'),
          constraints: BoxConstraints(
            minHeight: math.max(
              36,
              MediaQuery.textScalerOf(context).scale(16) + 16,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: inverted ? Colors.black : Colors.white,
            border: Border.all(
              color:
                  confirmed || widget.busy ? Colors.black : Colors.transparent,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (confirmed) ...[
                Icon(Icons.check, size: 18, color: foreground),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: confirmed ? FontWeight.w700 : FontWeight.w400,
                      height: 1,
                      color: foreground,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _control(String label, IconData icon, VoidCallback onPressed) {
    return IconButton(
      onPressed: onPressed,
      iconSize: 20,
      icon: Icon(icon, semanticLabel: label),
    );
  }
}
