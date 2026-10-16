import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_palette.dart';
import '../../../core/theme/app_theme_store.dart';
import '../../shared/presentation/layout_spacing.dart';
import 'theme_color_picker.dart';

class CustomThemeColorPage extends StatefulWidget {
  const CustomThemeColorPage({
    required this.store,
    this.palette,
    super.key,
  });

  final AppThemeStore store;
  final AppThemePalette? palette;

  @override
  State<CustomThemeColorPage> createState() => _CustomThemeColorPageState();
}

class _CustomThemeColorPageState extends State<CustomThemeColorPage> {
  late String _name;
  String? _editingId;
  late bool _advanced;
  late Color _seed;
  late AppThemeSemanticColors _light;
  late AppThemeSemanticColors _dark;
  Brightness _editingBrightness = Brightness.light;

  late final String _initialName;
  late final bool _initialAdvanced;
  late final Color _initialSeed;
  late final AppThemeSemanticColors _initialLight;
  late final AppThemeSemanticColors _initialDark;

  AppThemeSemanticColors get _editingColors =>
      _editingBrightness == Brightness.light ? _light : _dark;

  @override
  void initState() {
    super.initState();
    final source = widget.palette ?? widget.store.palette;
    _name = source.isCustom ? source.name : '我的配色';
    _editingId = source.isCustom ? source.id : null;
    _advanced = source.isCustom && source.customAdvanced;
    _seed = source.lightSeed;
    _light = source.lightSemanticColors ??
        AppThemeSemanticColors.fromSeed(_seed, Brightness.light);
    _dark = source.darkSemanticColors ??
        AppThemeSemanticColors.fromSeed(
          source.effectiveDarkSeed,
          Brightness.dark,
        );

    _initialName = _name;
    _initialAdvanced = _advanced;
    _initialSeed = _seed;
    _initialLight = _light;
    _initialDark = _dark;
  }

  @override
  Widget build(BuildContext context) {
    final colors = _advanced
        ? _editingColors
        : AppThemeSemanticColors.fromSeed(_seed, _editingBrightness);

    return Scaffold(
      appBar: AppBar(
        title: Text(_editingId == null ? '自定义调色' : '编辑配色'),
        actions: [
          if (_editingId != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'copy') {
                  _save(copy: true);
                } else if (value == 'delete') {
                  _delete();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'copy',
                  child: Text('另存为新方案'),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('删除这个方案'),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: AppLayoutSpacing.pageScrollPadding(
          context,
          left: 16,
          top: 10,
          right: 16,
        ),
        children: [
          _PaletteLivePreview(colors: colors),
          const SizedBox(height: 14),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text(
              '方案名称',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(_name),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _rename,
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: false,
                icon: Icon(Icons.auto_awesome_outlined),
                label: Text('基础'),
              ),
              ButtonSegment<bool>(
                value: true,
                icon: Icon(Icons.tune_rounded),
                label: Text('高级'),
              ),
            ],
            selected: <bool>{_advanced},
            onSelectionChanged: (value) {
              setState(() => _advanced = value.first);
            },
          ),
          const SizedBox(height: 12),
          if (!_advanced) ...[
            _ColorSettingTile(
              title: '主主题色',
              description: '按钮、选中态、进度条、开关和重点图标',
              color: _seed,
              onTap: () => _pickSeedColor(),
            ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '基础模式只需要选择主主题色，浅色和深色下的背景、卡片、文字、边框等会自动生成；切到高级模式可以逐项覆盖。',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            SegmentedButton<Brightness>(
              segments: const [
                ButtonSegment<Brightness>(
                  value: Brightness.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('浅色配色'),
                ),
                ButtonSegment<Brightness>(
                  value: Brightness.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('深色配色'),
                ),
              ],
              selected: <Brightness>{_editingBrightness},
              onSelectionChanged: (value) {
                setState(() => _editingBrightness = value.first);
              },
            ),
            if (_editingBrightness == Brightness.dark) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _applyLightToDark,
                  icon: const Icon(Icons.copy_all_rounded),
                  label: const Text('套用浅色配色'),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '把浅色模式当前的 8 项颜色完整复制到深色模式；复制后仍可以继续单独调整深色配色。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            _ColorSettingTile(
              title: '主主题色',
              description: '主按钮、选中态、进度条、开关、重点图标',
              color: _editingColors.primary,
              onTap: () => _pickSemantic(
                '主主题色',
                _editingColors.primary,
                (value) => _replaceEditing(
                  _editingColors.copyWith(primary: value),
                ),
              ),
            ),
            _ColorSettingTile(
              title: '辅助强调色',
              description: '标签、装饰和荧光/拼贴/复古等风格的第二强调色',
              color: _editingColors.accent,
              onTap: () => _pickSemantic(
                '辅助强调色',
                _editingColors.accent,
                (value) => _replaceEditing(
                  _editingColors.copyWith(accent: value),
                ),
              ),
            ),
            _ColorSettingTile(
              title: '背景色',
              description: '页面最底层的大背景',
              color: _editingColors.background,
              onTap: () => _pickSemantic(
                '背景色',
                _editingColors.background,
                (value) => _replaceEditing(
                  _editingColors.copyWith(background: value),
                ),
              ),
            ),
            _ColorSettingTile(
              title: '卡片 / 面板色',
              description: '排单卡片、设置面板、弹窗和抽屉主体',
              color: _editingColors.surface,
              onTap: () => _pickSemantic(
                '卡片 / 面板色',
                _editingColors.surface,
                (value) => _replaceEditing(
                  _editingColors.copyWith(surface: value),
                ),
              ),
            ),
            _ColorSettingTile(
              title: '次级表面色',
              description: '搜索框、输入框、筛选条和弱强调底板',
              color: _editingColors.surfaceAlt,
              onTap: () => _pickSemantic(
                '次级表面色',
                _editingColors.surfaceAlt,
                (value) => _replaceEditing(
                  _editingColors.copyWith(surfaceAlt: value),
                ),
              ),
            ),
            _ColorSettingTile(
              title: '主文字色',
              description: '标题、正文和主要图标',
              color: _editingColors.foreground,
              onTap: () => _pickSemantic(
                '主文字色',
                _editingColors.foreground,
                (value) => _replaceEditing(
                  _editingColors.copyWith(foreground: value),
                ),
              ),
            ),
            _ColorSettingTile(
              title: '次文字 / 说明色',
              description: '副标题、提示文字、未选中图标和输入提示',
              color: _editingColors.mutedForeground,
              onTap: () => _pickSemantic(
                '次文字 / 说明色',
                _editingColors.mutedForeground,
                (value) => _replaceEditing(
                  _editingColors.copyWith(mutedForeground: value),
                ),
              ),
            ),
            _ColorSettingTile(
              title: '边框 / 分割线色',
              description: '描边、分割线和弱轮廓',
              color: _editingColors.border,
              onTap: () => _pickSemantic(
                '边框 / 分割线色',
                _editingColors.border,
                (value) => _replaceEditing(
                  _editingColors.copyWith(border: value),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _resetDraft,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('恢复进入时状态'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _save(),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_editingId == null ? '保存方案' : '保存修改'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _applyLightToDark() {
    setState(() {
      _dark = _light;
      _editingBrightness = Brightness.dark;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已把浅色配色套用到深色模式，可以继续单独调整。'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickSeedColor() async {
    final picked = await showThemeColorPicker(
      context: context,
      initialColor: _seed,
      title: '主主题色',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _seed = picked;
      _light = AppThemeSemanticColors.fromSeed(picked, Brightness.light);
      _dark = AppThemeSemanticColors.fromSeed(picked, Brightness.dark);
    });
  }

  Future<void> _pickSemantic(
    String title,
    Color initial,
    ValueChanged<Color> apply,
  ) async {
    final picked = await showThemeColorPicker(
      context: context,
      initialColor: initial,
      title: title,
    );
    if (picked != null && mounted) apply(picked);
  }

  void _replaceEditing(AppThemeSemanticColors colors) {
    setState(() {
      if (_editingBrightness == Brightness.light) {
        _light = colors;
        _seed = colors.primary;
      } else {
        _dark = colors;
      }
    });
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('方案名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(
            hintText: '例如：奶油蓝、深夜紫',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty || !mounted) return;
    setState(() => _name = result);
  }

  Future<void> _save({bool copy = false}) async {
    var name = _name;
    if (copy) {
      final controller = TextEditingController(text: '$_name 副本');
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('另存为新方案'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 20,
            decoration: const InputDecoration(labelText: '方案名称'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (result == null || result.isEmpty) return;
      name = result;
    }

    final light = _advanced
        ? _light
        : AppThemeSemanticColors.fromSeed(_seed, Brightness.light);
    final dark = _advanced
        ? _dark
        : AppThemeSemanticColors.fromSeed(_seed, Brightness.dark);

    final saved = await widget.store.saveCustomPalette(
      id: copy ? null : _editingId,
      name: name,
      seed: _advanced ? light.primary : _seed,
      light: light,
      dark: dark,
      advanced: _advanced,
    );
    if (!mounted) return;
    Navigator.of(context).pop(saved);
  }

  Future<void> _delete() async {
    final id = _editingId;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这个配色？'),
        content: Text('“$_name”会从自定义方案中删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.deleteCustomPalette(id);
    if (mounted) Navigator.of(context).pop();
  }

  void _resetDraft() {
    setState(() {
      _name = _initialName;
      _advanced = _initialAdvanced;
      _seed = _initialSeed;
      _light = _initialLight;
      _dark = _initialDark;
      _editingBrightness = Brightness.light;
    });
  }
}

class _ColorSettingTile extends StatelessWidget {
  const _ColorSettingTile({
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(description),
        trailing: Container(
          width: 44,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _PaletteLivePreview extends StatelessWidget {
  const _PaletteLivePreview({required this.colors});

  final AppThemeSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    final onPrimary = colors.primary.computeLuminance() > 0.48
        ? Colors.black
        : Colors.white;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '实时预览',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.foreground,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: colors.mutedForeground),
                const SizedBox(width: 8),
                Text(
                  '搜索排单',
                  style: TextStyle(color: colors.mutedForeground),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '米画师',
                        style: TextStyle(
                          color: colors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '示例排单',
                        style: TextStyle(
                          color: colors.foreground,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '草稿 40% · 剩余 3天',
                  style: TextStyle(color: colors.mutedForeground),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '确认节点',
                    style: TextStyle(
                      color: onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Icon(Icons.list_alt_rounded, color: colors.primary),
              Icon(Icons.image_outlined, color: colors.mutedForeground),
              Icon(Icons.calendar_month_outlined,
                  color: colors.mutedForeground),
              Icon(Icons.bar_chart_rounded, color: colors.mutedForeground),
            ],
          ),
        ],
      ),
    );
  }
}
