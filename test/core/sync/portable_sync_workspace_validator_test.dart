import 'package:flutter_app/core/sync/portable_sync_workspace_validator.dart';
import 'package:flutter_app/core/sync/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migrated settings ignore the retained legacy feature aggregate', () {
    final record = SyncRecord.bootstrap(
      kind: SyncEntityKind.settings,
      id: 'app',
      values: const <String, dynamic>{
        'id': 'app',
        'features': <String, dynamic>{
          'search': false,
          'sorting': true,
        },
        'feature.search': false,
        'feature.sorting': true,
        'themeMode': 'system',
      },
      deviceId: 'phone',
    ).copyWith(accountId: 'account-1');

    final matches = PortableSyncWorkspaceValidator.recordsMatchWorkspace(
      accountId: 'account-1',
      records: <Map<String, dynamic>>[record.toJson()],
      orders: const <String, Map<String, dynamic>>{},
      products: const <String, Map<String, dynamic>>{},
      presets: const <String, Map<String, dynamic>>{},
      settings: const <String, dynamic>{
        'id': 'app',
        'feature.search': false,
        'feature.sorting': true,
        'themeMode': 'system',
      },
    );

    expect(matches, isTrue);
  });
}
