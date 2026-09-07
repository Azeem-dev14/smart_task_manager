import 'package:flutter/material.dart';
import 'package:smart_task_manager/core/theme/text_styles.dart';

/// A reusable application branding widget displaying the app icon, title, and optional subtitle.
class AppLogo extends StatelessWidget {
  final double size;
  final String? subtitle;
  final bool showTitle;

  const AppLogo({
    super.key,
    this.size = 56,
    this.subtitle,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(size * 0.35),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(size * 0.42),
          ),
          child: Icon(
            Icons.check_circle_rounded,
            size: size,
            color: theme.colorScheme.primary,
          ),
        ),
        if (showTitle) ...[
          const SizedBox(height: 18),
          Text(
            'Smart Task Manager',
            textAlign: TextAlign.center,
            style: context.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: context.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }
}
