import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  group('platform reuse architecture', () {
    test('theme and feature stores keep behavior in shared cores', () {
      expect(
        source('lib/core/theme/app_theme_store_native.dart'),
        contains('extends AppThemeStoreCore'),
      );
      expect(
        source('lib/core/theme/app_theme_store_web.dart'),
        contains('extends AppThemeStoreCore'),
      );
      expect(
        source('lib/core/features/app_feature_store_native.dart'),
        contains('extends AppFeatureStoreCore'),
      );
      expect(
        source('lib/core/features/app_feature_store_web.dart'),
        contains('extends AppFeatureStoreCore'),
      );
    });

    test('theme color UI is one shared page', () {
      expect(
        source('lib/features/home/presentation/theme_color_page_native.dart'),
        contains('SharedThemeColorPage'),
      );
      expect(
        source('lib/features/home/presentation/theme_color_page_web.dart'),
        contains('SharedThemeColorPage'),
      );
    });

    test('sync coordinators share workspace and local record engines', () {
      for (final path in <String>[
        'lib/core/sync/sync_coordinator.dart',
        'lib/core/sync/sync_coordinator_web.dart',
      ]) {
        final text = source(path);
        expect(text, contains('SyncWorkspaceEngine'));
        expect(text, contains('buildLocalSyncRecordChange'));
      }
    });

    test('account stores share activation and session behavior', () {
      for (final path in <String>[
        'lib/core/account/account_store.dart',
        'lib/core/account/web_account_store.dart',
      ]) {
        final text = source(path);
        expect(text, contains('verifyAndRedeemAccountActivation'));
        expect(text, contains('AccountSessionController'));
        expect(text, contains('accountStatusForRecord'));
      }

      final sharedSession =
          source('lib/core/account/account_session_controller.dart');
      expect(sharedSession, contains('accountCredentialsMatch'));
      expect(sharedSession, contains('accountStatusForRecord'));

      expect(
        source('lib/core/account/web_account_store.dart'),
        isNot(contains('_constantTimeEquals')),
      );
    });

    test('workspace pages and settings are constructed from shared code', () {
      final native = source('lib/features/home/presentation/home_page.dart');
      final web = source('lib/app/app_web.dart');
      for (final token in <String>[
        'buildWorkspaceMainPage',
        'buildWorkspaceCommonToolPage',
        'WorkspaceSettingsCodec',
        'createWorkspacePublicPeerSyncService',
        'workspaceTabSpecs',
      ]) {
        expect(native, contains(token));
        expect(web, contains(token));
      }
    });

    test('reference image UI has no platform copy', () {
      expect(
        source(
          'lib/features/orders/presentation/'
          'order_reference_image_widgets_native.dart',
        ).trim(),
        "export 'order_reference_image_widgets_common.dart';",
      );
      expect(
        source(
          'lib/features/orders/presentation/'
          'order_reference_image_widgets_web.dart',
        ).trim(),
        "export 'order_reference_image_widgets_common.dart';",
      );
    });

    test('web app consumes platform facades instead of concrete web stores', () {
      final web = source('lib/app/app_web.dart');
      expect(
        web,
        isNot(contains("order_reference_image_store_web.dart")),
      );
      expect(
        web,
        contains("order_reference_image_store.dart"),
      );
    });

    test('relay protocol and backup rules stay shared', () {
      for (final path in <String>[
        'lib/core/sync/public_relay_client_native.dart',
        'lib/core/sync/public_relay_client_web.dart',
      ]) {
        final text = source(path);
        expect(text, contains('PublicRelayClientBase'));
        expect(text, contains('buildPublicRelayUri'));
        expect(text, contains('encodePublicRelayPublish'));
      }

      expect(
        source('lib/core/portability/full_backup_bundle_service.dart'),
        contains('BackupAssetRules'),
      );
      expect(
        source('lib/core/portability/web_backup_reader.dart'),
        contains('BackupAssetRules'),
      );
    });
  });
}
