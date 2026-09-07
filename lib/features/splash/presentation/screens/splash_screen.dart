import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/core/widgets/app_logo.dart';
import 'package:smart_task_manager/features/auth/data/auth_repository.dart';
import 'package:smart_task_manager/features/auth/presentation/screens/login_screen.dart';
import 'package:smart_task_manager/features/profile/data/profile_repository.dart';
import 'package:smart_task_manager/features/tasks/presentation/screens/task_list_screen.dart';

/// Initial entry screen responsible for checking user session and routing accordingly.
class SplashScreen extends ConsumerStatefulWidget {
  /// Constructs the [SplashScreen].
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  /// Verifies if a user session is cached in local Hive storage.
  ///
  /// If valid, pre-fetches the user profile from Firestore and routes to [TaskListScreen].
  /// Otherwise, redirects to [LoginScreen].
  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    final cachedUser = ref.read(authRepositoryProvider).getCachedUser();

    if (cachedUser != null && cachedUser.uid.isNotEmpty) {
      // Pre-fetch updated user profile from Firestore in background if online
      try {
        await ref
            .read(profileRepositoryProvider)
            .fetchUserProfile(cachedUser.uid);
      } catch (_) {
        // Safe fallback to locally cached profile
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TaskListScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppLogo(size: 64, subtitle: 'Organize, track, and conquer tasks'),
            SizedBox(height: 36),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
