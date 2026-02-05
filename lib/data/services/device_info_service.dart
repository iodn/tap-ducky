import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/device_snapshot.dart';

class DeviceInfoService {
  Future<DeviceSnapshot> getSnapshot() async {
    final deviceInfo = DeviceInfoPlugin();
    final android = await deviceInfo.androidInfo;
    final pkg = await PackageInfo.fromPlatform();

    return DeviceSnapshot(
      manufacturer: android.manufacturer,
      model: android.model,
      brand: android.brand,
      device: android.device,
      androidVersion: android.version.release,
      sdkInt: android.version.sdkInt,
      isPhysicalDevice: android.isPhysicalDevice ?? true,
      appVersion: pkg.version,
      buildNumber: pkg.buildNumber,
    );
  }
}
