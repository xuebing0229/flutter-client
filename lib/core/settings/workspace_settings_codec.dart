import 'package:flutter/material.dart';

import '../features/app_feature_store.dart';
import '../finance/pricing_preset_store.dart';
import '../theme/app_theme_palette.dart';
import '../theme/app_theme_store.dart';
import '../theme/app_ui_style.dart';
import '../../features/shared/domain/collection_view_preferences.dart';
import '../../features/shared/domain/receipt_style_store.dart';

class WorkspaceSettingsState {
  const WorkspaceSettingsState({
    required this.collectionViews,
    required this.desktopNavigationOpen,
  });

  final CollectionViewPreferences collectionViews;
  final bool desktopNavigationOpen;
}

class WorkspaceSettingsCodec {
  const WorkspaceSettingsCodec._();

  static Map<String, dynamic> capture({
    required AppThemeStore themeStore,
    required AppFeatureStore featureStore,
    required PricingPresetStore pricingPresetStore,
    required ReceiptStyleStore receiptStyleStore,
    required CollectionViewPreferences collectionViews,
    required bool desktopNavigationOpen,
    Map<String, dynamic> retainedSettings = const <String, dynamic>{},
    Map<AppFeature, bool> featureOverrides = const <AppFeature, bool>{},
  }) {
    final features = featureStore.toJson();
    return <String, dynamic>{
      ...retainedSettings,
      'id': 'app',
      'themeMode': themeStore.mode.name,
      'themePaletteId': themeStore.paletteId,
      'customThemePalettes': themeStore.exportCustomPalettes(),
      'uiStyle': themeStore.style.id,
      'pricingAdjustmentPresets': pricingPresetStore.toJson(),
      'receiptStyle': receiptStyleStore.toJson(),
      for (final feature in AppFeature.values)
        'feature.${feature.name}':
            featureOverrides[feature] ?? features[feature.name] ?? false,
      ...collectionViews.toSettings(),
      'desktopNavigationOpen': desktopNavigationOpen,
    };
  }

  static Future<WorkspaceSettingsState> apply({
    required Map<String, dynamic> settings,
    required AppThemeStore themeStore,
    required AppFeatureStore featureStore,
    required PricingPresetStore pricingPresetStore,
    required ReceiptStyleStore receiptStyleStore,
    required CollectionViewPreferences collectionViews,
    required bool desktopNavigationOpen,
    Set<AppFeature> passthroughFeatures = const <AppFeature>{},
    void Function(AppFeature feature, bool value)? onPassthroughFeature,
  }) async {
    final modeName = settings['themeMode'];
    if (modeName is String) {
      final mode = switch (modeName) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => throw const FormatException('同步主题模式无效。'),
      };
      await themeStore.setMode(mode);
    }

    if (settings.containsKey('customThemePalettes')) {
      await themeStore.replaceCustomPalettesFromJson(
        settings['customThemePalettes'],
      );
    }

    final paletteId = settings['themePaletteId'];
    if (paletteId is String) {
      await themeStore.setPaletteId(
        themeStore.containsPaletteId(paletteId)
            ? paletteId
            : AppThemePalettes.guildOriginal.id,
      );
    } else if (paletteId != null) {
      await themeStore.setPaletteId(AppThemePalettes.guildOriginal.id);
    }

    final styleId = settings['uiStyle'];
    if (styleId is String && AppUiStyle.containsId(styleId)) {
      await themeStore.setStyle(AppUiStyle.byId(styleId));
    } else if (styleId == null) {
      final legacyTextureId = settings['uiTexture'];
      if (legacyTextureId == null) {
        await themeStore.setStyle(AppUiStyle.classic);
      } else if (legacyTextureId is String) {
        await themeStore.setStyle(
          AppUiStyle.fromLegacyTextureId(legacyTextureId),
        );
      } else {
        throw const FormatException('同步 UI 风格设置无效。');
      }
    } else {
      throw const FormatException('同步 UI 风格设置无效。');
    }

    if (settings.containsKey('pricingAdjustmentPresets')) {
      pricingPresetStore.applyJson(settings['pricingAdjustmentPresets']);
    }
    if (settings.containsKey('receiptStyle')) {
      receiptStyleStore.applyJson(settings['receiptStyle']);
    }

    final nextFeatures = featureStore.toJson();
    final legacyFeatures = settings['features'];
    if (legacyFeatures is Map) {
      for (final entry in legacyFeatures.entries) {
        if (entry.key is String && entry.value is bool) {
          final feature = AppFeature.values
              .where((item) => item.name == entry.key)
              .firstOrNull;
          if (feature != null && passthroughFeatures.contains(feature)) {
            onPassthroughFeature?.call(feature, entry.value as bool);
          } else {
            nextFeatures[entry.key as String] = entry.value as bool;
          }
        }
      }
    } else if (legacyFeatures != null) {
      throw const FormatException('同步功能开关设置无效。');
    }

    for (final feature in AppFeature.values) {
      final key = 'feature.${feature.name}';
      if (!settings.containsKey(key)) continue;
      final value = settings[key];
      if (value is! bool) {
        throw FormatException('同步功能开关 ${feature.name} 格式无效。');
      }
      if (passthroughFeatures.contains(feature)) {
        onPassthroughFeature?.call(feature, value);
      } else {
        nextFeatures[feature.name] = value;
      }
    }
    await featureStore.applyJson(nextFeatures);

    return WorkspaceSettingsState(
      collectionViews: collectionViews.applySettings(settings),
      desktopNavigationOpen:
          settings['desktopNavigationOpen'] is bool
              ? settings['desktopNavigationOpen'] as bool
              : desktopNavigationOpen,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
