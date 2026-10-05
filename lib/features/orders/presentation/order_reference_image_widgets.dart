import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/order_reference_image_store.dart';
import '../domain/queue_order.dart';

class OrderReferenceImagesSection extends StatelessWidget {
  const OrderReferenceImagesSection({
    required this.accountId,
    required this.images,
    required this.store,
    this.editable = false,
    this.onAdd,
    this.onRemove,
    super.key,
  });

  final String accountId;
  final List<OrderReferenceImage> images;
  final OrderReferenceImageStore store;
  final bool editable;
  final VoidCallback? onAdd;
  final ValueChanged<OrderReferenceImage>? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '参考图',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(width: 8),
            Text(
              '${images.length} 张',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const Spacer(),
            if (editable)
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('添加'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (images.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 18,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Text(
              editable ? '还没有参考图，可以一次选择多张。' : '未添加参考图',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720
                  ? 6
                  : constraints.maxWidth >= 480
                  ? 4
                  : 3;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: images.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  final image = images[index];
                  return _ReferenceImageTile(
                    accountId: accountId,
                    image: image,
                    store: store,
                    editable: editable,
                    onRemove: onRemove == null
                        ? null
                        : () => onRemove!(image),
                  );
                },
              );
            },
          ),
      ],
    );
  }
}

class _ReferenceImageTile extends StatefulWidget {
  const _ReferenceImageTile({
    required this.accountId,
    required this.image,
    required this.store,
    required this.editable,
    this.onRemove,
  });

  final String accountId;
  final OrderReferenceImage image;
  final OrderReferenceImageStore store;
  final bool editable;
  final VoidCallback? onRemove;

  @override
  State<_ReferenceImageTile> createState() => _ReferenceImageTileState();
}

class _ReferenceImageTileState extends State<_ReferenceImageTile> {
  File? _file;
  bool _exists = false;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant _ReferenceImageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        oldWidget.image.relativePath != widget.image.relativePath) {
      _retryTimer?.cancel();
      _file = null;
      _exists = false;
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final file = await widget.store.localFile(
        accountId: widget.accountId,
        image: widget.image,
      );
      final exists = await file.exists();
      if (!mounted) return;
      setState(() {
        _file = file;
        _exists = exists;
      });
      if (!exists) {
        _retryTimer?.cancel();
        _retryTimer = Timer(
          const Duration(seconds: 2),
          () => unawaited(_refresh()),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _exists = false);
    }
  }

  void _open() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderReferenceImageViewerPage(
          accountId: widget.accountId,
          image: widget.image,
          store: widget.store,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _open,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_exists && _file != null)
              Image.file(
                _file!,
                fit: BoxFit.cover,
                cacheWidth: 600,
                errorBuilder: (_, __, ___) => _UnavailablePreview(
                  icon: Icons.broken_image_outlined,
                  text: '无法预览',
                ),
              )
            else
              const _UnavailablePreview(
                icon: Icons.cloud_sync_outlined,
                text: '同步中',
              ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Text(
                    widget.image.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ),
            if (widget.editable && widget.onRemove != null)
              Positioned(
                top: 3,
                right: 3,
                child: IconButton.filled(
                  tooltip: '移除参考图',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnavailablePreview extends StatelessWidget {
  const _UnavailablePreview({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                ),
          ),
        ],
      ),
    );
  }
}

class OrderReferenceImageViewerPage extends StatefulWidget {
  const OrderReferenceImageViewerPage({
    required this.accountId,
    required this.image,
    required this.store,
    super.key,
  });

  final String accountId;
  final OrderReferenceImage image;
  final OrderReferenceImageStore store;

  @override
  State<OrderReferenceImageViewerPage> createState() =>
      _OrderReferenceImageViewerPageState();
}

class _OrderReferenceImageViewerPageState
    extends State<OrderReferenceImageViewerPage> {
  File? _file;
  bool _exists = false;
  bool _saving = false;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final file = await widget.store.localFile(
        accountId: widget.accountId,
        image: widget.image,
      );
      final exists = await file.exists();
      if (!mounted) return;
      setState(() {
        _file = file;
        _exists = exists;
      });

      if (!exists) {
        _retryTimer?.cancel();
        _retryTimer = Timer(
          const Duration(seconds: 2),
          () => unawaited(_refresh()),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _exists = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !_exists) return;
    setState(() => _saving = true);
    try {
      final saved = await widget.store.exportImage(
        accountId: widget.accountId,
        image: widget.image,
      );
      if (!mounted || !saved) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('参考图已保存'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text(
          widget.image.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '保存到本机',
            onPressed: _exists && !_saving ? _save : null,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _exists && _file != null
          ? Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 6,
                child: Image.file(
                  _file!,
                  fit: BoxFit.contain,
                  cacheWidth: 4096,
                  errorBuilder: (_, __, ___) => const _UnavailablePreview(
                    icon: Icons.broken_image_outlined,
                    text: '图片格式暂时无法预览，但仍可保存原文件',
                  ),
                ),
              ),
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_sync_outlined,
                      size: 52,
                      color: colors.primary,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '图片正在从另一台设备同步',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '文件到达本机后会自动显示，不需要重新进入详情页。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => unawaited(_refresh()),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('立即检查'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
