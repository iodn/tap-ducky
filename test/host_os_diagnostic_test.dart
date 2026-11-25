import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/data/models/host_os.dart';

void main() {
  group('HostOsDiagnostic', () {
    test('defaults to Unknown with no source', () {
      const diagnostic = HostOsDiagnostic();

      expect(diagnostic.os, HostOs.unknown);
      expect(diagnostic.source, HostOsSource.none);
      expect(diagnostic.label, 'Unknown');
      expect(diagnostic.isKnown, isFalse);
      expect(diagnostic.isSessionScoped, isFalse);
    });

    test('manual selection is explicitly labelled', () {
      const diagnostic = HostOsDiagnostic(
        os: HostOs.windows,
        source: HostOsSource.manual,
      );

      expect(diagnostic.label, 'Windows (Manually selected)');
      expect(diagnostic.explanation, contains('Manually selected'));
      expect(diagnostic.isSessionScoped, isFalse);
    });

    test('inference displays the OS name', () {
      const diagnostic = HostOsDiagnostic(
        os: HostOs.windows,
        source: HostOsSource.inferred,
      );

      expect(diagnostic.label, 'Windows');
      expect(diagnostic.explanation, contains('Inferred'));
      expect(diagnostic.isSessionScoped, isTrue);
    });

    test('verified labels the companion', () {
      const diagnostic = HostOsDiagnostic(
        os: HostOs.linux,
        source: HostOsSource.verified,
      );

      expect(diagnostic.label, 'Linux (Verified by companion)');
      expect(diagnostic.isSessionScoped, isTrue);
    });

    test('rejects a source without a known OS', () {
      expect(
        () => HostOsDiagnostic(
          os: HostOs.unknown,
          source: HostOsSource.inferred,
        ),
        throwsAssertionError,
      );
    });

    test('rejects a known OS without a source', () {
      expect(
        () => HostOsDiagnostic(os: HostOs.macos),
        throwsAssertionError,
      );
    });

    test('parses only the supported OS names', () {
      expect(HostOs.fromName('windows'), HostOs.windows);
      expect(HostOs.fromName('ios'), HostOs.ios);
      expect(HostOs.fromName('beos'), HostOs.unknown);
      expect(HostOs.fromName(null), HostOs.unknown);
    });
  });
}
