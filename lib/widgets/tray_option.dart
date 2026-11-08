import 'package:flutter/material.dart';

import '../app_theme.dart';

class TrayOption extends StatelessWidget {
  const TrayOption({
    super.key,
    required this.title,
    required this.onPressed,
    this.subtitle,
    this.leading,
    this.trailing,
    this.selected,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool? selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: selected != null,
      child: OutlinedButton(
        style: choiceButtonStyle(
          selected: selected ?? false,
          padding: const EdgeInsets.all(12),
        ),
        onPressed: onPressed,
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    ),
  );
}
