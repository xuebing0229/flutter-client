import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/order_reference_image_store.dart';
import '../domain/queue_order.dart';
import 'order_reference_image_widgets_common.dart';

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
      _bytes = null;
      _loading = true;
      unawaited(_load());
    }
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
                : Icons.image_not_supported_outlined,
            text: _loading ? '载入中' : '文件缺失',
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

  @override
  void initState() {
    super.initState();
    unawaited(_load());
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
      await widget.store.exportImage(
        accountId: widget.accountId,
        image: widget.image,
      );
      if (!mounted) return;
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
      missingIcon: Icons.image_not_supported_outlined,
      missingTitle: '当前网页里没有这张参考图原文件',
      missingBody: '请重新导入包含参考图的 .zip 完整备份，或让已绑定设备在线同步。',
      onRefresh: () => unawaited(_load()),
    );
  }
}
