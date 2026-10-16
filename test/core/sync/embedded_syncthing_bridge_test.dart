import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/sync/embedded_syncthing_bridge.dart';

void main() {
  test('folder-level remote sharing state is preserved', () {
    final status = EmbeddedSyncthingStatus.fromMap(<Object?, Object?>{
      'available': true,
      'running': true,
      'deviceId': 'LOCAL-DEVICE-ID',
      'connectedDeviceIds': <String>['REMOTE-DEVICE-ID'],
      'configuredDevices': <Map<String, Object?>>[
        <String, Object?>{
          'deviceId': 'REMOTE-DEVICE-ID',
          'name': 'remote',
        },
      ],
      'folderState': 'idle',
      'remoteFolderStates': <String, String>{
        'REMOTE-DEVICE-ID': 'valid',
      },
      'folderErrors': <String>[
        'first error',
        '',
      ],
      'syncProgress': <String, Object?>{
        'completion': 50.0,
      },
    });

    expect(status.remoteFolderStates['REMOTE-DEVICE-ID'], 'valid');
    expect(status.folderErrors, <String>['first error']);
    expect(status.connectedDeviceIds, contains('REMOTE-DEVICE-ID'));
  });

  test('device connectivity does not imply folder sharing', () {
    final status = EmbeddedSyncthingStatus.fromMap(<Object?, Object?>{
      'available': true,
      'running': true,
      'connectedDeviceIds': <String>['REMOTE-DEVICE-ID'],
      'remoteFolderStates': <String, String>{
        'REMOTE-DEVICE-ID': 'notSharing',
      },
    });

    expect(status.connectedDeviceIds, contains('REMOTE-DEVICE-ID'));
    expect(status.remoteFolderStates['REMOTE-DEVICE-ID'], 'notSharing');
  });
}
