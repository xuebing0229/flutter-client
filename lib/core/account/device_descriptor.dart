import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

class DeviceDescriptor {
  const DeviceDescriptor({
    required this.name,
    required this.platform,
  });

  final String name;
  final String platform;

  static Future<DeviceDescriptor> current() async {
    final info = DeviceInfoPlugin();

    try {
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        final manufacturer = android.manufacturer.trim();
        final model = android.model.trim();
        final name = [manufacturer, model]
            .where((part) => part.isNotEmpty)
            .join(' ');
        return DeviceDescriptor(
          name: name.isEmpty ? 'Android 设备' : name,
          platform: 'android',
        );
      }

      if (Platform.isWindows) {
        final windows = await info.windowsInfo;
        final name = windows.computerName.trim();
        return DeviceDescriptor(
          name: name.isEmpty ? 'Windows 电脑' : name,
          platform: 'windows',
        );
      }

      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        final name = ios.name.trim();
        return DeviceDescriptor(
          name: name.isEmpty ? 'iPhone / iPad' : name,
          platform: 'ios',
        );
      }

      if (Platform.isMacOS) {
        final mac = await info.macOsInfo;
        final name = mac.computerName.trim();
        return DeviceDescriptor(
          name: name.isEmpty ? 'Mac' : name,
          platform: 'macos',
        );
      }

      if (Platform.isLinux) {
        return const DeviceDescriptor(
          name: 'Linux 电脑',
          platform: 'linux',
        );
      }
    } catch (_) {
      // Falling back to a generic device name is enough for account tracking.
    }

    return DeviceDescriptor(
      name: Platform.operatingSystem,
      platform: Platform.operatingSystem,
    );
  }
}
