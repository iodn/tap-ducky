import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/data/services/platform_gadget_service.dart';
import 'package:tap_ducky/state/controllers/hid_status_controller.dart';

void main() {
  test(
    'a recovered session uses the native role and can be armed without a host',
    () {
      final state = HidStatus.fromGadgetStatus(
        GadgetStatus.fromMap({
          'state': 'ACTIVE',
          'activeProfileId': 'comp_saved',
          'activeRoleType': 'composite',
          'deviceConnected': false,
        }),
      );

      expect(state.sessionArmed, isTrue);
      expect(state.activeProfileId, 'comp_saved');
      expect(state.activeProfileType, 'composite');
      expect(state.deviceConnected, isFalse);
    },
  );

  test('only a verified active state counts as armed', () {
    for (final state in ['IDLE', 'ACTIVATING', 'ERROR']) {
      expect(GadgetStatus.fromMap({'state': state}).isActive, isFalse);
    }
  });

  test('disarm distinguishes USB restoration from a restored session', () {
    final restoring = HidStatus.fromGadgetStatus(
      GadgetStatus.fromMap({
        'state': 'RESTORING',
        'desiredArmed': false,
        'gadgetBound': true,
        'prepared': true,
      }),
    );
    final restored = HidStatus.fromGadgetStatus(
      GadgetStatus.fromMap({
        'state': 'IDLE',
        'desiredArmed': false,
        'gadgetBound': false,
        'prepared': false,
      }),
    );

    expect(restoring.sessionArmed, isFalse);
    expect(restoring.usbRestoring, isTrue);
    expect(restoring.gadgetBound, isTrue);
    expect(restored.sessionArmed, isFalse);
    expect(restored.usbRestoring, isFalse);
    expect(restored.gadgetBound, isFalse);
  });

  test('armed waiting keeps logical arm separate from host connection', () {
    final hid = HidStatus.fromGadgetStatus(
      GadgetStatus.fromMap({
        'state': 'ACTIVE',
        'desiredArmed': true,
        'gadgetBound': true,
        'prepared': true,
        'deviceConnected': false,
      }),
    );

    expect(hid.sessionArmed, isTrue);
    expect(hid.gadgetBound, isTrue);
    expect(hid.deviceConnected, isFalse);
  });

  test('stock USB can detect a PC before TapDucky HID is prepared', () {
    final status = GadgetStatus.fromMap({
      'state': 'ARMING',
      'desiredArmed': true,
      'deviceConnected': false,
      'pcConnected': true,
      'udcState': 'configured',
    });
    final hid = HidStatus.fromGadgetStatus(GadgetStatus.fromMap(status.toMap()));

    expect(hid.sessionArmed, isTrue);
    expect(hid.pcConnected, isTrue);
    expect(hid.gadgetBound, isFalse);
    expect(hid.deviceConnected, isFalse);
  });
}
