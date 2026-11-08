import 'package:flutter/material.dart';

Future<T?> showTrayDialog<T>(BuildContext context, WidgetBuilder builder) {
  return showDialog<T>(
    context: context,
    animationStyle: AnimationStyle.noAnimation,
    barrierColor: Colors.transparent,
    builder:
        (context) => Dialog(
          insetAnimationDuration: Duration.zero,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(20),
          constraints: BoxConstraints(
            maxWidth: 540,
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(width: 2),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: builder(context),
          ),
        ),
  );
}
