enum UsbRestorePhase {
  idle,
  restoring,
  waitingForUnplug,
  verifying,
  verified,
  finished,
  failed;

  static UsbRestorePhase fromStatus(Object? value, {required String state}) =>
      switch (value) {
        'RESTORING' => restoring,
        'WAITING_FOR_UNPLUG' => waitingForUnplug,
        'VERIFYING' => verifying,
        'VERIFIED' => verified,
        'FINISHED' => finished,
        'FAILED' => failed,
        _ => state == 'RESTORING' ? restoring : idle,
      };
}
