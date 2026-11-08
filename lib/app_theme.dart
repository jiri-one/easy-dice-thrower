import 'package:flutter/material.dart';

WidgetStateProperty<BorderSide> _focusSide({required bool inverted}) =>
    WidgetStateProperty.resolveWith((states) {
      final focused = states.contains(WidgetState.focused);
      return BorderSide(
        color: focused && inverted ? Colors.white : Colors.black,
        width: focused ? 3 : 1.5,
      );
    });

ButtonStyle choiceButtonStyle({
  required bool selected,
  EdgeInsetsGeometry? padding,
  Size? minimumSize,
}) => ButtonStyle(
  animationDuration: Duration.zero,
  backgroundColor: WidgetStateProperty.resolveWith(
    (states) =>
        selected && !states.contains(WidgetState.disabled)
            ? Colors.black
            : Colors.white,
  ),
  foregroundColor: WidgetStateProperty.resolveWith(
    (states) =>
        states.contains(WidgetState.disabled)
            ? Colors.black54
            : selected
            ? Colors.white
            : Colors.black,
  ),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  side: _focusSide(inverted: selected),
  padding: padding == null ? null : WidgetStatePropertyAll(padding),
  minimumSize: minimumSize == null ? null : WidgetStatePropertyAll(minimumSize),
);

ThemeData buildAppTheme() {
  final colors = ColorScheme.fromSeed(
    seedColor: Colors.black,
    brightness: Brightness.light,
  ).copyWith(
    primary: Colors.black,
    onPrimary: Colors.white,
    secondary: Colors.black,
    onSecondary: Colors.white,
    surface: Colors.white,
    onSurface: Colors.black,
    onSurfaceVariant: Colors.black,
    outline: Colors.black,
    outlineVariant: Colors.black,
    error: Colors.black,
    onError: Colors.white,
    surfaceTint: Colors.transparent,
  );
  final buttons = ButtonStyle(
    animationDuration: Duration.zero,
    minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    side: WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        color: Colors.black,
        width: states.contains(WidgetState.focused) ? 3 : 1.5,
      ),
    ),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: Colors.white,
    canvasColor: Colors.white,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    dividerColor: Colors.black,
    disabledColor: Colors.black54,
    filledButtonTheme: FilledButtonThemeData(
      style: buttons.copyWith(
        side: _focusSide(inverted: true),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.disabled)
                  ? Colors.white
                  : Colors.black,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.disabled)
                  ? Colors.black54
                  : Colors.white,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: buttons.copyWith(
        foregroundColor: const WidgetStatePropertyAll(Colors.black),
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: buttons.copyWith(
        side: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.focused)
                  ? const BorderSide(width: 2)
                  : BorderSide.none,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: buttons.copyWith(
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        side: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.focused)
                  ? const BorderSide(width: 2)
                  : BorderSide.none,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(width: 2.5),
      ),
      floatingLabelStyle: const TextStyle(color: Colors.black),
      helperMaxLines: 4,
      errorMaxLines: 3,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Colors.black,
      selectionColor: Color(0xffdddddd),
      selectionHandleColor: Colors.black,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _InstantTransitions(),
        TargetPlatform.iOS: _InstantTransitions(),
        TargetPlatform.linux: _InstantTransitions(),
        TargetPlatform.macOS: _InstantTransitions(),
        TargetPlatform.windows: _InstantTransitions(),
      },
    ),
  );
}

class _InstantTransitions extends PageTransitionsBuilder {
  const _InstantTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
