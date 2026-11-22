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
}
