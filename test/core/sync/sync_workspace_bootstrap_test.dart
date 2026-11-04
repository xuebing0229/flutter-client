import 'package:flutter_app/core/sync/sync_models.dart';
import 'package:flutter_app/core/sync/sync_workspace_engine.dart';
import 'package:flutter_test/flutter_test.dart';

SyncRecord _record(
  SyncEntityKind kind,
  String id,
  Map<String, dynamic> values,
) {
  return SyncRecord.bootstrap(
    kind: kind,
    id: id,
    values: <String, dynamic>{'id': id, ...values},
    deviceId: 'existing-device',
  ).copyWith(accountId: 'account-1');
}

void main() {
  test('initial remote baseline waits for both settings and node presets', () {
    final records = <SyncEntityKind, Map<String, SyncRecord>>{
      for (final kind in SyncEntityKind.values) kind: <String, SyncRecord>{},
    };

    expect(hasInitialRemoteWorkspaceBaseline(records), isFalse);

    records[SyncEntityKind.settings]!['app'] = _record(
      SyncEntityKind.settings,
      'app',
      <String, dynamic>{'themeMode': 'dark'},
    );
    expect(hasInitialRemoteWorkspaceBaseline(records), isFalse);

    records[SyncEntityKind.nodePreset]!['default'] = _record(
      SyncEntityKind.nodePreset,
      'default',
      <String, dynamic>{'name': '默认节点', 'nodes': <dynamic>[]},
    );
    expect(hasInitialRemoteWorkspaceBaseline(records), isTrue);
  });
}
