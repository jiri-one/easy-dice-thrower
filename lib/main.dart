import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'l10n/generated/app_localizations.dart';
import 'l10n/localized_labels.dart';
import 'platform/document_locale_stub.dart'
    if (dart.library.js_interop) 'platform/document_locale_web.dart';

import 'app_theme.dart';
import 'data/tray_store.dart';
import 'models/dice.dart';
import 'models/tray_orientation.dart';
import 'platform/orientation_lock.dart';
import 'platform/web_entry.dart';
import 'tray_controller.dart';
import 'widgets/die_editor.dart';
import 'widgets/dice_board.dart';
import 'widgets/die_tile.dart';
import 'widgets/static_text_field.dart';
import 'widgets/tray_dialog.dart';
import 'widgets/tray_option.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EasyDiceApp());
}

class EasyDiceApp extends StatefulWidget {
  const EasyDiceApp({super.key, this.controller, this.orientationLock});

  final TrayController? controller;
  final OrientationLock? orientationLock;

  @override
  State<EasyDiceApp> createState() => _EasyDiceAppState();
}

class _EasyDiceAppState extends State<EasyDiceApp> {
  final _theme = buildAppTheme();
  final _routeObserver = RouteObserver<ModalRoute<dynamic>>();
  late final TrayController _controller;
  late final OrientationLock _orientationLock;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        TrayController(
          store: PreferencesTrayStore(),
          initialPreset:
              kIsWeb ? webEntryPreset(Uri.base) : DicePreset.mercenaries,
        );
    _orientationLock = widget.orientationLock ?? OrientationLock();
    _controller.addListener(_syncOrientation);
    _syncOrientation();
    unawaited(_controller.load());
  }

  void _syncOrientation() {
    if (_controller.ready) _orientationLock.apply(_controller.orientation);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncOrientation);
    if (widget.orientationLock == null) _orientationLock.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        Locale? selected;
        for (final locale in AppLocalizations.supportedLocales) {
          if (locale.toLanguageTag() == _controller.language) selected = locale;
        }
        return MaterialApp(
          onGenerateTitle: (context) => context.l10n.appTitle,
          debugShowCheckedModeBanner: false,
          theme: _theme,
          themeAnimationDuration: Duration.zero,
          locale: selected,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          navigatorObservers: [_routeObserver],
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            overscroll: false,
          ),
          builder: (context, child) {
            setDocumentLanguage(
              Localizations.localeOf(context).toLanguageTag(),
            );
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: const SystemUiOverlayStyle(
                statusBarColor: Colors.white,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
                systemNavigationBarColor: Colors.white,
                systemNavigationBarIconBrightness: Brightness.dark,
                systemStatusBarContrastEnforced: false,
                systemNavigationBarContrastEnforced: false,
              ),
              child: child!,
            );
          },
          home: DiceTrayPage(
            controller: _controller,
            orientationLock: _orientationLock,
            routeObserver: _routeObserver,
          ),
        );
      },
    );
  }
}

class DiceTrayPage extends StatefulWidget {
  const DiceTrayPage({
    super.key,
    required this.controller,
    required this.orientationLock,
    required this.routeObserver,
  });

  final TrayController controller;
  final OrientationLock orientationLock;
  final RouteObserver<ModalRoute<dynamic>> routeObserver;

  @override
  State<DiceTrayPage> createState() => _DiceTrayPageState();
}

class _DiceTrayPageState extends State<DiceTrayPage> with RouteAware {
  static const _compactTitleStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
  );

  bool _editing = false;
  bool _precached = false;
  double _dragDistance = 0;
  Offset _dragOrigin = Offset.zero;
  double _verticalTravel = 0;
  bool _dragCancelled = false;
  ModalRoute<dynamic>? _route;
  late final Listenable _changes;

  @override
  void initState() {
    super.initState();
    _changes = Listenable.merge([widget.controller, widget.orientationLock]);
  }

  TrayController get _tray => widget.controller;
  OrientationLock get _orientationLock => widget.orientationLock;

  bool get _canRollAll => !_editing && !_tray.busy && _tray.dice.isNotEmpty;
  bool get _canResetRollCounts => !_editing && _tray.canResetRollCounts;

  void _rollAll() {
    if (_canRollAll && (_route?.isCurrent ?? false)) {
      unawaited(_tray.rollAll());
    }
  }

  void _resetRollCounts() {
    if (_canResetRollCounts && (_route?.isCurrent ?? false)) {
      _tray.resetRollCounts();
    }
  }

  @override
  void didPushNext() => _dragCancelled = true;

  @override
  void dispose() {
    widget.routeObserver.unsubscribe(this);
    super.dispose();
  }

  Widget _rollSurface(Widget child) => SizedBox.expand(
    child: Listener(
      onPointerCancel: (_) => _dragCancelled = true,
      child: GestureDetector(
        key: const ValueKey('roll-surface'),
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragDown:
            _canRollAll
                ? (details) {
                  _dragDistance = 0;
                  _verticalTravel = 0;
                  _dragOrigin = details.localPosition;
                  _dragCancelled = !(_route?.isCurrent ?? false);
                }
                : null,
        onHorizontalDragUpdate:
            _canRollAll
                ? (details) {
                  _dragDistance += details.primaryDelta ?? 0;
                  _verticalTravel = math.max(
                    _verticalTravel,
                    (details.localPosition.dy - _dragOrigin.dy).abs(),
                  );
                }
                : null,
        onHorizontalDragEnd:
            _canRollAll
                ? (details) {
                  if (!_dragCancelled &&
                      _dragDistance.abs() > _verticalTravel &&
                      (_dragDistance.abs() >= 32 ||
                          (details.primaryVelocity?.abs() ?? 0) >= 250)) {
                    _rollAll();
                  }
                  _dragDistance = 0;
                }
                : null,
        onHorizontalDragCancel: _canRollAll ? () => _dragDistance = 0 : null,
        child: child,
      ),
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route != route) {
      widget.routeObserver.unsubscribe(this);
      _route = route;
      if (route != null) widget.routeObserver.subscribe(this, route);
    }
    if (!_precached) {
      _precached = true;
      for (final asset in ['blank', 'one_sword', 'two_swords']) {
        unawaited(
          precacheImage(AssetImage('assets/mercenary/$asset.jpg'), context),
        );
      }
    }
  }

  Future<void> _chooseLanguage() async {
    final choices = <AppLocalizations>[];
    for (final locale in AppLocalizations.supportedLocales) {
      choices.add(await AppLocalizations.delegate.load(locale));
    }
    if (!mounted) return;
    await showTrayDialog<void>(
      context,
      (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.languageTitle,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          TrayOption(
            title: context.l10n.deviceLanguage,
            selected: _tray.language == null,
            trailing: _tray.language == null ? const Icon(Icons.check) : null,
            onPressed: () {
              _tray.setLanguage(null);
              Navigator.pop(context);
            },
          ),
          for (var i = 0; i < choices.length; i++)
            TrayOption(
              title: choices[i].languageName,
              selected:
                  _tray.language ==
                  AppLocalizations.supportedLocales[i].toLanguageTag(),
              trailing:
                  _tray.language ==
                          AppLocalizations.supportedLocales[i].toLanguageTag()
                      ? const Icon(Icons.check)
                      : null,
              onPressed: () {
                _tray.setLanguage(
                  AppLocalizations.supportedLocales[i].toLanguageTag(),
                );
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }

  Future<void> _showRollHelp() => showTrayDialog<void>(
    context,
    (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.rollHelpTitle,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Text(context.l10n.rollHint),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    ),
  );

  Future<void> _showTrayMenu() async {
    final action = await showTrayDialog<VoidCallback>(
      context,
      (context) => ListenableBuilder(
        listenable: _changes,
        builder: (context, _) {
          Widget option(
            String label,
            IconData icon,
            VoidCallback? action, {
            Key? key,
          }) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton.icon(
              key: key,
              onPressed:
                  action == null ? null : () => Navigator.pop(context, action),
              icon: Icon(icon, size: 20),
              label: Text(label),
            ),
          );

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.trayMenuTitle,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              option(
                context.l10n.rollAll,
                Icons.casino_outlined,
                _canRollAll ? _rollAll : null,
              ),
              option(
                context.l10n.resetRollCounts,
                Icons.restart_alt,
                _canResetRollCounts ? _resetRollCounts : null,
                key: const ValueKey('reset-roll-counts'),
              ),
              option(context.l10n.addDice, Icons.add, _addDice),
              option(context.l10n.sets, Icons.folder_open_outlined, _pickSet),
              option(
                _editing ? context.l10n.done : context.l10n.edit,
                _editing ? Icons.check : Icons.tune,
                () => setState(() => _editing = !_editing),
              ),
              option(context.l10n.save, Icons.bookmark_border, _saveSet),
              option(
                context.l10n.languageTitle,
                Icons.language,
                _chooseLanguage,
                key: const ValueKey('language-picker'),
              ),
              if (_orientationLock.supported)
                option(
                  context.l10n.orientationTitle,
                  Icons.screen_rotation,
                  _chooseOrientation,
                  key: const ValueKey('orientation-picker'),
                ),
              option(
                context.l10n.rollHelpTitle,
                Icons.help_outline,
                _showRollHelp,
              ),
              const SizedBox(height: 8),
              Text(
                _tray.dice.isEmpty
                    ? context.l10n.emptyFooter
                    : context.l10n.diceOnTray(_tray.dice.length),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.close),
              ),
            ],
          );
        },
      ),
    );
    if (mounted) action?.call();
  }

  Future<void> _chooseOrientation() async {
    if (!_orientationLock.supported) return;
    await showTrayDialog<void>(
      context,
      (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.orientationTitle,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(context.l10n.orientationHelp),
          const SizedBox(height: 16),
          for (final orientation in TrayOrientation.values)
            TrayOption(
              key: ValueKey('orientation-${orientation.name}'),
              selected: _tray.orientation == orientation,
              leading: Icon(
                orientation == TrayOrientation.portrait
                    ? Icons.stay_current_portrait
                    : Icons.stay_current_landscape,
              ),
              title:
                  orientation == TrayOrientation.portrait
                      ? context.l10n.portraitOrientation
                      : context.l10n.landscapeOrientation,
              trailing:
                  _tray.orientation == orientation
                      ? const Icon(Icons.check)
                      : null,
              onPressed: () {
                final retry =
                    _tray.orientation == orientation && _orientationLock.failed;
                _tray.setOrientation(orientation);
                if (retry) _orientationLock.apply(orientation, retry: true);
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }

  Future<void> _addDice() async {
    await showTrayDialog<DieEditResult>(
      context,
      (_) => DieEditor(
        maxCount: 100 - _tray.dice.length,
        onSubmit: (result) => _tray.addDice(result.definition, result.count),
      ),
    );
  }

  Future<void> _editDie(TrayDie die) async {
    final result = await showTrayDialog<DieEditResult>(
      context,
      (_) => DieEditor(initial: die.definition),
    );
    if (!mounted || result == null) return;
    _tray.replaceDie(die.id, result.definition);
  }

  Future<void> _saveSet() async {
    final form = GlobalKey<FormState>();
    final name = TextEditingController(
      text:
          _tray.savedSets.any((set) => set.name == _tray.setName)
              ? _tray.setName
              : '',
    );
    await showTrayDialog<void>(
      context,
      (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          final overwrite = _tray.savedSets.any(
            (set) => set.name == name.text.trim(),
          );
          void save() {
            if (!form.currentState!.validate()) return;
            if (_tray.saveSet(name.text)) Navigator.pop(dialogContext);
          }

          return Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.saveSetTitle,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(context.l10n.saveSetHelp),
                const SizedBox(height: 24),
                StaticTextField(
                  controller: name,
                  label: context.l10n.setNameLabel,
                  hint: context.l10n.setNameHint,
                  maxLength: 48,
                  onChanged: (_) => update(() {}),
                  onFieldSubmitted: (_) => save(),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return context.l10n.requiredSetName;
                    if (text.characters.length > 48) {
                      return context.l10n.nameTooLong;
                    }
                    return null;
                  },
                ),
                if (overwrite) ...[
                  const SizedBox(height: 8),
                  Text(context.l10n.overwriteSetWarning),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(context.l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FilledButton(
                        onPressed: save,
                        child: Text(
                          overwrite
                              ? context.l10n.overwriteSet
                              : context.l10n.save,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    name.dispose();
  }

  Future<void> _pickSet() async {
    final result = await showTrayDialog<String>(
      context,
      (dialogContext) => ListenableBuilder(
        listenable: _tray,
        builder:
            (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.setsTitle,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(context.l10n.chooseSetHelp),
                const SizedBox(height: 20),
                Text(
                  context.l10n.presetsSection,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                for (final set in builtInSets) _setRow(set, dialogContext),
                if (_tray.savedSets.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    context.l10n.yourSetsSection,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  for (final set in _tray.savedSets)
                    _setRow(set, dialogContext, saved: true),
                ],
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, 'save'),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(context.l10n.saveCurrentTray),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(context.l10n.close),
                ),
              ],
            ),
      ),
    );
    if (!mounted) return;
    if (result == 'save') await _saveSet();
  }

  Widget _setRow(
    DiceSet set,
    BuildContext dialogContext, {
    bool saved = false,
  }) {
    final summary =
        set.dice.isEmpty
            ? context.l10n.startEmpty
            : set.dice.map((die) => context.l10n.dieName(die)).join(', ');
    return Row(
      children: [
        Expanded(
          child: TrayOption(
            title: context.l10n.setTitle(set),
            subtitle: summary,
            trailing: const Icon(Icons.arrow_forward, size: 20),
            onPressed: () => _loadSet(set, dialogContext),
          ),
        ),
        if (saved)
          IconButton(
            onPressed: () => _deleteSet(set),
            icon: Icon(
              Icons.delete_outline,
              semanticLabel: context.l10n.deleteSetAction(set.name),
            ),
          ),
      ],
    );
  }

  Future<void> _loadSet(DiceSet set, BuildContext dialogContext) async {
    if (_tray.modified || _tray.dice.any((die) => die.value != null)) {
      final confirmed = await showTrayDialog<bool>(
        dialogContext,
        (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.switchSetTitle,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Text(context.l10n.switchSetHelp),
            const SizedBox(height: 24),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(context.l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(context.l10n.switchSet),
                ),
              ],
            ),
          ],
        ),
      );
      if (!mounted || !dialogContext.mounted || confirmed != true) return;
    }
    _tray.loadSet(set);
    setState(() => _editing = false);
    Navigator.pop(dialogContext);
  }

  Future<void> _deleteSet(DiceSet set) async {
    final confirmed = await showTrayDialog<bool>(
      context,
      (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.deleteSetQuestion(set.name),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Text(context.l10n.deleteSetHelp),
          const SizedBox(height: 24),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            overflowSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.delete),
              ),
            ],
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) _tray.deleteSet(set.name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _changes,
          builder: (context, _) {
            final compact = MediaQuery.sizeOf(context).width < 600;
            if (!_tray.ready) {
              return Center(child: Text(context.l10n.loadingTray));
            }
            final size = MediaQuery.sizeOf(context);
            if (size.width <= size.height) {
              return _rollSurface(_fittedTray(portrait: true));
            }
            if (size.width > size.height && size.height < 600) {
              return _rollSurface(_fittedTray(portrait: false));
            }
            return _rollSurface(
              SingleChildScrollView(
                padding: EdgeInsets.all(compact ? 16 : 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.casino_outlined, size: 30),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                context.l10n.appTitle,
                                style: TextStyle(
                                  fontSize: compact ? 20 : 24,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _languageButton(),
                            if (_orientationLock.supported) ...[
                              const SizedBox(width: 8),
                              _orientationButton(),
                            ],
                          ],
                        ),
                        if (!compact) ...[
                          const SizedBox(height: 8),
                          Text(
                            context.l10n.appTagline,
                            style: TextStyle(fontSize: 16),
                          ),
                        ],
                        SizedBox(height: compact ? 16 : 28),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              context.l10n.trayTitle(_tray),
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_tray.modified)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  context.l10n.modifiedTray,
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _toolbar(),
                        SizedBox(height: compact ? 12 : 20),
                        Text(
                          _editing
                              ? context.l10n.editHint
                              : context.l10n.rollHint,
                          style: const TextStyle(fontSize: 14),
                        ),
                        SizedBox(height: compact ? 12 : 20),
                        const Divider(height: 1, thickness: 1),
                        ..._notices(),
                        const SizedBox(height: 20),
                        if (_tray.dice.isEmpty) _emptyTray() else _diceBoard(),
                        const SizedBox(height: 28),
                        const Divider(height: 1, thickness: 1),
                        const SizedBox(height: 16),
                        Text(
                          _tray.dice.isEmpty
                              ? context.l10n.emptyFooter
                              : context.l10n.diceOnTray(_tray.dice.length),
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _notices() => [
    if (_tray.recoveryRequired)
      _recoveryNotice()
    else if (_tray.storageWarning != null)
      _notice(context.l10n.trayMessage(_tray.storageWarning!)),
    if (_tray.operationError != null)
      _notice(
        context.l10n.trayMessage(_tray.operationError!),
        dismiss: _tray.dismissError,
      ),
    if (_orientationLock.failed) _notice(context.l10n.orientationLockFailed),
  ];

  Widget _recoveryNotice() => Container(
    margin: const EdgeInsets.only(top: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(border: Border.all(width: 2)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(liveRegion: true, child: Text(context.l10n.loadFailed)),
        const SizedBox(height: 12),
        OverflowBar(
          spacing: 8,
          overflowSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => unawaited(_tray.retryLoad()),
              child: Text(context.l10n.retryLoad),
            ),
            OutlinedButton(
              onPressed: _replaceUnreadData,
              child: Text(context.l10n.replaceSavedData),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _replaceUnreadData() async {
    final confirmed = await showTrayDialog<bool>(
      context,
      (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.replaceSavedDataTitle,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Text(context.l10n.replaceSavedDataHelp),
          const SizedBox(height: 24),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            overflowSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.replaceSavedData),
              ),
            ],
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) _tray.replaceUnreadData();
  }

  Widget _languageButton({bool compact = false}) {
    final label = context.l10n.languageTitle;
    if (compact) {
      return _compactAction(
        label,
        Icons.language,
        _chooseLanguage,
        key: const ValueKey('language-picker'),
      );
    }
    return OutlinedButton.icon(
      key: const ValueKey('language-picker'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      onPressed: _chooseLanguage,
      icon: Icon(Icons.language, size: 20, semanticLabel: label),
      label: Text(Localizations.localeOf(context).languageCode.toUpperCase()),
    );
  }

  Widget _orientationButton() => _compactAction(
    context.l10n.orientationTitle,
    _tray.orientation == TrayOrientation.portrait
        ? Icons.stay_current_portrait
        : Icons.stay_current_landscape,
    _chooseOrientation,
    key: const ValueKey('orientation-picker'),
  );

  Widget _compactAction(
    String label,
    IconData icon,
    VoidCallback? action, {
    Key? key,
    bool selected = false,
  }) {
    return IconButton(
      key: key,
      onPressed: action,
      style: choiceButtonStyle(selected: selected),
      icon: Icon(icon, semanticLabel: label),
    );
  }

  Widget _landscapeToolbar() {
    final title = Text(
      context.l10n.trayTitle(_tray),
      style: _compactTitleStyle,
    );
    final actions = [
      _compactAction(
        context.l10n.rollAll,
        Icons.casino_outlined,
        _canRollAll ? _rollAll : null,
        key: const ValueKey('landscape-roll-all'),
        selected: true,
      ),
      _compactAction(
        context.l10n.resetRollCounts,
        Icons.restart_alt,
        _canResetRollCounts ? _resetRollCounts : null,
        key: const ValueKey('reset-roll-counts'),
      ),
      _compactAction(
        context.l10n.addDice,
        Icons.add,
        _addDice,
        key: const ValueKey('landscape-add'),
      ),
      _compactAction(context.l10n.sets, Icons.folder_open_outlined, _pickSet),
      _compactAction(
        _editing ? context.l10n.done : context.l10n.edit,
        _editing ? Icons.check : Icons.tune,
        () => setState(() => _editing = !_editing),
        selected: _editing,
      ),
      _compactAction(context.l10n.save, Icons.bookmark_border, _saveSet),
      _languageButton(compact: true),
      if (_orientationLock.supported) _orientationButton(),
      _compactAction(
        context.l10n.rollHelpTitle,
        Icons.help_outline,
        _showRollHelp,
        key: const ValueKey('landscape-help'),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final titleWidth = constraints.maxWidth - actions.length * 48;
        if (titleWidth < 80 || _titleMetrics(context, titleWidth).lines > 2) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              Wrap(alignment: WrapAlignment.end, children: actions),
            ],
          );
        }
        return Row(children: [Expanded(child: title), ...actions]);
      },
    );
  }

  ({double height, int lines}) _titleMetrics(
    BuildContext context,
    double width,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: context.l10n.trayTitle(_tray),
        style: DefaultTextStyle.of(context).style.merge(_compactTitleStyle),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: math.max(1, width));
    final metrics = (
      height: painter.height,
      lines: painter.computeLineMetrics().length,
    );
    painter.dispose();
    return metrics;
  }

  Widget _portraitToolbar({required bool showTitle}) => Row(
    children: [
      if (showTitle)
        Expanded(
          child: Text(context.l10n.trayTitle(_tray), style: _compactTitleStyle),
        )
      else
        const Spacer(),
      if (_tray.modified)
        Icon(
          Icons.edit_outlined,
          size: 18,
          semanticLabel: context.l10n.modifiedTray,
        ),
      if (_editing)
        _compactAction(
          context.l10n.done,
          Icons.check,
          () => setState(() => _editing = false),
          key: const ValueKey('portrait-done'),
        ),
      _compactAction(
        context.l10n.trayMenuTitle,
        Icons.menu,
        _showTrayMenu,
        key: const ValueKey('tray-menu'),
      ),
    ],
  );

  Widget _fittedTray({required bool portrait}) => LayoutBuilder(
    builder: (context, constraints) {
      final titleWidth =
          constraints.maxWidth -
          24 -
          48 -
          (_editing ? 48 : 0) -
          (_tray.modified ? 18 : 0);
      final separateTitle =
          portrait &&
          _titleMetrics(context, titleWidth).height >
              math.max(48, math.min(96, constraints.maxHeight / 4));
      final toolbar = ColoredBox(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (portrait)
                _portraitToolbar(showTitle: !separateTitle)
              else
                _landscapeToolbar(),
              const Divider(height: 1, thickness: 1),
            ],
          ),
        ),
      );
      return CustomScrollView(
        key: ValueKey(portrait ? 'portrait-tray' : 'landscape-tray'),
        slivers: [
          if (portrait)
            PinnedHeaderSliver(child: toolbar)
          else
            SliverToBoxAdapter(child: toolbar),
          if (separateTitle)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  context.l10n.trayTitle(_tray),
                  key: const ValueKey('portrait-full-title'),
                  style: _compactTitleStyle,
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_editing) ...[
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.editHint,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                  ],
                  ..._notices(),
                ],
              ),
            ),
          ),
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final height = math.max(
                0.0,
                constraints.viewportMainAxisExtent -
                    constraints.precedingScrollExtent -
                    16,
              );
              return SliverPadding(
                padding: const EdgeInsets.all(8),
                sliver: SliverToBoxAdapter(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: height),
                    child: Center(
                      child:
                          _tray.dice.isEmpty
                              ? _emptyTray()
                              : _diceBoard(availableHeight: height),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      );
    },
  );

  Widget _diceBoard({double? availableHeight}) => DiceBoard(
    availableHeight: availableHeight,
    editing: _editing,
    tiles: [
      for (final (i, die) in _tray.dice.indexed)
        DieTile(
          key: ValueKey(die.id),
          compact: availableHeight != null,
          die: die,
          position: i + 1,
          editing: _editing,
          busy: _tray.isRolling(die.id),
          onRoll: () => unawaited(_tray.rollDie(die.id)),
          onEdit: () => unawaited(_editDie(die)),
          onRemove: () => _tray.removeDie(die.id),
          onDuplicate: () => _tray.duplicateDie(die.id),
        ),
    ],
  );

  Widget _toolbar() {
    final roll = FilledButton.icon(
      onPressed: _canRollAll ? _rollAll : null,
      icon: const Icon(Icons.casino_outlined, size: 20),
      label: Text(context.l10n.rollAll),
    );
    final reset = OutlinedButton.icon(
      key: const ValueKey('reset-roll-counts'),
      onPressed: _canResetRollCounts ? _resetRollCounts : null,
      icon: const Icon(Icons.restart_alt, size: 20),
      label: Text(context.l10n.resetRollCounts),
    );
    final add = OutlinedButton.icon(
      onPressed: _addDice,
      icon: const Icon(Icons.add, size: 20),
      label: Text(context.l10n.addDice),
    );
    final sets = OutlinedButton.icon(
      onPressed: _pickSet,
      icon: const Icon(Icons.folder_open_outlined, size: 20),
      label: Text(context.l10n.sets),
    );
    final edit = OutlinedButton.icon(
      style: choiceButtonStyle(selected: _editing),
      onPressed: () => setState(() => _editing = !_editing),
      icon: Icon(_editing ? Icons.check : Icons.tune, size: 20),
      label: Text(_editing ? context.l10n.done : context.l10n.edit),
    );
    final save = OutlinedButton.icon(
      onPressed: _saveSet,
      icon: const Icon(Icons.bookmark_border, size: 20),
      label: Text(context.l10n.save),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (MediaQuery.textScalerOf(context).scale(15) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final button in [roll, reset, add, sets, edit, save])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: button,
                ),
            ],
          );
        }
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [roll, reset, add, sets, edit, save],
        );
      },
    );
  }

  Widget _emptyTray() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(
      children: [
        const Icon(Icons.casino_outlined, size: 56),
        const SizedBox(height: 16),
        Text(
          context.l10n.emptyTrayTitle,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(context.l10n.emptyTrayHelp, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _addDice,
          icon: const Icon(Icons.add),
          label: Text(context.l10n.addFirstDie),
        ),
      ],
    ),
  );

  Widget _notice(String text, {VoidCallback? dismiss}) => Container(
    margin: const EdgeInsets.only(top: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(border: Border.all(width: 2)),
    child: Row(
      children: [
        const Icon(Icons.info_outline),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            container: true,
            liveRegion: true,
            child: Text(text),
          ),
        ),
        if (dismiss != null)
          IconButton(
            onPressed: dismiss,
            icon: Icon(Icons.close, semanticLabel: context.l10n.dismissMessage),
          ),
      ],
    ),
  );
}
