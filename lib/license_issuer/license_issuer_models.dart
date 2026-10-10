class IssuedLicenseRecord {
  const IssuedLicenseRecord({
    required this.accountId,
    required this.serial,
    required this.activationCode,
    required this.createdAt,
    this.note = '',
    this.generatedBy = '',
    this.soldAt,
    this.soldBy,
    this.redeemedAt,
  });

  final String accountId;
  final String serial;
  final String activationCode;
  final DateTime createdAt;
  final String note;
  final String generatedBy;
  final DateTime? soldAt;
  final String? soldBy;
  final DateTime? redeemedAt;

  bool get isSold => soldAt != null;
  bool get isRedeemed => redeemedAt != null;
  bool get isLegacyCode => activationCode.startsWith('AW1.');

  IssuedLicenseRecord copyWith({
    String? note,
    String? generatedBy,
    DateTime? soldAt,
    String? soldBy,
    DateTime? redeemedAt,
    bool clearSoldAt = false,
    bool clearSoldBy = false,
    bool clearRedeemedAt = false,
  }) {
    return IssuedLicenseRecord(
      accountId: accountId,
      serial: serial,
      activationCode: activationCode,
      createdAt: createdAt,
      note: note ?? this.note,
      generatedBy: generatedBy ?? this.generatedBy,
      soldAt: clearSoldAt ? null : soldAt ?? this.soldAt,
      soldBy: clearSoldBy ? null : soldBy ?? this.soldBy,
      redeemedAt:
          clearRedeemedAt ? null : redeemedAt ?? this.redeemedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'accountId': accountId,
        'serial': serial,
        'activationCode': activationCode,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'note': note,
        'generatedBy': generatedBy,
        'soldAt': soldAt?.toUtc().toIso8601String(),
        'soldBy': soldBy,
        'redeemedAt': redeemedAt?.toUtc().toIso8601String(),
      };

  factory IssuedLicenseRecord.fromJson(Map<String, dynamic> json) {
    String requiredString(String field) {
      final value = json[field];
      if (value is! String || value.isEmpty) {
        throw FormatException('发码记录字段 $field 格式无效。');
      }
      return value;
    }

    DateTime requiredDate(Object? value, String field) {
      if (value is! String) {
        throw FormatException('发码记录字段 $field 时间格式无效。');
      }
      final parsed = DateTime.tryParse(value);
      if (parsed == null) {
        throw FormatException('发码记录字段 $field 时间格式无效。');
      }
      return parsed;
    }

    final serial = requiredString('serial');
    if (int.tryParse(serial) == null) {
      throw const FormatException('发码记录编号格式无效。');
    }
    final note = json['note'];
    if (note is! String) {
      throw const FormatException('发码记录备注格式无效。');
    }

    final generatedBy = json['generatedBy'];
    if (generatedBy != null && generatedBy is! String) {
      throw const FormatException('发码记录生成者格式无效。');
    }
    final soldBy = json['soldBy'];
    if (soldBy != null && soldBy is! String) {
      throw const FormatException('发码记录售出人格式无效。');
    }

    final soldAt = json['soldAt'];
    final parsedSoldAt =
        soldAt == null ? null : requiredDate(soldAt, 'soldAt');
    final redeemedAt = json['redeemedAt'];
    final parsedRedeemedAt = redeemedAt == null
        ? null
        : requiredDate(redeemedAt, 'redeemedAt');

    return IssuedLicenseRecord(
      accountId: requiredString('accountId'),
      serial: serial,
      activationCode: requiredString('activationCode'),
      createdAt: requiredDate(json['createdAt'], 'createdAt'),
      note: note,
      generatedBy: (generatedBy as String?)?.trim().isNotEmpty == true
          ? (generatedBy as String).trim()
          : '旧记录',
      soldAt: parsedSoldAt,
      soldBy: parsedSoldAt == null
          ? null
          : ((soldBy as String?)?.trim().isNotEmpty == true
              ? (soldBy as String).trim()
              : '旧记录'),
      redeemedAt: parsedRedeemedAt,
    );
  }
}
