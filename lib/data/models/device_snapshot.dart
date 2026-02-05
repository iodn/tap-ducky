class DeviceSnapshot {
  const DeviceSnapshot({
    required this.manufacturer,
    required this.model,
    required this.brand,
    required this.device,
    required this.androidVersion,
    required this.sdkInt,
    required this.isPhysicalDevice,
    required this.appVersion,
    required this.buildNumber,
  });

  final String manufacturer;
  final String model;
  final String brand;
  final String device;
  final String androidVersion;
  final int sdkInt;
  final bool isPhysicalDevice;
  final String appVersion;
  final String buildNumber;

  Map<String, String> asMap() => {
        'Manufacturer': manufacturer,
        'Model': model,
        'Brand': brand,
        'Device': device,
        'Android': androidVersion,
        'SDK': '$sdkInt',
        'Physical device': isPhysicalDevice ? 'Yes' : 'No',
        'App version': appVersion,
        'Build number': buildNumber,
      };
}
