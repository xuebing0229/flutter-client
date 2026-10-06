class LegacyDeviceWarningCopy {
  const LegacyDeviceWarningCopy._();

  static const title = '检测到设备版本较旧';

  static String message(String deviceName) {
    final name = deviceName.trim().isEmpty ? '未知设备' : deviceName.trim();
    return '设备「$name」尚未上报同步协议版本，可能正在使用较旧版本。'
        '当前不会阻止同步，建议尽快更新该设备。';
  }
}
