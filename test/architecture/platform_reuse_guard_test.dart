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

    test('platform adapters keep reusable helpers shared', () {
      for (final path in <String>[
        'lib/features/imports/data/screenshot_ocr_service_native.dart',
        'lib/features/imports/data/screenshot_ocr_service_web.dart',
      ]) {
        expect(source(path), contains('parseScreenshotOcrPayload'));
      }

      for (final path in <String>[
        'lib/core/theme/theme_palette_transfer_service_native.dart',
        'lib/core/theme/theme_palette_transfer_service_web.dart',
      ]) {
        expect(source(path), contains('ThemePaletteTransferCodec'));
      }

      for (final path in <String>[
        'lib/features/imports/data/screenshot_import_history_native.dart',
        'lib/features/imports/data/screenshot_import_history_web.dart',
      ]) {
        expect(source(path), contains('hashScreenshotBytes'));
      }

      for (final path in <String>[
        'lib/features/shared/data/receipt_style_image_bridge_native.dart',
        'lib/features/shared/data/receipt_style_image_bridge_web.dart',
      ]) {
        expect(source(path), contains('PickedReceiptStyleImage'));
      }
    });

    test('PWA install state does not pretend a launcher shortcut exists', () {
      final bridge = source('web/pwa_platform_bridge.js');
      final webApp = source('lib/app/app_web.dart');

      expect(bridge, contains('isStandalonePwa()'));
      expect(bridge, contains('getInstalledRelatedApps'));
      expect(bridge, contains("window.addEventListener('appinstalled'"));
      expect(
        bridge,
        contains('userChoice only confirms the user\'s choice'),
      );
      expect(
        webApp,
        isNot(contains('冒险者公会已经作为应用添加到桌面。')),
      );
      expect(webApp, contains('webPwaInstalledState'));
      expect(webApp, contains('网页版应用已安装'));
      expect(webApp, contains('网页不能直接申请系统的“创建桌面快捷方式”权限'));
    });

    test('PWA startup migrates old workers before Flutter loads', () {
      final index = source('web/index.html');
      final bootstrap = source('web/flutter_bootstrap.js');
      final worker = source('web/pwa_service_worker.js');
      final finalizer = source('tool/finalize_pwa.py');

      expect(index, contains('__PWA_BOOT_VERSION__'));
      expect(index, contains('navigator.serviceWorker.getRegistrations()'));
      expect(index, contains('registration.unregister()'));
      expect(index, contains("window.caches.delete(key)"));
      expect(index, contains("flutter_bootstrap.js' + versionQuery"));
      expect(
        index,
        isNot(contains('<script src="flutter_bootstrap.js"')),
      );

      expect(bootstrap, contains('__PWA_BOOT_VERSION__'));
      expect(bootstrap, contains('build.mainJsPath'));
      expect(bootstrap, contains("build.mainJsPath.includes('?')"));
      expect(bootstrap, contains("versionQuery = 'v='"));

      expect(worker, contains('LEGACY_FLUTTER_CACHES'));
      expect(worker, contains('NETWORK_FIRST_PATHS'));
      expect(worker, contains("'/flutter_bootstrap.js'"));
      expect(worker, contains("'/main.dart.js'"));
      expect(worker, contains("cache: 'no-cache'"));
      expect(worker, isNot(contains('caches.match(request)')));

      expect(finalizer, contains('BOOT_TOKEN'));
      expect(finalizer, contains('BOOT_FILES'));
      expect(finalizer, contains('source.replace(BOOT_TOKEN, build_number)'));
    });

    test('PWA startup exposes the exact failing boot stage', () {
      final index = source('web/index.html');
      final bootstrap = source('web/flutter_bootstrap.js');

      expect(index, contains('pwa-startup-status'));
      expect(index, contains('adventurersGuildBootStage'));
      expect(index, contains('adventurersGuildBootFailure'));
      expect(index, contains("window.addEventListener('error'"));
      expect(index, contains("window.addEventListener('unhandledrejection'"));
      expect(index, contains("window.addEventListener('flutter-first-frame'"));
      expect(index, contains('超过 20 秒仍未出现 Flutter 首帧'));

      expect(bootstrap, contains('onEntrypointLoaded'));
      expect(bootstrap, contains('initializeEngine(engineConfig)'));
      expect(bootstrap, contains('await appRunner.runApp()'));
      expect(bootstrap, contains('verboseBuildSelection: true'));
      expect(
        bootstrap,
        contains("adventurersGuildBootFailure?.('Flutter 引擎或应用启动失败'"),
      );
    });

    test('Android PWA avoids WebGL context-loss rendering', () {
      final bootstrap = source('web/flutter_bootstrap.js');
      final referenceImages = source(
        'lib/features/orders/presentation/'
        'order_reference_image_widgets_common.dart',
      );

      expect(bootstrap, contains('/Android/i'));
      expect(bootstrap, contains('canvasKitForceCpuOnly: isAndroid'));
      expect(bootstrap, contains('_flutter.loader.load({'));
      expect(
        RegExp(r'filterQuality: FilterQuality\.low')
            .allMatches(referenceImages)
            .length,
        greaterThanOrEqualTo(2),
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
