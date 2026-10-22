import 'package:flutter_app/core/sync/embedded_syncthing_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diagnostic status keeps folder and global peers separate', () {
    final status = EmbeddedSyncthingStatus.fromMap(<Object?, Object?>{
      'available': true,
      'running': true,
      'deviceId': 'LOCAL',
      'connectedDeviceIds': <String>['FOLDER-PEER'],
      'configuredDevices': <Map<String, Object?>>[
        <String, Object?>{'deviceId': 'FOLDER-PEER', 'name': 'folder peer'},
      ],
      'allConnectedDeviceIds': <String>['FOLDER-PEER', 'OLD-PEER'],
      'allConfiguredDevices': <Map<String, Object?>>[
        <String, Object?>{'deviceId': 'FOLDER-PEER', 'name': 'folder peer'},
        <String, Object?>{'deviceId': 'OLD-PEER', 'name': 'old peer'},
      ],
      'folderState': 'idle',
      'remoteFolderStates': <String, String>{
        'FOLDER-PEER': 'notSharing',
      },
    });

    expect(status.connectedDeviceIds, <String>['FOLDER-PEER']);
    expect(status.configuredDevices.single['deviceId'], 'FOLDER-PEER');
    expect(
      status.allConnectedDeviceIds,
      <String>['FOLDER-PEER', 'OLD-PEER'],
    );
    expect(
      status.allConfiguredDevices.map((item) => item['deviceId']).toList(),
      <String>['FOLDER-PEER', 'OLD-PEER'],
    );
    expect(status.remoteFolderStates['FOLDER-PEER'], 'notSharing');
  });
}
