import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'issuer_secret_bridge.dart';
import 'license_issuer_api.dart';
import 'license_issuer_engine.dart';
import 'license_issuer_models.dart';
import 'license_issuer_store.dart';

class LicenseIssuerApp extends StatefulWidget {
  const LicenseIssuerApp({super.key});

  @override
  State<LicenseIssuerApp> createState() => _LicenseIssuerAppState();
}

class _LicenseIssuerAppState extends State<LicenseIssuerApp> {
  final LicenseIssuerStore _store = LicenseIssuerStore();
  final IssuerSecretBridge _secretBridge = const IssuerSecretBridge();
  final LicenseIssuerEngine _engine = const LicenseIssuerEngine();

  bool _loading = true;
  String? _privateKey;
  String? _keyError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _store.load();
    try {
      if (await _secretBridge.hasPrivateKey()) {
        final source = await _secretBridge.readPrivateKey();
        if (source != null && source.trim().isNotEmpty) {
          await _engine.validatePrivateKey(source);
          _privateKey = source;
          _keyError = null;
        }
      }
    } catch (error) {
      _keyError = '已保存的私钥不可用：$error';
      await _secretBridge.clearPrivateKey();
      _privateKey = null;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _importPrivateKey() async {
    try {
      final source = await _secretBridge.importPrivateKey();
      if (source == null || source.trim().isEmpty) return;

      await _engine.validatePrivateKey(source);
      await _secretBridge.storePrivateKey(source);

      if (!mounted) return;
      setState(() {
        _privateKey = source;
        _keyError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('私钥已验证并安全保存到本机')),
      );
    } catch (error, stackTrace) {
      debugPrint('License issuer private key import failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;
      final friendlyError = _friendlyKeyImportError(error);
      final hasExistingValidKey = _privateKey != null;

      setState(() {
        _keyError = hasExistingValidKey ? null : friendlyError;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasExistingValidKey
                ? '重新导入失败，已继续使用原来的有效私钥。'
                : '导入失败：$friendlyError',
          ),
        ),
      );
    }
  }

  Future<void> _clearPrivateKey() async {
    await _secretBridge.clearPrivateKey();
    final stillStored = await _secretBridge.hasPrivateKey();
    if (stillStored) {
      throw PlatformException(
        code: 'PRIVATE_KEY_CLEAR_FAILED',
        message: '系统安全存储仍报告私钥存在。',
      );
    }
    if (mounted) {
      setState(() {
        _privateKey = null;
        _keyError = null;
      });
    }
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF9AA66A),
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '激活码生成器',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF7F8F0),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7F8F0),
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: _loading
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : _IssuerHomePage(
              store: _store,
              secretBridge: _secretBridge,
              privateKey: _privateKey,
              keyError: _keyError,
              onImportPrivateKey: _importPrivateKey,
              onClearPrivateKey: _clearPrivateKey,
            ),
    );
  }
}

enum _IssuerFilter { all, unused, sold, redeemed }

class _IssuerHomePage extends StatefulWidget {
  const _IssuerHomePage({
    required this.store,
    required this.secretBridge,
    required this.privateKey,
    required this.keyError,
    required this.onImportPrivateKey,
    required this.onClearPrivateKey,
  });

  final LicenseIssuerStore store;
  final IssuerSecretBridge secretBridge;
  final String? privateKey;
  final String? keyError;
  final Future<void> Function() onImportPrivateKey;
  final Future<void> Function() onClearPrivateKey;

  @override
  State<_IssuerHomePage> createState() => _IssuerHomePageState();
}

class _IssuerHomePageState extends State<_IssuerHomePage> {
  final _noteController = TextEditingController();
  bool _busy = false;
  bool _adminBusy = true;
  String? _adminError;
  _IssuerFilter _filter = _IssuerFilter.all;
  bool _selectingForDelete = false;
  final Set<String> _selectedForDelete = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_restoreAdminSession(promptIfMissing: true));
  }

  Future<void> _restoreAdminSession({bool promptIfMissing = false}) async {
    if (!widget.store.serverConfigured) {
      if (mounted) {
        setState(() {
          _adminBusy = false;
          _adminError = '当前构建还没有配置激活服务器地址。';
        });
      }
      return;
    }

    try {
      final hasToken = await widget.secretBridge.hasAdminToken();
      if (!hasToken) {
        if (mounted) {
          setState(() {
            _adminBusy = false;
            _adminError = null;
          });
          if (promptIfMissing) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !widget.store.isConnected) {
                _registerAdmin(required: true);
              }
            });
          }
        }
        return;
      }

      final token = await widget.secretBridge.readAdminToken();
      if (token == null || token.trim().isEmpty) {
        await widget.secretBridge.clearAdminToken();
        if (mounted) {
          setState(() {
            _adminBusy = false;
            _adminError = null;
          });
        }
        return;
      }

      await widget.store.connectAdmin(token);
      if (mounted) {
        setState(() {
          _adminBusy = false;
          _adminError = null;
        });
      }
    } on IssuerApiException catch (error) {
      if (error.isUnauthorized) {
        await widget.secretBridge.clearAdminToken();
      }
      if (mounted) {
        setState(() {
          _adminBusy = false;
          _adminError = error.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _adminBusy = false;
          _adminError = error.toString();
        });
      }
    }
  }

  Future<void> _registerAdmin({bool required = false}) async {
    if (_adminBusy || !widget.store.serverConfigured) return;

    final nameController =
        TextEditingController(text: widget.store.adminName);
    final setupKeyController = TextEditingController();
    var canSave = nameController.text.trim().isNotEmpty;

    final result = await showDialog<(String, String)>(
      context: context,
      barrierDismissible: !required,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('连接发码管理'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                maxLength: 24,
                textInputAction: TextInputAction.next,
                onChanged: (value) {
                  setDialogState(() => canSave = value.trim().isNotEmpty);
                },
                decoration: const InputDecoration(
                  labelText: '管理昵称',
                  hintText: '例如：小雪 / 阿竹',
                  helperText: '服务器会记录谁生成、谁售出了激活码',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: setupKeyController,
                obscureText: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: '管理接入密钥',
                  helperText: '只在这台发码器首次加入时填写',
                  prefixIcon: Icon(Icons.key_outlined),
                ),
              ),
            ],
          ),
          actions: [
            if (!required)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
            FilledButton(
              onPressed: canSave
                  ? () => Navigator.of(dialogContext).pop((
                        nameController.text,
                        setupKeyController.text,
                      ))
                  : null,
              child: const Text('连接'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    setupKeyController.dispose();
    if (result == null) return;

    setState(() => _adminBusy = true);
    try {
      final session = await widget.store.registerAdmin(
        setupKey: result.$2,
        name: result.$1,
      );
      final token = session.token;
      if (token == null || token.isEmpty) {
        throw const IssuerApiException('服务器没有返回管理员凭据。');
      }
      await widget.secretBridge.storeAdminToken(token);
      await widget.store.connectAdmin(token);
      if (!mounted) return;
      setState(() {
        _adminBusy = false;
        _adminError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已连接为 ${widget.store.adminName}')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _adminBusy = false;
        _adminError = error.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('连接失败：$error')),
      );
    }
  }

  Future<void> _reconnectAdmin() async {
    if (_adminBusy) return;
    setState(() => _adminBusy = true);
    await _restoreAdminSession(promptIfMissing: false);
    if (!mounted) return;
    if (!widget.store.isConnected && _adminError == null) {
      await _registerAdmin();
    }
  }

  Future<void> _refreshRecords() async {
    if (_adminBusy || !widget.store.isConnected) return;
    setState(() => _adminBusy = true);
    try {
      await widget.store.refresh();
      if (!mounted) return;
      setState(() {
        _adminBusy = false;
        _adminError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _adminBusy = false;
        _adminError = error.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刷新失败：$error')),
      );
    }
  }

  Future<void> _editAdminName({bool required = false}) async {
    if (!widget.store.isConnected) {
      await _reconnectAdmin();
      return;
    }

    final controller = TextEditingController(text: widget.store.adminName);
    var canSave = controller.text.trim().isNotEmpty;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: !required,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('修改管理昵称'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 24,
            textInputAction: TextInputAction.done,
            onChanged: (value) {
              setDialogState(() => canSave = value.trim().isNotEmpty);
            },
            onSubmitted: canSave
                ? (_) => Navigator.of(dialogContext).pop(controller.text)
                : null,
            decoration: const InputDecoration(
              labelText: '管理昵称',
              helperText: '之后的新操作会显示这个名字',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          actions: [
            if (!required)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
            FilledButton(
              onPressed: canSave
                  ? () => Navigator.of(dialogContext).pop(controller.text)
                  : null,
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;

    try {
      await widget.store.renameAdmin(result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('当前管理者：${widget.store.adminName}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存管理昵称失败：$error')),
      );
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _issueOne() async {
    final key = widget.privateKey;
    if (key == null || _busy) return;

    setState(() => _busy = true);
    try {
      final record = await widget.store.issueOne(
        privateKeySource: key,
        note: _noteController.text,
      );
      _noteController.clear();
      await Clipboard.setData(
        ClipboardData(text: record.activationCode),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '编号 ${_displaySerial(record.serial)} 的完整激活码已生成并复制',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _issueBatch() async {
    final key = widget.privateKey;
    if (key == null || _busy) return;

    final count = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('批量生成'),
        children: [
          for (final value in const [10, 50, 100])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(value),
              child: Text('生成 $value 枚'),
            ),
        ],
      ),
    );
    if (count == null) return;

    setState(() => _busy = true);
    try {
      await widget.store.issueBatch(
        privateKeySource: key,
        count: count,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已生成 $count 枚激活码')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('批量生成失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCsv() async {
    if (widget.store.records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有可导出的记录')),
      );
      return;
    }

    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final fileName =
        'activation-codes-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}.csv';

    final saved = await widget.secretBridge.exportText(
      fileName: fileName,
      content: widget.store.exportCsv(),
      mimeType: 'text/csv',
    );
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('发码记录已导出')),
      );
    }
  }

  Future<void> _editNote(IssuedLicenseRecord record) async {
    final controller = TextEditingController(text: record.note);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('备注 · 编号 ${_displaySerial(record.serial)}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '例如：买家昵称 / 订单号',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) {
      await widget.store.updateNote(record.accountId, result);
    }
  }

  Future<void> _deleteRecord(IssuedLicenseRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: Text(
          '编号 ${_displaySerial(record.serial)} 会从服务器账本中作废并隐藏。'
          '已核销的激活码不能直接删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除记录'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.store.delete(record.accountId);
    }
  }

  void _startBatchDelete() {
    setState(() {
      _selectingForDelete = true;
      _selectedForDelete.clear();
    });
  }

  void _cancelBatchDelete() {
    setState(() {
      _selectingForDelete = false;
      _selectedForDelete.clear();
    });
  }

  void _toggleDeleteSelection(String accountId) {
    setState(() {
      if (!_selectedForDelete.add(accountId)) {
        _selectedForDelete.remove(accountId);
      }
    });
  }

  void _selectAllForDelete(List<IssuedLicenseRecord> records) {
    setState(() {
      _selectedForDelete.addAll(records.map((item) => item.accountId));
    });
  }

  Future<void> _deleteSelectedRecords() async {
    final count = _selectedForDelete.length;
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除选中的 $count 条记录？'),
        content: const Text(
          '选中的未核销记录会在服务器账本中作废；已核销记录不能直接删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('批量删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final deleted = await widget.store.deleteMany(_selectedForDelete);
    if (!mounted) return;
    setState(() {
      _selectingForDelete = false;
      _selectedForDelete.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除 $deleted 条发码记录')),
    );
  }

  Future<void> _confirmClearPrivateKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移除本机私钥？'),
        content: const Text(
          '历史发码记录不会删除，但移除后不能继续生成激活码，除非重新导入私钥文件。',
        ),
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
    if (confirmed != true) return;

    try {
      await widget.onClearPrivateKey();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本机私钥已移除')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('移除私钥失败：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = widget.privateKey != null;

    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final all = widget.store.records;
        final hasAdmin = widget.store.isConnected;
        final records = switch (_filter) {
          _IssuerFilter.all => all,
          _IssuerFilter.unused => all
              .where((item) => !item.isSold && !item.isRedeemed)
              .toList(),
          _IssuerFilter.sold => all
              .where((item) => item.isSold && !item.isRedeemed)
              .toList(),
          _IssuerFilter.redeemed =>
            all.where((item) => item.isRedeemed).toList(),
        };

        return Scaffold(
          appBar: AppBar(
            title: Text(
              _selectingForDelete
                  ? '批量删除 · 已选 ${_selectedForDelete.length}'
                  : '激活码生成器',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            actions: _selectingForDelete
                ? [
                    IconButton(
                      tooltip: '全选当前',
                      onPressed: records.isEmpty
                          ? null
                          : () => _selectAllForDelete(records),
                      icon: const Icon(Icons.select_all_rounded),
                    ),
                    IconButton(
                      tooltip: '删除已选',
                      onPressed: _selectedForDelete.isEmpty
                          ? null
                          : _deleteSelectedRecords,
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                    IconButton(
                      tooltip: '取消',
                      onPressed: _cancelBatchDelete,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ]
                : [
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'batch') _issueBatch();
                        if (value == 'admin') _editAdminName();
                        if (value == 'refresh') _refreshRecords();
                        if (value == 'delete_batch') _startBatchDelete();
                        if (value == 'export') _exportCsv();
                        if (value == 'key') widget.onImportPrivateKey();
                        if (value == 'clear') _confirmClearPrivateKey();
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'admin',
                          child: Text('修改管理昵称'),
                        ),
                        if (hasAdmin)
                          const PopupMenuItem(
                            value: 'refresh',
                            child: Text('刷新服务器记录'),
                          ),
                        if (hasKey && hasAdmin)
                          const PopupMenuItem(
                            value: 'batch',
                            child: Text('批量生成'),
                          ),
                        if (all.isNotEmpty)
                          const PopupMenuItem(
                            value: 'delete_batch',
                            child: Text('批量删除'),
                          ),
                        const PopupMenuItem(
                          value: 'export',
                          child: Text('导出 CSV'),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'key',
                          child: Text(hasKey ? '重新导入私钥' : '导入私钥'),
                        ),
                        if (hasKey)
                          const PopupMenuItem(
                            value: 'clear',
                            child: Text('移除本机私钥'),
                          ),
                      ],
                    ),
                  ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              _KeyStatusCard(
                hasKey: hasKey,
                error: hasKey ? null : widget.keyError,
                onImport: widget.onImportPrivateKey,
              ),
              const SizedBox(height: 10),
              _AdminIdentityCard(
                adminName: widget.store.adminName,
                connected: widget.store.isConnected,
                serverConfigured: widget.store.serverConfigured,
                busy: _adminBusy,
                error: _adminError,
                onEdit: _editAdminName,
                onConnect: widget.store.isConnected
                    ? _refreshRecords
                    : _reconnectAdmin,
              ),
              const SizedBox(height: 14),
              _GenerateCard(
                enabled: hasKey && hasAdmin && !_busy,
                busy: _busy,
                noteController: _noteController,
                onGenerate: _issueOne,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    '发码记录',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const Spacer(),
                  Text('${all.length} 枚'),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<_IssuerFilter>(
                segments: const [
                  ButtonSegment(
                    value: _IssuerFilter.all,
                    label: Text('全部'),
                  ),
                  ButtonSegment(
                    value: _IssuerFilter.unused,
                    label: Text('未售'),
                  ),
                  ButtonSegment(
                    value: _IssuerFilter.sold,
                    label: Text('已售'),
                  ),
                  ButtonSegment(
                    value: _IssuerFilter.redeemed,
                    label: Text('已核销'),
                  ),
                ],
                selected: <_IssuerFilter>{_filter},
                onSelectionChanged: (value) {
                  setState(() => _filter = value.first);
                },
              ),
              const SizedBox(height: 10),
              if (_selectingForDelete) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '点记录勾选；右上角可一键全选当前筛选结果。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (records.isEmpty)
                const _EmptyHistory()
              else
                for (final record in records)
                  _HistoryCard(
                    record: record,
                    onCopy: () async {
                      await Clipboard.setData(
                        ClipboardData(text: record.activationCode),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '编号 ${_displaySerial(record.serial)} 的完整激活码已复制',
                          ),
                        ),
                      );
                    },
                    onToggleSold: () async {
                      try {
                        await widget.store.setSold(
                          record.accountId,
                          !record.isSold,
                        );
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('更新售出状态失败：$error')),
                        );
                      }
                    },
                    onEditNote: () => _editNote(record),
                    onDelete: () => _deleteRecord(record),
                    selectionMode: _selectingForDelete,
                    selected: _selectedForDelete.contains(record.accountId),
                    onSelect: () => _toggleDeleteSelection(record.accountId),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _KeyStatusCard extends StatelessWidget {
  const _KeyStatusCard({
    required this.hasKey,
    required this.error,
    required this.onImport,
  });

  final bool hasKey;
  final String? error;
  final Future<void> Function() onImport;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: hasKey
          ? colors.primaryContainer.withValues(alpha: 0.55)
          : colors.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              hasKey
                  ? Icons.verified_user_rounded
                  : Icons.key_off_outlined,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasKey ? '签名私钥已就绪' : '还没有导入签名私钥',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasKey
                        ? '私钥只保存在这台设备的 Android Keystore 加密存储中。'
                        : '首次使用时导入私钥 .txt 文件，之后无需重复选择。',
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      error!,
                      style: TextStyle(color: colors.error),
                    ),
                  ],
                  if (!hasKey) ...[
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: onImport,
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('导入私钥文件'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminIdentityCard extends StatelessWidget {
  const _AdminIdentityCard({
    required this.adminName,
    required this.connected,
    required this.serverConfigured,
    required this.busy,
    required this.error,
    required this.onEdit,
    required this.onConnect,
  });

  final String adminName;
  final bool connected;
  final bool serverConfigured;
  final bool busy;
  final String? error;
  final Future<void> Function({bool required}) onEdit;
  final Future<void> Function() onConnect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = connected
        ? '当前管理者：${adminName.isEmpty ? '未命名' : adminName}'
        : serverConfigured
            ? '发码服务器未连接'
            : '当前构建未配置发码服务器';
    final description = connected
        ? '生成、售出和核销状态来自服务器共同账本。'
        : error ??
            (serverConfigured
                ? '连接后才能生成或修改激活码；离线时仍可查看本地缓存。'
                : '配置服务器地址后，这里会连接多人共享账本。');

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              connected
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: TextStyle(
                      color: error == null
                          ? colors.onSurfaceVariant
                          : colors.error,
                    ),
                  ),
                  if (serverConfigured) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: busy ? null : () => onConnect(),
                          icon: busy
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  connected
                                      ? Icons.refresh_rounded
                                      : Icons.login_rounded,
                                ),
                          label: Text(connected ? '刷新' : '连接'),
                        ),
                        if (connected)
                          TextButton.icon(
                            onPressed: busy ? null : () => onEdit(),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('改名'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenerateCard extends StatelessWidget {
  const _GenerateCard({
    required this.enabled,
    required this.busy,
    required this.noteController,
    required this.onGenerate,
  });

  final bool enabled;
  final bool busy;
  final TextEditingController noteController;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '生成新激活码',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: '备注（可选）',
                hintText: '例如：买家昵称 / 订单号',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: enabled ? onGenerate : null,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_circle_outline_rounded),
                label: Text(busy ? '正在生成…' : '生成并复制激活码'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.record,
    required this.onCopy,
    required this.onToggleSold,
    required this.onEditNote,
    required this.onDelete,
    required this.selectionMode,
    required this.selected,
    required this.onSelect,
  });

  final IssuedLicenseRecord record;
  final VoidCallback onCopy;
  final VoidCallback onToggleSold;
  final VoidCallback onEditNote;
  final VoidCallback onDelete;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: selected
          ? colors.secondaryContainer.withValues(alpha: 0.45)
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: InkWell(
                onTap: selectionMode ? onSelect : onCopy,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '编号 ${_displaySerial(record.serial)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: record.isRedeemed
                                ? colors.tertiaryContainer
                                : record.isSold
                                    ? colors.secondaryContainer
                                    : colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            child: Text(
                              record.isRedeemed
                                  ? '已核销'
                                  : record.isSold
                                      ? '已售出'
                                      : record.isLegacyCode
                                          ? '旧版码'
                                          : '未售出',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _actorSummary(record),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      record.note.isEmpty ? '无备注' : record.note,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '激活码：${_activationCodePreview(record.activationCode)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '生成：${_formatTime(record.createdAt.toLocal())}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                    if (record.redeemedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '核销：${_formatTime(record.redeemedAt!.toLocal())}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (selectionMode)
              Checkbox(
                value: selected,
                onChanged: (_) => onSelect(),
              )
            else
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'copy') onCopy();
                  if (value == 'sold') onToggleSold();
                  if (value == 'note') onEditNote();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'copy',
                    child: Text('复制激活码'),
                  ),
                  PopupMenuItem(
                    value: 'sold',
                    enabled: !record.isLegacyCode || record.isSold,
                    child: Text(
                      record.isSold
                          ? '恢复为未售出'
                          : record.isLegacyCode
                              ? '旧版码不可新售'
                              : '标记已售出',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'note',
                    child: Text('修改备注'),
                  ),
                  if (!record.isRedeemed) ...[
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('删除记录'),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Column(
        children: [
          Icon(
            Icons.confirmation_number_outlined,
            size: 44,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 10),
          Text(
            '这里还没有激活码记录',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _displaySerial(String serial) {
  final match = RegExp(r'^AW-(\d{6})$').firstMatch(serial.trim());
  return match?.group(1) ?? serial.trim();
}

String _actorSummary(IssuedLicenseRecord record) {
  final generatedBy =
      record.generatedBy.trim().isEmpty ? '旧记录' : record.generatedBy.trim();
  if (!record.isSold) return '$generatedBy生成 · 未售出';
  final soldBy = record.soldBy?.trim();
  return '$generatedBy生成 · ${soldBy == null || soldBy.isEmpty ? '未记录' : soldBy}售出';
}

String _activationCodePreview(String code) {
  final value = code.trim();
  if (value.length <= 42) return value;
  return '${value.substring(0, 24)}…${value.substring(value.length - 10)}';
}

String _formatTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

String _friendlyKeyImportError(Object error) {
  if (error is FormatException) {
    return error.message;
  }
  if (error is PlatformException) {
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) return message;
    return '系统安全存储返回异常，请重试。';
  }
  final text = error.toString().trim();
  if (text.isEmpty || text == 'Null check operator used on a null value') {
    return '私钥导入流程异常，请重试；若仍失败请重新安装最新版发码器。';
  }
  return text;
}
