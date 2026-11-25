/// Host OS diagnostics for the USB target.
///
/// The manual label is a diagnostic preference. Scripts get the session
/// fingerprint directly from the Android backend.
enum HostOs {
  unknown('Unknown'),
  windows('Windows'),
  macos('macOS'),
  linux('Linux'),
  chromeos('ChromeOS'),
  android('Android'),
  ios('iOS');

  const HostOs(this.displayName);

  final String displayName;

  static HostOs fromName(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return HostOs.unknown;
    for (final os in HostOs.values) {
      if (os.name == value) return os;
    }
    return HostOs.unknown;
  }
}

/// How the host OS value was obtained.
///
/// [none] and [unknown] always travel together. [verified] is reserved for a
/// future companion running on the host; no companion is required for HID use
/// and none is wired into the app today.
enum HostOsSource { none, manual, verified, inferred }

class HostOsDiagnostic {
  const HostOsDiagnostic({
    this.os = HostOs.unknown,
    this.source = HostOsSource.none,
  }) : assert(
          (os == HostOs.unknown) == (source == HostOsSource.none),
          'A known OS requires a source, and Unknown must not have one.',
        );

  static const unknown = HostOsDiagnostic();

  final HostOs os;
  final HostOsSource source;

  bool get isKnown => os != HostOs.unknown;

  /// Inferred and verified values belong to one USB session and must be
  /// discarded when that session ends.
  bool get isSessionScoped =>
      source == HostOsSource.inferred || source == HostOsSource.verified;

  /// Display name with an explicit label for manually selected values.
  String get label {
    if (os == HostOs.unknown) return 'Unknown';
    switch (source) {
      case HostOsSource.none:
        return 'Unknown';
      case HostOsSource.manual:
        return '${os.displayName} (Manually selected)';
      case HostOsSource.verified:
        return '${os.displayName} (Verified by companion)';
      case HostOsSource.inferred:
        return os.displayName;
    }
  }

  String get explanation {
    if (os == HostOs.unknown) {
      return 'No host OS information is available.';
    }
    switch (source) {
      case HostOsSource.none:
        return 'No host OS information is available.';
      case HostOsSource.manual:
        return 'Manually selected for diagnostics only. It never selects, starts, or changes a script.';
      case HostOsSource.verified:
        return 'Reported by a TapDucky companion on the host.';
      case HostOsSource.inferred:
        return 'Inferred from USB enumeration.';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is HostOsDiagnostic && other.os == os && other.source == source;

  @override
  int get hashCode => Object.hash(os, source);

  @override
  String toString() => 'HostOsDiagnostic(${os.name}, ${source.name})';
}
