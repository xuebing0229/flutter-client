class LegacyDeviceWarningCopy {
  const LegacyDeviceWarningCopy._();

  static String title(String deviceName) {
    final name = deviceName.trim().isEmpty ? '未知设备' : deviceName.trim();
    return '检测到「$name」版本较旧';
  }

  static String message(String deviceName) {
    final name = deviceName.trim().isEmpty ? '未知设备' : deviceName.trim();
    return '设备「$name」的同步信息不完整，可能正在使用较旧版本。'
        '当前不会阻止同步，建议尽快更新该设备。';
  }
}
