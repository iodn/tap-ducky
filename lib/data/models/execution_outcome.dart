enum ExecutionOutcome {
  completed('Completed'),
  stopped('Stopped'),
  timedOut('Timed out'),
  failed('Failed'),
  interrupted('Interrupted');

  const ExecutionOutcome(this.label);

  final String label;

  static ExecutionOutcome? fromName(String? name) {
    return values.where((outcome) => outcome.name == name).firstOrNull;
  }
}
