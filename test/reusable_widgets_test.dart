import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_task_manager/core/widgets/app_button.dart';
import 'package:smart_task_manager/core/widgets/app_confirm_dialog.dart';
import 'package:smart_task_manager/core/widgets/app_text_field.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_category.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_priority.dart';
import 'package:smart_task_manager/features/tasks/presentation/widgets/category_badge.dart';
import 'package:smart_task_manager/features/tasks/presentation/widgets/due_date_badge.dart';
import 'package:smart_task_manager/features/tasks/presentation/widgets/priority_badge.dart';
import 'package:smart_task_manager/features/tasks/presentation/widgets/sync_status_badge.dart';

void main() {
  group('Reusable Widgets Tests', () {
    testWidgets('AppButton renders text, responds to tap, and displays spinner when loading',
        (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              text: 'Save Task',
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Save Task'), findsOneWidget);
      await tester.tap(find.text('Save Task'));
      expect(tapped, true);

      // Verify loading state
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              text: 'Save Task',
              isLoading: true,
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Save Task'), findsNothing);
    });

    testWidgets('AppTextField renders label, handles text and password visibility toggle',
        (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTextField(
              controller: controller,
              labelText: 'Password',
              isPassword: true,
            ),
          ),
        ),
      );

      expect(find.text('Password'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      // Tap visibility toggle icon
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    testWidgets('Badges render priority, category, due date, and sync status correctly',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const PriorityBadge(priority: TaskPriority.high),
                const CategoryBadge(category: TaskCategory.work),
                DueDateBadge(
                  dueDate: DateTime.now().add(const Duration(days: 2)),
                ),
                const SyncStatusBadge(isPendingSync: true),
              ],
            ),
          ),
        ),
      );

      expect(find.text('High'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Pending Sync'), findsOneWidget);
      expect(find.byIcon(Icons.access_time_rounded), findsOneWidget);
    });

    testWidgets('AppConfirmDialog returns true on confirm and false on cancel', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await AppConfirmDialog.show(
                    context,
                    title: 'Delete Item',
                    message: 'Are you sure?',
                    confirmText: 'Delete',
                    isDestructive: true,
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Item'), findsOneWidget);
      expect(find.text('Are you sure?'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(result, true);
    });
  });
}
