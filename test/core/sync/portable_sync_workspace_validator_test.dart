import 'package:flutter_app/core/portability/app_backup_data.dart';
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

  test('legacy uiTexture does not block a modern full backup', () {
    final record = SyncRecord.bootstrap(
      kind: SyncEntityKind.settings,
      id: 'app',
      values: const <String, dynamic>{
        'id': 'app',
        'themeMode': 'system',
        'themePaletteId': 'guildOriginal',
        'uiStyle': 'classic',
        'uiTexture': 'frosted',
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
        'themeMode': 'system',
        'themePaletteId': 'guildOriginal',
        'uiStyle': 'classic',
      },
    );

    expect(matches, isTrue);
  });

  test('backup-only settings do not invalidate portable sync history', () {
    final record = SyncRecord.bootstrap(
      kind: SyncEntityKind.settings,
      id: 'app',
      values: const <String, dynamic>{
        'id': 'app',
        'themeMode': 'system',
        'themePaletteId': 'guild-original',
        'uiStyle': 'classic',
      },
      deviceId: 'phone',
    ).copyWith(accountId: 'account-1');

    final backup = AppBackupData(
      exportedAt: DateTime.utc(2026, 10, 16),
      orders: const [],
      products: const [],
      nodePresets: const [],
      syncRecords: <Map<String, dynamic>>[record.toJson()],
      settings: const <String, dynamic>{
        'themeMode': 'system',
        'themePaletteId': 'guild-original',
        'uiStyle': 'classic',
        'screenshotImportHistory': <String>['orders|abc|0'],
        'desktopPetBackup': <String, dynamic>{
          'schema': 1,
          'presets': <dynamic>[],
        },
      },
    );

    expect(
      () => PortableSyncWorkspaceValidator.validateBackup(
        backup: backup,
        accountId: 'account-1',
      ),
      returnsNormally,
    );
  });
}
