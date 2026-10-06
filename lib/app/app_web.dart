import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/account/account_models.dart';
import '../core/account/web_account_store.dart';
import '../core/features/app_feature_store.dart';
import '../core/portability/app_backup_data.dart';
import '../core/portability/web_backup_reader.dart';
import '../core/sync/sync_entity_codec.dart';
import '../core/sync/sync_models.dart';
import '../core/sync/sync_ui_coordinator.dart';
import '../core/theme/app_theme_palette.dart';
import '../core/theme/app_theme_store.dart';
import '../features/home/presentation/archive_page.dart';
import '../features/home/presentation/feature_toggle_page.dart';
import '../features/home/presentation/theme_color_page.dart';
import '../features/orders/data/node_presets.dart';
import '../features/orders/data/order_reference_image_store.dart';
import '../features/orders/presentation/add_order_page.dart';
import '../features/orders/presentation/node_preset_page.dart';
import '../features/orders/presentation/order_queue_page.dart';
import '../features/orders/state/order_store.dart';
import '../features/products/presentation/add_product_page.dart';
import '../features/products/presentation/product_page.dart';
import '../features/products/state/product_store.dart';
import '../features/schedule/presentation/schedule_page.dart';
import '../features/statistics/presentation/statistics_page.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final AppThemeStore _themeStore = AppThemeStore();
  final AppFeatureStore _featureStore = AppFeatureStore();
  final WebAccountStore _accountStore = WebAccountStore();

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await Future.wait<void>([
      _themeStore.load(),
      _featureStore.load(),
      _accountStore.load(),
    ]);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _themeStore.dispose();
    _featureStore.dispose();
    _accountStore.dispose();
    super.dispose();
  }

  Color _onColor(Color color) {
    return color.computeLuminance() > 0.48 ? Colors.black : Colors.white;
  }

  ColorScheme _paletteScheme(Brightness brightness) {
    final palette = _themeStore.palette;
    final colors = palette.previewColors;
    final primary = colors.first;
    final secondary = colors.length > 1 ? colors[1] : primary;
    final tertiary = colors.length > 2 ? colors[2] : secondary;
    final primaryContainer = colors.length > 3 ? colors[3] : primary;
    final secondaryContainer = colors.length > 4 ? colors[4] : secondary;
    final tertiaryContainer = colors.length > 2 ? colors.last : primary;
    final dark = brightness == Brightness.dark;

    final base = ColorScheme.fromSeed(
      seedColor: dark ? palette.effectiveDarkSeed : palette.lightSeed,
      brightness: brightness,
    );

    return base.copyWith(
      primary: primary,
      onPrimary: _onColor(primary),
      primaryContainer: primaryContainer,
      onPrimaryContainer: _onColor(primaryContainer),
      secondary: secondary,
      onSecondary: _onColor(secondary),
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: _onColor(secondaryContainer),
      tertiary: tertiary,
      onTertiary: _onColor(tertiary),
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: _onColor(tertiaryContainer),
      surface: base.surface,
      onSurface: base.onSurface,
      surfaceContainerHighest: base.surfaceContainerHighest,
      onSurfaceVariant: base.onSurfaceVariant,
      outline: base.outline,
      outlineVariant: base.outlineVariant,
      inversePrimary: primary,
      surfaceTint: Colors.transparent,
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = _paletteScheme(brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        height: 70,
      ),
      dialogTheme: DialogThemeData(backgroundColor: scheme.surface),
      cardTheme: CardThemeData(color: scheme.surface),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _themeStore,
        _accountStore,
      ]),
      builder: (context, _) {
        return MaterialApp(
          title: '冒险者公会',
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: _themeStore.mode,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          home: _WebAccountGate(
            accountStore: _accountStore,
            themeStore: _themeStore,
            featureStore: _featureStore,
          ),
        );
      },
    );
  }
}


class _WebAccountGate extends StatefulWidget {
  const _WebAccountGate({
    required this.accountStore,
    required this.themeStore,
    required this.featureStore,
  });

  final WebAccountStore accountStore;
  final AppThemeStore themeStore;
  final AppFeatureStore featureStore;

  @override
  State<_WebAccountGate> createState() => _WebAccountGateState();
}

class _WebAccountGateState extends State<_WebAccountGate> {
  final WebBackupReader _backupReader = const WebBackupReader();
  final OrderReferenceImageStore _referenceImageStore =
      OrderReferenceImageStore();
  bool _importing = false;

  Future<void> _importAccountBackup() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final imported = await _backupReader.pickAndRead();
      if (imported == null) return;
      final state = imported.backup.accountSyncState;
      if (state == null || !state.hasCredentials) {
        throw const FormatException(
          '这份备份没有完整账号凭据，不能用来在新浏览器登录。',
        );
      }

      final accountId = state.accountId;
      final workspaceKey = 'adventurers-guild.web.workspace.v2.$accountId';

      if (imported.includesAssets) {
        AppBackupData? previousBackup;
        final previousSource = html.window.localStorage[workspaceKey];
        if (previousSource != null && previousSource.trim().isNotEmpty) {
          try {
            previousBackup = AppBackupData.decode(previousSource);
          } catch (_) {
            // A damaged old workspace must not block a valid replacement.
          }
        }

        final importedPaths = <String>{};
        for (final order in imported.backup.orders) {
          for (final image in order.referenceImages) {
            final bytes = imported.assets[image.relativePath];
            if (bytes == null) {
              throw FormatException('完整备份缺少参考图：${image.fileName}');
            }
            await _referenceImageStore.writeAssetBytes(
              accountId: accountId,
              relativePath: image.relativePath,
              bytes: bytes,
            );
            importedPaths.add(image.relativePath);
          }
        }

        if (previousBackup != null) {
          await _referenceImageStore.deleteImages(
            accountId: accountId,
            images: [
              for (final order in previousBackup.orders)
                for (final image in order.referenceImages)
                  if (!importedPaths.contains(image.relativePath)) image,
            ],
          );
        }
      }

      html.window.localStorage[workspaceKey] =
          imported.backup.encode(pretty: false);

      await widget.accountStore.importAccountState(
        state,
        select: true,
        stayLoggedIn: false,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('账号和本地数据已导入，请输入账号密码登录。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导入失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.accountStore.status) {
      WebAccountStatus.loading => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      WebAccountStatus.unlocked => _WebWorkspace(
          accountStore: widget.accountStore,
          themeStore: widget.themeStore,
          featureStore: widget.featureStore,
        ),
      WebAccountStatus.locked => _WebLoginPage(store: widget.accountStore),
      WebAccountStatus.revoked => _WebRevokedPage(store: widget.accountStore),
      WebAccountStatus.unactivated => _WebAccountEntryPage(
          store: widget.accountStore,
          importing: _importing,
          onImportBackup: _importAccountBackup,
        ),
    };
  }
}

class _WebAccountEntryPage extends StatelessWidget {
  const _WebAccountEntryPage({
    required this.store,
    required this.importing,
    required this.onImportBackup,
  });

  final WebAccountStore store;
  final bool importing;
  final Future<void> Function() onImportBackup;

  @override
  Widget build(BuildContext context) {
    final accounts = store.localAccounts;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '冒险者公会',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
            children: [
              Text(
                accounts.isEmpty ? '开始使用网页版' : '选择本机账号',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '网页账号只保存在当前浏览器。已有安卓 / Windows 账号请从客户端完整备份导入，不需要重新使用激活码。',
                style: TextStyle(
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (accounts.isNotEmpty) ...[
                const SizedBox(height: 18),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var index = 0; index < accounts.length; index++) ...[
                        ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline_rounded),
                          ),
                          title: Text(
                            accounts[index].accountName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text('当前浏览器已保存'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () =>
                              store.selectLocalAccount(accounts[index].accountId),
                        ),
                        if (index != accounts.length - 1)
                          const Divider(height: 1, indent: 72),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: importing ? null : onImportBackup,
                icon: importing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_upload_outlined),
                label: Text(importing ? '正在导入…' : '从客户端完整备份导入账号'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: importing
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _WebActivationPage(store: store),
                          ),
                        ),
                icon: const Icon(Icons.key_rounded),
                label: const Text('使用激活码创建新账号'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebActivationPage extends StatefulWidget {
  const _WebActivationPage({required this.store});

  final WebAccountStore store;

  @override
  State<_WebActivationPage> createState() => _WebActivationPageState();
}

class _WebActivationPageState extends State<_WebActivationPage> {
  final TextEditingController _activation = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.activate(
        activationCode: _activation.text,
        accountName: _name.text,
        password: _password.text,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _activation.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('激活新账号')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                controller: _activation,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '激活码',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '账号名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: '密码',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('激活并登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebLoginPage extends StatefulWidget {
  const _WebLoginPage({required this.store});

  final WebAccountStore store;

  @override
  State<_WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<_WebLoginPage> {
  late final TextEditingController _name;
  final TextEditingController _password = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.store.accountName ?? '');
  }

  Future<void> _login() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await widget.store.unlock(
        accountName: _name.text,
        password: _password.text,
      );
      if (!ok && mounted) {
        setState(() => _error = '账号名或密码不正确。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('从这个浏览器移除账号？'),
        content: const Text('会移除当前浏览器里这个账号的登录与工作区记录，不会影响安卓、Windows 或其他设备。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.store.removeSelectedLocalAccount();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '登录',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '账号名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: !_showPassword,
                onSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  labelText: '密码',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _busy ? null : _login,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('登录'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _busy ? null : widget.store.returnToAccountChooser,
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('使用其他账号'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _remove,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('从这个浏览器移除账号'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebRevokedPage extends StatelessWidget {
  const _WebRevokedPage({required this.store});

  final WebAccountStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.phonelink_erase_rounded, size: 52),
                const SizedBox(height: 16),
                Text(
                  '这个网页设备已被解绑',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '当前浏览器里的这个账号不能继续作为已授权设备使用。你可以移除本地记录，再从新的完整备份重新加入。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: store.removeSelectedLocalAccount,
                  child: const Text('移除本地账号'),
                ),
                TextButton(
                  onPressed: store.returnToAccountChooser,
                  child: const Text('返回账号列表'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WebWorkspace extends StatefulWidget {
  const _WebWorkspace({
    required this.accountStore,
    required this.themeStore,
    required this.featureStore,
  });

  final WebAccountStore accountStore;
  final AppThemeStore themeStore;
  final AppFeatureStore featureStore;

  @override
  State<_WebWorkspace> createState() => _WebWorkspaceState();
}

class _WebWorkspaceState extends State<_WebWorkspace> {
  static const String _legacyWorkspaceKey =
      'adventurers-guild.web.workspace.v1';
  static const String _manifestName = 'backup.json';

  final OrderStore _orderStore = OrderStore();
  final ProductStore _productStore = ProductStore();
  final NodePresetStore _nodePresetStore = NodePresetStore();
  final EmptySyncUiCoordinator _syncUi = EmptySyncUiCoordinator();
  final OrderReferenceImageStore _referenceImageStore =
      OrderReferenceImageStore();
  final WebBackupReader _backupReader = const WebBackupReader();

  Timer? _saveDebounce;

  String get _accountId => widget.accountStore.accountId!;
  AccountSyncState get _accountState => widget.accountStore.syncSnapshot!;
  String get _webDeviceId => widget.accountStore.currentDeviceId!;
  String get _workspaceKey =>
      'adventurers-guild.web.workspace.v2.$_accountId';

  bool _ready = false;
  bool _busy = false;
  String _selectedTab = 'orders';
  bool _orderCardView = false;
  bool _productCardView = false;
  String _orderSortMode = 'defaultOrder';
  String _productSortMode = 'defaultOrder';
  bool _desktopNavigationOpen = true;
  bool _nativeDeadlineReminderPreference = false;

  @override
  void initState() {
    super.initState();
    _orderStore.addListener(_scheduleSave);
    _productStore.addListener(_scheduleSave);
    _nodePresetStore.addListener(_scheduleSave);
    widget.featureStore.addListener(_onFeatureStoreChanged);
    widget.themeStore.addListener(_scheduleSave);
    unawaited(_restoreWorkspace());
  }

  void _onFeatureStoreChanged() {
    if (mounted) {
      final allowed = _tabs().map((item) => item.id).toSet();
      if (!allowed.contains(_selectedTab)) _selectedTab = 'orders';
      setState(() {});
    }
    _scheduleSave();
  }

  Future<void> _restoreWorkspace() async {
    try {
      var source = html.window.localStorage[_workspaceKey];
      var migratedLegacy = false;
      if (source == null || source.trim().isEmpty) {
        final legacy = html.window.localStorage[_legacyWorkspaceKey];
        if (legacy != null && legacy.trim().isNotEmpty) {
          final legacyBackup = AppBackupData.decode(legacy);
          final legacyAccountId = legacyBackup.accountSyncState?.accountId;
          if (legacyAccountId == null || legacyAccountId == _accountId) {
            source = legacy;
            migratedLegacy = true;
          }
        }
      }

      if (source != null && source.trim().isNotEmpty) {
        final backup = AppBackupData.decode(source);
        final backupAccount = backup.accountSyncState;
        if (backupAccount != null && backupAccount.accountId != _accountId) {
          throw const FormatException('浏览器本地数据属于另一个账号。');
        }
        if (backupAccount != null) {
          await widget.accountStore.mergeCurrentAccountState(backupAccount);
        }
        backup.restoreInto(
          orderStore: _orderStore,
          productStore: _productStore,
          nodePresetStore: _nodePresetStore,
        );
        await _applySettings(backup.settings);
        if (migratedLegacy) {
          await _persistWorkspace();
          html.window.localStorage.remove(_legacyWorkspaceKey);
        }
      } else {
        await widget.themeStore.resetToDefaults();
        await widget.featureStore.resetToDefaults();
      }
    } catch (error) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('浏览器本地数据读取失败：$error'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        });
      }
    }

    if (mounted) setState(() => _ready = true);
  }

  Map<String, dynamic> _captureSettings() {
    final features = widget.featureStore.toJson();
    return <String, dynamic>{
      'id': 'app',
      'themeMode': widget.themeStore.mode.name,
      'themePaletteId': widget.themeStore.paletteId,
      for (final entry in features.entries)
        'feature.${entry.key}': entry.key == AppFeature.deadlineReminders.name
            ? _nativeDeadlineReminderPreference
            : entry.value,
      'orderCardView': _orderCardView,
      'productCardView': _productCardView,
      'orderSortMode': _orderSortMode,
      'productSortMode': _productSortMode,
      'desktopNavigationOpen': _desktopNavigationOpen,
    };
  }

  Future<void> _applySettings(Map<String, dynamic> settings) async {
    final modeName = settings['themeMode'];
    if (modeName is String) {
      await widget.themeStore.setMode(
        switch (modeName) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
      );
    }

    final paletteId = settings['themePaletteId'];
    if (paletteId is String && AppThemePalettes.containsId(paletteId)) {
      await widget.themeStore.setPaletteId(paletteId);
    }

    final legacyFeatures = settings['features'];
    final nextFeatures = widget.featureStore.toJson();
    if (legacyFeatures is Map) {
      for (final entry in legacyFeatures.entries) {
        if (entry.key is String && entry.value is bool) {
          nextFeatures[entry.key as String] = entry.value as bool;
        }
      }
    }
    for (final feature in AppFeature.values) {
      final value = settings['feature.${feature.name}'];
      if (value is bool) {
        if (feature == AppFeature.deadlineReminders) {
          _nativeDeadlineReminderPreference = value;
        } else {
          nextFeatures[feature.name] = value;
        }
      }
    }
    nextFeatures[AppFeature.deadlineReminders.name] = false;
    await widget.featureStore.applyJson(nextFeatures);

    final orderCard = settings['orderCardView'];
    final productCard = settings['productCardView'];
    final orderSort = settings['orderSortMode'];
    final productSort = settings['productSortMode'];
    final desktopOpen = settings['desktopNavigationOpen'];
    if (orderCard is bool) _orderCardView = orderCard;
    if (productCard is bool) _productCardView = productCard;
    if (orderSort is String &&
        const {'defaultOrder', 'income', 'deadline'}.contains(orderSort)) {
      _orderSortMode = orderSort;
    }
    if (productSort is String &&
        const {'defaultOrder', 'income', 'soldCount'}.contains(productSort)) {
      _productSortMode = productSort;
    }
    if (desktopOpen is bool) _desktopNavigationOpen = desktopOpen;
  }

  AppBackupData _captureLocalBackup({bool portable = false}) {
    final settings = _captureSettings();
    return AppBackupData.capture(
      orderStore: _orderStore,
      productStore: _productStore,
      nodePresetStore: _nodePresetStore,
      accountSyncState: _accountState,
      syncRecords: portable ? _buildPortableRecords(settings) : null,
      settings: settings,
    );
  }

  List<Map<String, dynamic>> _buildPortableRecords(
    Map<String, dynamic> settings,
  ) {
    final accountId = _accountState.accountId;

    Map<String, dynamic> record(
      SyncEntityKind kind,
      String id,
      Map<String, dynamic> values,
    ) {
      return SyncRecord.bootstrap(
        kind: kind,
        id: id,
        values: values,
        deviceId: _webDeviceId,
      ).copyWith(accountId: accountId).toJson();
    }

    return <Map<String, dynamic>>[
      for (final order in _orderStore.orders)
        record(
          SyncEntityKind.order,
          order.id,
          SyncEntityCodec.orderToFields(order),
        ),
      for (final product in _productStore.products)
        record(
          SyncEntityKind.product,
          product.id,
          SyncEntityCodec.productToFields(product),
        ),
      for (final preset in _nodePresetStore.presets)
        record(
          SyncEntityKind.nodePreset,
          preset.id,
          SyncEntityCodec.nodePresetToFields(preset),
        ),
      record(SyncEntityKind.settings, 'app', settings),
    ];
  }

  void _scheduleSave() {
    if (!_ready) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), _persistWorkspace);
  }

  Future<void> _persistWorkspace() async {
    try {
      html.window.localStorage[_workspaceKey] =
          _captureLocalBackup().encode(pretty: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('浏览器本地保存失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<_WebTab> _tabs() {
    return <_WebTab>[
      const _WebTab('orders', '排单', Icons.assignment_outlined),
      if (widget.featureStore.products)
        const _WebTab('products', '成品', Icons.image_outlined),
      if (widget.featureStore.schedule)
        const _WebTab('schedule', '日程', Icons.calendar_month_outlined),
      if (widget.featureStore.statistics)
        const _WebTab('statistics', '统计', Icons.bar_chart_rounded),
    ];
  }

  Widget _tabBody(String id) {
    return switch (id) {
      'products' => ProductPage(
          store: _productStore,
          featureStore: widget.featureStore,
          syncCoordinator: _syncUi,
          cardView: _productCardView,
          onCardViewChanged: (value) {
            setState(() => _productCardView = value);
            _scheduleSave();
          },
          sortModeName: _productSortMode,
          onSortModeChanged: (value) {
            setState(() => _productSortMode = value);
            _scheduleSave();
          },
        ),
      'schedule' => SchedulePage(
          accountId: _accountId,
          store: _orderStore,
          productStore: _productStore,
          nodePresetStore: _nodePresetStore,
          featureStore: widget.featureStore,
        ),
      'statistics' => StatisticsPage(
          store: _orderStore,
          productStore: _productStore,
        ),
      _ => OrderQueuePage(
          accountId: _accountId,
          store: _orderStore,
          nodePresetStore: _nodePresetStore,
          featureStore: widget.featureStore,
          syncCoordinator: _syncUi,
          cardView: _orderCardView,
          onCardViewChanged: (value) {
            setState(() => _orderCardView = value);
            _scheduleSave();
          },
          sortModeName: _orderSortMode,
          onSortModeChanged: (value) {
            setState(() => _orderSortMode = value);
            _scheduleSave();
          },
        ),
    };
  }

  void _openAdd() {
    if (_selectedTab == 'products') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AddProductPage(
            store: _productStore,
            featureStore: widget.featureStore,
          ),
        ),
      );
      return;
    }
    if (_selectedTab == 'orders') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AddOrderPage(
            accountId: _accountId,
            store: _orderStore,
            nodePresetStore: _nodePresetStore,
            featureStore: widget.featureStore,
          ),
        ),
      );
    }
  }

  void _openTool(BuildContext drawerContext, Widget page) {
    final navigator = Navigator.of(drawerContext);
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _exportBackup(BuildContext context) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final backup = _captureLocalBackup(portable: true);
      final archive = Archive();
      final manifest = utf8.encode(backup.encode());
      archive.addFile(
        ArchiveFile(_manifestName, manifest.length, manifest),
      );

      for (final order in backup.orders) {
        for (final image in order.referenceImages) {
          final bytes = await _referenceImageStore.readAssetBytes(
            accountId: _accountId,
            relativePath: image.relativePath,
          );
          if (bytes == null) {
            throw StateError('参考图“${image.fileName}”原文件缺失，无法生成完整备份。');
          }
          if (bytes.length != image.sizeBytes) {
            throw StateError('参考图“${image.fileName}”文件大小与记录不一致。');
          }
          archive.addFile(
            ArchiveFile(image.relativePath, bytes.length, bytes),
          );
        }
      }

      final encoded = ZipEncoder().encode(archive);
      final bytes = Uint8List.fromList(encoded);
      _downloadBytes(
        fileName: _backupFileName(DateTime.now()),
        bytes: bytes,
        mimeType: 'application/zip',
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '完整备份已导出，可在安卓或电脑端“设置 → 导入完整备份”中手动同步。',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导出失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    if (_busy) return;

    final imported = await _backupReader.pickAndRead();
    if (imported == null) return;

    setState(() => _busy = true);
    try {
      final backup = imported.backup;
      final backupAccount = backup.accountSyncState;
      if (backupAccount != null && backupAccount.accountId != _accountId) {
        throw FormatException(
          '这份备份属于账号“${backupAccount.accountName}”，'
          '不能覆盖当前账号“${widget.accountStore.accountName}”。',
        );
      }
      final accountName =
          backupAccount?.accountName ?? widget.accountStore.accountName;

      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('导入并替换当前数据？'),
          content: Text(
            '排单 ${backup.orders.length} 条 · 成品 ${backup.products.length} 条 · '
            '节点预设 ${backup.nodePresets.length} 个\n'
            '账号：${accountName ?? '当前账号'}\n'
            '备份时间：${_formatDateTime(backup.exportedAt.toLocal())}\n\n'
            '导入后会用这份备份替换当前账号的网页版工作区。'
            '${imported.includesAssets ? '' : '\n这份文件不含参考图原文件，已有参考图可能显示为缺失。'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('导入'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      if (imported.includesAssets) {
        final importedPaths = <String>{};
        for (final order in backup.orders) {
          for (final image in order.referenceImages) {
            final bytes = imported.assets[image.relativePath];
            if (bytes == null) {
              throw FormatException('完整备份缺少参考图：${image.fileName}');
            }
            await _referenceImageStore.writeAssetBytes(
              accountId: _accountId,
              relativePath: image.relativePath,
              bytes: bytes,
            );
            importedPaths.add(image.relativePath);
          }
        }
        await _referenceImageStore.deleteImages(
          accountId: _accountId,
          images: [
            for (final order in _orderStore.orders)
              for (final image in order.referenceImages)
                if (!importedPaths.contains(image.relativePath)) image,
          ],
        );
      }

      if (backupAccount != null) {
        await widget.accountStore.mergeCurrentAccountState(backupAccount);
      }
      backup.restoreInto(
        orderStore: _orderStore,
        productStore: _productStore,
        nodePresetStore: _nodePresetStore,
      );
      await _applySettings(backup.settings);
      await _persistWorkspace();

      if (!context.mounted) return;
      setState(() => _selectedTab = 'orders');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('导入完成，当前账号的网页版工作区已经替换。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导入失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _downloadBytes({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) {
    final blob = html.Blob(<Object>[bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = fileName
      ..style.display = 'none';
    html.document.body?.append(anchor);
    try {
      anchor.click();
    } finally {
      anchor.remove();
      html.Url.revokeObjectUrl(url);
    }
  }

  String _backupFileName(DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '冒险者公会-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}.zip';
  }

  String _formatDateTime(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _orderStore.removeListener(_scheduleSave);
    _productStore.removeListener(_scheduleSave);
    _nodePresetStore.removeListener(_scheduleSave);
    widget.featureStore.removeListener(_onFeatureStoreChanged);
    widget.themeStore.removeListener(_scheduleSave);
    _syncUi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final tabs = _tabs();
    if (!tabs.any((tab) => tab.id == _selectedTab)) {
      _selectedTab = 'orders';
    }
    final selectedIndex = tabs.indexWhere((tab) => tab.id == _selectedTab);
    final selected = tabs[selectedIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          selected.label,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: '手动同步 / 备份',
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _WebDataPage(
                          linkedAccountName: _accountState.accountName,
                          busy: () => _busy,
                          onExport: _exportBackup,
                          onImport: _importBackup,
                        ),
                      ),
                    ),
            icon: const Icon(Icons.sync_alt_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '冒险者公会',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '网页版 · 本地优先',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(
                  widget.accountStore.accountName ?? '当前账号',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('网页本地账号'),
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('退出登录'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _persistWorkspace();
                  await widget.accountStore.lock();
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('归档'),
                onTap: () => _openTool(
                  context,
                  ArchivePage(
                    accountId: _accountId,
                    orderStore: _orderStore,
                    productStore: _productStore,
                    nodePresetStore: _nodePresetStore,
                    featureStore: widget.featureStore,
                    syncCoordinator: _syncUi,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: const Text('节点预设'),
                onTap: () => _openTool(
                  context,
                  NodePresetPage(store: _nodePresetStore),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('附加功能开关'),
                onTap: () => _openTool(
                  context,
                  FeatureTogglePage(store: widget.featureStore),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.auto_awesome_outlined),
                title: const Text('抽象版'),
                subtitle: const Text('切换普通版与抽象版'),
                value: widget.featureStore.abstractMode,
                onChanged: (value) =>
                    widget.featureStore.setEnabled(AppFeature.abstractMode, value),
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('UI主题色'),
                onTap: () => _openTool(
                  context,
                  ThemeColorPage(store: widget.themeStore),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.sync_alt_rounded),
                title: const Text('手动同步 / 备份'),
                subtitle: const Text('导入、导出完整备份'),
                onTap: () => _openTool(
                  context,
                  _WebDataPage(
                    linkedAccountName: _accountState.accountName,
                    busy: () => _busy,
                    onExport: _exportBackup,
                    onImport: _importBackup,
                  ),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                child: Text(
                  '网页版不连接 Syncthing。数据默认只保存在这个浏览器里；'
                  '要与安卓 / Windows 同步时，用“完整备份”手动导入导出。',
                  style: TextStyle(
                    height: 1.45,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _tabBody(_selectedTab)),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context)
                    .colorScheme
                    .scrim
                    .withValues(alpha: 0.08),
                child: const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 18,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                          SizedBox(width: 14),
                          Text('正在处理备份…'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _selectedTab == 'orders' ||
              _selectedTab == 'products'
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _openAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(_selectedTab == 'orders' ? '新增排单' : '新增成品'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedTab = tabs[index].id);
        },
        destinations: [
          for (final tab in tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}

class _WebDataPage extends StatelessWidget {
  const _WebDataPage({
    required this.linkedAccountName,
    required this.busy,
    required this.onExport,
    required this.onImport,
  });

  final String? linkedAccountName;
  final bool Function() busy;
  final Future<void> Function(BuildContext context) onExport;
  final Future<void> Function(BuildContext context) onImport;

  @override
  Widget build(BuildContext context) {
    final linked = linkedAccountName != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '手动同步 / 备份',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    linked
                        ? Icons.verified_user_outlined
                        : Icons.info_outline_rounded,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      linked
                          ? '当前网页工作区来自账号“$linkedAccountName”。导出的完整备份可回到安卓或 Windows 客户端导入。'
                          : '当前是独立网页版工作区。若要和安卓 / Windows 手动同步，建议先在客户端导出完整备份，再导入这里。',
                      style: const TextStyle(height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text(
                    '导出完整备份',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('排单、成品、节点、设置和参考图会一起打包成 .zip'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: busy() ? null : () => onExport(context),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text(
                    '导入完整备份',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('支持客户端导出的 .zip，也兼容旧版 .json'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: busy() ? null : () => onImport(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            margin: EdgeInsets.zero,
            child: const ListTile(
              leading: Icon(Icons.ios_share_rounded),
              title: Text(
                'iPhone / iPad 可以添加到主屏幕',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('用 Safari 打开网页 → 点“分享” → “添加到主屏幕”，之后就能像普通 App 一样从桌面进入。'),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '网页版没有后台 P2P，同步动作只发生在你主动导入或导出时。'
            '网页本地数据使用浏览器存储；清除站点数据前请先导出备份。',
            style: TextStyle(
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _WebTab {
  const _WebTab(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}
