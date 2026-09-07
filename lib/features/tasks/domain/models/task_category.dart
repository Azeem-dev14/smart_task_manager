enum TaskCategory {
  work('Work'),
  personal('Personal'),
  health('Health'),
  finance('Finance'),
  education('Education'),
  shopping('Shopping'),
  travel('Travel'),
  others('Others');

  final String value;
  const TaskCategory(this.value);

  static TaskCategory fromString(String? val) {
    if (val == null) return TaskCategory.work;
    return TaskCategory.values.firstWhere(
      (e) => e.value.toLowerCase() == val.toLowerCase(),
      orElse: () => TaskCategory.work,
    );
  }
}
