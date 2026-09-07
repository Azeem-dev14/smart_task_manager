import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/core/widgets/app_logo.dart';
import 'package:smart_task_manager/features/auth/data/auth_repository.dart';
import 'package:smart_task_manager/features/auth/presentation/screens/login_screen.dart';
import 'package:smart_task_manager/features/profile/data/profile_repository.dart';
import 'package:smart_task_manager/features/tasks/presentation/screens/task_list_screen.dart';

/// Initial entry screen responsible for restoring the session and routing accordingly.
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
    _restoreSession();
  }

  /// Restores a persistent login session.
  ///
  /// Firebase is authoritative for whether the session is still valid; when one
  /// exists the Firestore profile is loaded (so the saved theme applies before
  /// the dashboard appears) and the user goes straight to the task list.
  Future<void> _restoreSession() async {
    final authRepository = ref.read(authRepositoryProvider);

    final user = await authRepository.restoreSession();

    if (user != null) {
      try {
        final profile = await ref
            .read(profileRepositoryProvider)
            .fetchUserProfile(user.uid, fallback: user);
        await authRepository.cacheUser(profile);
      } catch (_) {
        // Offline or no profile document yet: continue with the cached session.
      }
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => user != null ? const TaskListScreen() : const LoginScreen(),
      ),
    );
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
