import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:smart_task_manager/core/theme/text_styles.dart';
import 'package:smart_task_manager/core/widgets/app_text_field.dart';
import 'package:smart_task_manager/core/widgets/error_view.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_model.dart';
import 'package:smart_task_manager/features/tasks/presentation/controllers/task_list_notifier.dart';
import 'package:smart_task_manager/features/tasks/presentation/widgets/priority_badge.dart';

/// Full-page form for creating a new task or editing an existing one.
class TaskFormScreen extends ConsumerStatefulWidget {
  /// Existing task to edit, or `null` to create a fresh task.
  final TaskModel? existingTask;

  /// Constructs a [TaskFormScreen].
  const TaskFormScreen({super.key, this.existingTask});

  /// Pushes the form as a new page.
  static Future<void> show(BuildContext context, {TaskModel? existingTask}) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TaskFormScreen(existingTask: existingTask)),
    );
  }

  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends ConsumerState<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late TaskPriority _selectedPriority;
  late TaskCategory _selectedCategory;
  DateTime? _selectedDueDate;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final task = widget.existingTask;
    _titleController = TextEditingController(text: task?.title ?? '');
    _selectedPriority = task?.priority ?? TaskPriority.medium;
    _selectedCategory = task?.category ?? TaskCategory.work;
    _selectedDueDate = task?.dueDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  /// Opens the date picker followed by the time picker to set due date.
  ///
  /// Due dates are restricted to today or later — a task cannot be due in
  /// the past. When editing a task whose existing due date has already
  /// passed, the picker opens on today instead (it would otherwise be an
  /// invalid initial date, since it falls before [firstDate]).
  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentDue = _selectedDueDate;
    final initialDate = (currentDue != null && !currentDue.isBefore(today))
        ? currentDue
        : today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );

    if (picked != null) {
      if (!mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDueDate ?? now),
      );

      setState(() {
        if (time != null) {
          _selectedDueDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
        } else {
          _selectedDueDate = DateTime(picked.year, picked.month, picked.day, 23, 59);
        }
      });
    }
  }

  /// Submits the task form to [TaskListNotifier].
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final controller = ref.read(taskListControllerProvider.notifier);

      if (widget.existingTask == null) {
        await controller.addTask(
          title: _titleController.text.trim(),
          priority: _selectedPriority,
          category: _selectedCategory,
          dueDate: _selectedDueDate,
        );
      } else {
        await controller.updateTaskDetails(
          widget.existingTask!.copyWith(
            title: _titleController.text.trim(),
            priority: _selectedPriority,
            category: _selectedCategory,
            dueDate: _selectedDueDate,
            // `null` alone means "leave unchanged", so clearing the due date
            // needs the explicit flag.
            clearDueDate: _selectedDueDate == null,
          ),
        );
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ErrorView.showSnackBar(context, e);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existingTask != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing ? 'Edit Task' : 'New Task',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Reusable Task Title Input
                AppTextField(
                  controller: _titleController,
                  labelText: 'Task Title *',
                  prefixIcon: Icons.title_rounded,
                  autofocus: !isEditing,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Priority Selector
                Text(
                  'Priority',
                  style: context.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: TaskPriority.values.map((priority) {
                    final isSelected = _selectedPriority == priority;
                    final pColor = PriorityBadge.getColor(priority);

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: InkWell(
                          onTap: () => setState(() => _selectedPriority = priority),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? pColor.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? pColor : theme.colorScheme.outlineVariant,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(radius: 5, backgroundColor: pColor),
                                const SizedBox(width: 6),
                                Text(
                                  priority.value,
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected ? pColor : theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Category & Due Date row
                Row(
                  children: [
                    // Category Dropdown
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Category',
                            style: context.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<TaskCategory>(
                            initialValue: _selectedCategory,
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            items: TaskCategory.values.map((cat) {
                              return DropdownMenuItem(
                                value: cat,
                                child: Text(cat.value, style: context.bodyMedium),
                              );
                            }).toList(),
                            onChanged: (cat) {
                              if (cat != null) setState(() => _selectedCategory = cat);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Due Date Button
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Due Date',
                            style: context.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: _pickDueDate,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              height: 52,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: theme.colorScheme.outlineVariant),
                                color: theme.inputDecorationTheme.fillColor,
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_today_outlined, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _selectedDueDate != null
                                          ? DateFormat('MMM d, h:mm a').format(_selectedDueDate!)
                                          : 'Set date',
                                      style: context.bodyMedium?.copyWith(
                                        color: _selectedDueDate != null
                                            ? theme.colorScheme.onSurface
                                            : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (_selectedDueDate != null)
                                    GestureDetector(
                                      onTap: () => setState(() => _selectedDueDate = null),
                                      child: const Icon(Icons.clear, size: 16),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Reserve space so the floating submit button never covers
                // the last field.
                const SizedBox(height: 88),
              ],
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width - 40,
          height: 52,
          child: FloatingActionButton.extended(
            onPressed: _isSubmitting ? null : _submit,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(isEditing ? 'Update Task' : 'Create Task'),
          ),
        ),
      ),
    );
  }
}
