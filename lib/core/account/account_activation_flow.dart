import 'activation_api.dart';
import 'offline_license.dart';

void validateNewAccountCredentials({
  required String accountName,
  required String password,
}) {
  final trimmedName = accountName.trim();
  if (trimmedName.length < 2 || trimmedName.length > 32) {
    throw const FormatException('账号名长度需要在 2–32 个字符之间。');
  }
  if (password.length < 6) {
    throw const FormatException('密码至少需要 6 个字符。');
  }
}

Future<ActivationLicense> verifyAndRedeemAccountActivation({
  required String activationCode,
  required String accountName,
  required String password,
  required OfflineLicenseVerifier verifier,
  required ActivationApiClient activationApi,
  required bool Function(String accountId) hasLocalAccount,
  required Future<String> Function(ActivationLicense license) claimFor,
  required Future<void> Function(String accountId) clearClaim,
}) async {
  validateNewAccountCredentials(
    accountName: accountName,
    password: password,
  );

  final license = await verifier.verify(activationCode);
  if (hasLocalAccount(license.accountId)) {
    throw const FormatException('这个激活码对应的账号已经存在于本机，请直接登录该账号。');
  }

  final claimId = await claimFor(license);
  try {
    final redemption = await activationApi.redeem(
      activationCode: activationCode,
      claimId: claimId,
    );
    if (redemption.accountId != license.accountId ||
        redemption.serial != license.serial) {
      throw const FormatException('激活服务器返回的账号身份与激活码不一致。');
    }
  } on ActivationApiException catch (error) {
    if (error.code == 'already_redeemed' || error.code == 'invalid_code') {
      await clearClaim(license.accountId);
    }
    throw FormatException(error.message);
  }

  return license;
}
