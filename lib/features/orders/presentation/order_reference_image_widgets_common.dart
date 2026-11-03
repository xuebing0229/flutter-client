import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/order_reference_image_store.dart';
import '../domain/queue_order.dart';

class ReferenceImagesSectionLayout extends StatelessWidget {
  const ReferenceImagesSectionLayout({
    required this.imageCount,
    required this.itemBuilder,
    this.editable = false,
    this.onAdd,
    super.key,
  });

  final int imageCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool editable;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('参考图', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 8),
            Text(
              '$imageCount 张',
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
        if (imageCount == 0)
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
                itemCount: imageCount,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: itemBuilder,
              );
            },
          ),
      ],
    );
  }
}

class ReferenceImageTileFrame extends StatelessWidget {
  const ReferenceImageTileFrame({
    required this.fileName,
    required this.preview,
    required this.onTap,
    this.editable = false,
    this.onRemove,
    super.key,
  });

  final String fileName;
  final Widget preview;
  final VoidCallback onTap;
  final bool editable;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            preview,
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
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ),
            if (editable && onRemove != null)
              Positioned(
                top: 3,
                right: 3,
                child: IconButton.filled(
                  tooltip: '移除参考图',
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ReferenceImageUnavailablePreview extends StatelessWidget {
  const ReferenceImageUnavailablePreview({
    required this.icon,
    required this.text,
    super.key,
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

class ReferenceImageViewerScaffold extends StatelessWidget {
  const ReferenceImageViewerScaffold({
    required this.fileName,
    required this.saving,
    required this.canSave,
    required this.onSave,
    required this.loading,
    required this.image,
    required this.missingIcon,
    required this.missingTitle,
    required this.missingBody,
    this.onRefresh,
    super.key,
  });

  final String fileName;
  final bool saving;
  final bool canSave;
  final VoidCallback onSave;
  final bool loading;
  final Widget? image;
  final IconData missingIcon;
  final String missingTitle;
  final String missingBody;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text(
          fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '保存到本机',
            onPressed: canSave && !saving ? onSave : null,
            icon: saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : image != null
              ? Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 6,
                    child: image!,
                  ),
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          missingIcon,
                          size: 52,
                          color: colors.primary,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          missingTitle,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          missingBody,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        if (onRefresh != null) ...[
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: onRefresh,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('立即检查'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }
}


List<OrderReferenceImage> mergeReferenceImageEdits({
  required List<OrderReferenceImage> baseline,
  required List<OrderReferenceImage> draft,
  required List<OrderReferenceImage> current,
}) {
  final baselineIds = <String>{for (final image in baseline) image.id};
  final draftIds = <String>{for (final image in draft) image.id};
  final removedIds = baselineIds.difference(draftIds);
  final currentIds = <String>{};
  final merged = <OrderReferenceImage>[];

  for (final image in current) {
    if (removedIds.contains(image.id)) continue;
    if (currentIds.add(image.id)) merged.add(image);
  }
  for (final image in draft) {
    if (baselineIds.contains(image.id)) continue;
    if (currentIds.add(image.id)) merged.add(image);
  }
  return List<OrderReferenceImage>.unmodifiable(merged);
}

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
    return ReferenceImagesSectionLayout(
      imageCount: images.length,
      editable: editable,
      onAdd: onAdd,
      itemBuilder: (context, index) {
        final image = images[index];
        return _ReferenceImageTile(
          accountId: accountId,
          image: image,
          store: store,
          editable: editable,
          onRemove: onRemove == null ? null : () => onRemove!(image),
        );
      },
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
  Uint8List? _bytes;
  bool _loading = true;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _ReferenceImageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        oldWidget.image.relativePath != widget.image.relativePath) {
      _retryTimer?.cancel();
      _bytes = null;
      _loading = true;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.store.readAssetBytes(
        accountId: widget.accountId,
        relativePath: widget.image.relativePath,
      );
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
      if (bytes == null) {
        _retryTimer?.cancel();
        _retryTimer = Timer(
          const Duration(seconds: 2),
          () => unawaited(_load()),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bytes = null;
        _loading = false;
      });
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
    final preview = _bytes != null
        ? Image.memory(
            _bytes!,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            cacheWidth: 600,
            errorBuilder: (_, __, ___) =>
                const ReferenceImageUnavailablePreview(
              icon: Icons.broken_image_outlined,
              text: '无法预览',
            ),
          )
        : ReferenceImageUnavailablePreview(
            icon: _loading
                ? Icons.hourglass_top_rounded
                : Icons.cloud_sync_outlined,
            text: _loading ? '载入中' : '同步中',
          );

    return ReferenceImageTileFrame(
      fileName: widget.image.fileName,
      preview: preview,
      onTap: _open,
      editable: widget.editable,
      onRemove: widget.onRemove,
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
  Uint8List? _bytes;
  bool _loading = true;
  bool _saving = false;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.store.readAssetBytes(
        accountId: widget.accountId,
        relativePath: widget.image.relativePath,
      );
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
      if (bytes == null) {
        _retryTimer?.cancel();
        _retryTimer = Timer(
          const Duration(seconds: 2),
          () => unawaited(_load()),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bytes = null;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving || _bytes == null) return;
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
    final image = _bytes == null
        ? null
        : Image.memory(
            _bytes!,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.low,
            cacheWidth: 4096,
            errorBuilder: (_, __, ___) =>
                const ReferenceImageUnavailablePreview(
              icon: Icons.broken_image_outlined,
              text: '图片格式暂时无法预览，但仍可保存原文件',
            ),
          );

    return ReferenceImageViewerScaffold(
      fileName: widget.image.fileName,
      saving: _saving,
      canSave: _bytes != null,
      onSave: _save,
      loading: _loading,
      image: image,
      missingIcon: Icons.cloud_sync_outlined,
      missingTitle: '图片正在同步',
      missingBody: '文件到达当前设备后会自动显示，不需要重新进入详情页。',
      onRefresh: () => unawaited(_load()),
    );
  }
}
