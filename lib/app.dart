import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/core/theme/app_theme.dart';
import 'package:smart_task_manager/features/profile/presentation/controllers/theme_controller.dart';
import 'package:smart_task_manager/features/splash/presentation/screens/splash_screen.dart';

/// Root application widget configuring global theming, title, and initial routing.
class SmartTaskManagerApp extends ConsumerWidget {
  /// Constructs the [SmartTaskManagerApp].
  const SmartTaskManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider);

    return MaterialApp(
      title: 'Smart Task Manager',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}
