import 'package:flutter/material.dart';

import '../../shared/presentation/layout_spacing.dart';

import '../data/node_presets.dart';
import '../domain/queue_order.dart';

class NodePresetPage extends StatelessWidget {
  const NodePresetPage({required this.store, super.key});

  final NodePresetStore store;

  Future<void> _openEditor(BuildContext context, {NodePreset? preset}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NodePresetEditorPage(store: store, preset: preset),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '节点预设',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final presets = store.presets;

          return ListView.separated(
            padding: AppLayoutSpacing.pageScrollPaddingWithAction(
              context,
              left: 16,
              top: 16,
              right: 16,
            ),
            itemCount: presets.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final preset = presets[index];

              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  title: Text(
                    preset.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    preset.nodes
                        .map((node) => '${node.name} ${node.progressPercent}%')
                        .join(' → '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openEditor(context, preset: preset),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建预设'),
      ),
    );
  }
}

class NodePresetEditorPage extends StatefulWidget {
  const NodePresetEditorPage({required this.store, this.preset, super.key});

  final NodePresetStore store;
  final NodePreset? preset;

  @override
  State<NodePresetEditorPage> createState() => _NodePresetEditorPageState();
}

class _NodePresetEditorPageState extends State<NodePresetEditorPage> {
  late final TextEditingController _nameController;
  late List<NodeDefinition> _nodes;

  bool get _isNew => widget.preset == null;

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(text: widget.preset?.name ?? '');

    _nodes = widget.preset == null
        ? [
            NodeDefinition(
              id: 'node-${DateTime.now().microsecondsSinceEpoch}-start',
              name: '草稿',
              iconKey: 'edit',
              colorValue: 0xFF8D8D8D,
              progressPercent: 0,
            ),
            NodeDefinition(
              id: 'node-${DateTime.now().microsecondsSinceEpoch}-end',
              name: '成稿',
              iconKey: 'image',
              colorValue: 0xFF7F9A78,
              progressPercent: 100,
            ),
          ]
        : [for (final node in widget.preset!.nodes) node.snapshot()];
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addNode() {
    final previous = _nodes.length >= 2 ? _nodes[_nodes.length - 2] : null;
    final previousPercent = previous?.progressPercent ?? 0;
    var suggested = ((previousPercent + 100) / 2).round();
    if (suggested >= 100) suggested = 99;
    if (suggested <= previousPercent) {
      suggested = (previousPercent + 1).clamp(0, 99);
    }

    final node = NodeDefinition(
      id: 'node-${DateTime.now().microsecondsSinceEpoch}',
      name: '新节点',
      iconKey: 'circle',
      colorValue: 0xFF7A8793,
      progressPercent: suggested,
    );

    setState(() {
      _nodes.insert(_nodes.length - 1, node);
    });
  }

  void _deleteNode(int index) {
    if (_nodes.length <= 2) {
      return;
    }

    setState(() {
      _nodes.removeAt(index);
      _forceLastPercent();
    });
  }

  void _replaceNode(int index, {String? name, int? progressPercent}) {
    final old = _nodes[index];

    _nodes[index] = NodeDefinition(
      id: old.id,
      name: name ?? old.name,
      iconKey: old.iconKey,
      colorValue: old.colorValue,
      progressPercent: progressPercent ?? old.progressPercent,
      builtIn: old.builtIn,
    );
  }

  void _reorder(int oldIndex, int newIndex) {
    // Flutter's onReorder reports the insertion point before the removed item
    // is taken out, so dragging an item down needs a one-position adjustment.
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final reordered = [..._nodes];
    final item = reordered.removeAt(oldIndex);
    final target = newIndex.clamp(0, reordered.length);
    reordered.insert(target, item);

    setState(() {
      _nodes = reordered;
      _forceLastPercent();
    });
  }

  void _forceLastPercent() {
    if (_nodes.isEmpty) return;

    final last = _nodes.last;
    _nodes[_nodes.length - 1] = NodeDefinition(
      id: last.id,
      name: last.name,
      iconKey: last.iconKey,
      colorValue: last.colorValue,
      progressPercent: 100,
      builtIn: last.builtIn,
    );
  }

  void _save() {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      _message('请先填写预设名称');
      return;
    }

    _forceLastPercent();

    for (final node in _nodes) {
      if (node.name.trim().isEmpty) {
        _message('节点名称不能为空');
        return;
      }
      if (node.progressPercent < 0 || node.progressPercent > 100) {
        _message('节点百分比必须在 0% 到 100% 之间');
        return;
      }
    }

    for (var index = 1; index < _nodes.length; index++) {
      if (_nodes[index].progressPercent <= _nodes[index - 1].progressPercent) {
        _message('节点百分比需要按顺序递增');
        return;
      }
    }

    final preset = NodePreset(
      id:
          widget.preset?.id ??
          'preset-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      nodes: [
        for (var index = 0; index < _nodes.length; index++)
          NodeDefinition(
            id: _nodes[index].id,
            name: _nodes[index].name.trim(),
            iconKey: _nodes[index].iconKey,
            colorValue: _nodes[index].colorValue,
            progressPercent: index == _nodes.length - 1
                ? 100
                : _nodes[index].progressPercent,
            builtIn: _nodes[index].builtIn,
          ),
      ],
    );

    widget.store.upsert(preset);
    Navigator.of(context).pop();
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _deletePreset() async {
    final preset = widget.preset;
    if (preset == null || preset.id == defaultNodePreset.id) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除这个预设？'),
          content: Text('“${preset.name}”将从节点预设列表中删除。'),
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
        );
      },
    );

    if (confirmed == true && mounted) {
      widget.store.remove(preset.id);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final preset = widget.preset;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isNew ? '新建节点预设' : '编辑节点预设',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (preset != null && preset.id != defaultNodePreset.id)
            IconButton(
              tooltip: '删除预设',
              onPressed: _deletePreset,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          TextButton(onPressed: _save, child: const Text('保存')),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '预设名称',
                hintText: '例如：厚涂流程',
              ),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: AppLayoutSpacing.pageScrollPaddingWithAction(
                context,
                left: 12,
                top: 0,
                right: 12,
              ),
              buildDefaultDragHandles: false,
              itemCount: _nodes.length,
              onReorder: _reorder,
              itemBuilder: (context, index) {
                final node = _nodes[index];
                final isLast = index == _nodes.length - 1;
                final canDelete = _nodes.length > 2;

                return Card(
                  key: ValueKey(node.id),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.drag_handle_rounded),
                          ),
                        ),
                        Expanded(
                          child: TextFormField(
                            key: ValueKey('name-${node.id}'),
                            initialValue: node.name,
                            onChanged: (value) {
                              _replaceNode(index, name: value);
                            },
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              hintText: '节点名称',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 72,
                          child: isLast
                              ? const Text(
                                  '100%',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                )
                              : TextFormField(
                                  key: ValueKey('progress-${node.id}'),
                                  initialValue: node.progressPercent.toString(),
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  decoration: const InputDecoration(
                                    suffixText: '%',
                                    isDense: true,
                                  ),
                                  onChanged: (value) {
                                    final parsed = int.tryParse(value);
                                    if (parsed != null) {
                                      _replaceNode(
                                        index,
                                        progressPercent: parsed,
                                      );
                                    }
                                  },
                                ),
                        ),
                        if (canDelete)
                          IconButton(
                            tooltip: '删除节点',
                            onPressed: () => _deleteNode(index),
                            icon: const Icon(Icons.close_rounded),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNode,
        icon: const Icon(Icons.add_rounded),
        label: const Text('添加节点'),
      ),
    );
  }
}
