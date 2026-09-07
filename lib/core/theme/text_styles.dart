import 'package:flutter/material.dart';

/// Shorthand access to the active [TextTheme] via [BuildContext], so call
/// sites read `context.bodyMedium` instead of the more verbose
/// `Theme.of(context).textTheme.bodyMedium`.
///
/// Every screen and widget should read text styles through these getters
/// rather than hardcoding a `fontSize`, so type scale stays centralized here
/// and consistent across the app.
extension AppTextStyles on BuildContext {
  TextTheme get _textTheme => Theme.of(this).textTheme;

  /// Largest display style — hero numbers, splash headlines.
  TextStyle? get displayLarge => _textTheme.displayLarge;
  TextStyle? get displayMedium => _textTheme.displayMedium;
  TextStyle? get displaySmall => _textTheme.displaySmall;

  /// Section headlines (e.g. "Create Account").
  TextStyle? get headlineLarge => _textTheme.headlineLarge;
  TextStyle? get headlineMedium => _textTheme.headlineMedium;
  TextStyle? get headlineSmall => _textTheme.headlineSmall;

  /// Card and app bar titles.
  TextStyle? get titleLarge => _textTheme.titleLarge;
  TextStyle? get titleMedium => _textTheme.titleMedium;
  TextStyle? get titleSmall => _textTheme.titleSmall;

  /// Regular paragraph and label text.
  TextStyle? get bodyLarge => _textTheme.bodyLarge;
  TextStyle? get bodyMedium => _textTheme.bodyMedium;
  TextStyle? get bodySmall => _textTheme.bodySmall;

  /// Buttons, chips, badges.
  TextStyle? get labelLarge => _textTheme.labelLarge;
  TextStyle? get labelMedium => _textTheme.labelMedium;
  TextStyle? get labelSmall => _textTheme.labelSmall;
}
