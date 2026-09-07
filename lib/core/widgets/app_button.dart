import 'package:flutter/material.dart';

/// A reusable, customizable button component adhering to Material 3 styling.
///
/// Features built-in asynchronous loading indicator state, optional prefix icon,
/// tonal/filled variants, and full-width layout control.
class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final bool isFullWidth;
  final bool isTonal;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double verticalPadding;

  const AppButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.isFullWidth = true,
    this.isTonal = false,
    this.backgroundColor,
    this.foregroundColor,
    this.verticalPadding = 16,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = isLoading ? null : onPressed;

    final childContent = isLoading
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
        : Row(
            mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
              ],
              Text(
                text,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          );

    final style = FilledButton.styleFrom(
      padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: 20),
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    Widget buttonWidget;
    if (isTonal) {
      buttonWidget = FilledButton.tonal(
        onPressed: effectiveOnPressed,
        style: style,
        child: childContent,
      );
    } else {
      buttonWidget = FilledButton(
        onPressed: effectiveOnPressed,
        style: style,
        child: childContent,
      );
    }

    if (isFullWidth) {
      return SizedBox(
        width: double.infinity,
        child: buttonWidget,
      );
    }

    return buttonWidget;
  }
}
