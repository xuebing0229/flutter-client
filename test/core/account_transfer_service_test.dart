import 'dart:convert';

import 'package:flutter_app/core/account/account_transfer_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final descriptor = AccountTransferDescriptor(
    encryptionKey: base64UrlEncode(List<int>.generate(32, (index) => index))
        .replaceAll('=', ''),
    sourceDeviceId:
        'AAAAAAA-BBBBBBB-CCCCCCC-DDDDDDD-EEEEEEE-FFFFFFF-GGGGGGG-HHHHHHH',
    folderId:
        'artist-workbench-bootstrap-abcdefghijklmnopqrstuvwxyz123456',
  );

  for (final platform in <String>['windows', 'android']) {
    test('v175 response authenticates $platform provisional binding', () async {
      final response = await AccountTransferResponseCode.create(
        descriptor: descriptor,
        receiverDeviceId:
            'IIIIIII-JJJJJJJ-KKKKKKK-LLLLLLL-MMMMMMM-NNNNNNN-OOOOOOO-PPPPPPP',
        receiverName: 'new-device',
        receiverAppDeviceId: 'provisional-app-device-123456',
        receiverPlatform: platform,
      );

      final decoded = AccountTransferResponseCode.decode(response.encode());
      expect(decoded.receiverAppDeviceId, 'provisional-app-device-123456');
      expect(decoded.receiverPlatform, platform);
      expect(await decoded.verifies(descriptor), isTrue);
    });
  }

  test('tampering provisional app-device id invalidates binding proof', () async {
    final response = await AccountTransferResponseCode.create(
      descriptor: descriptor,
      receiverDeviceId:
          'IIIIIII-JJJJJJJ-KKKKKKK-LLLLLLL-MMMMMMM-NNNNNNN-OOOOOOO-PPPPPPP',
      receiverName: 'new-pc',
      receiverAppDeviceId: 'provisional-app-device-123456',
      receiverPlatform: 'windows',
    );

    final tampered = AccountTransferResponseCode(
      folderId: response.folderId,
      sourceDeviceId: response.sourceDeviceId,
      receiverDeviceId: response.receiverDeviceId,
      receiverName: response.receiverName,
      proof: response.proof,
      receiverAppDeviceId: 'different-app-device-123456',
      receiverPlatform: response.receiverPlatform,
      bindingProof: response.bindingProof,
    );

    expect(await tampered.verifies(descriptor), isFalse);
  });


  test('Android background service start rejection is retryable', () {
    expect(
      isDeferredSyncthingBackgroundStartError(
        PlatformException(
          code: 'SYNCTHING_ERROR',
          message: 'APP_BACKGROUND_START_DEFERRED',
        ),
      ),
      isTrue,
    );
    expect(
      isDeferredSyncthingBackgroundStartError(
        PlatformException(
          code: 'SYNCTHING_ERROR',
          message:
              'Not allowed to start service Intent {...}: app is in background',
        ),
      ),
      isTrue,
    );
    expect(
      isDeferredSyncthingBackgroundStartError(
        PlatformException(
          code: 'SYNCTHING_ERROR',
          message: '同步核心启动超时',
        ),
      ),
      isFalse,
    );
  });


}
