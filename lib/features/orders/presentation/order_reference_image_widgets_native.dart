import 'dart:async';
import 'dart:io';

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
    final preview = _exists && _file != null
        ? Image.file(
            _file!,
            fit: BoxFit.cover,
            cacheWidth: 600,
            errorBuilder: (_, __, ___) =>
                const ReferenceImageUnavailablePreview(
              icon: Icons.broken_image_outlined,
              text: '无法预览',
            ),
          )
        : const ReferenceImageUnavailablePreview(
            icon: Icons.cloud_sync_outlined,
            text: '同步中',
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
    final image = _exists && _file != null
        ? Image.file(
            _file!,
            fit: BoxFit.contain,
            cacheWidth: 4096,
            errorBuilder: (_, __, ___) =>
                const ReferenceImageUnavailablePreview(
              icon: Icons.broken_image_outlined,
              text: '图片格式暂时无法预览，但仍可保存原文件',
            ),
          )
        : null;

    return ReferenceImageViewerScaffold(
      fileName: widget.image.fileName,
      saving: _saving,
      canSave: _exists,
      onSave: _save,
      loading: false,
      image: image,
      missingIcon: Icons.cloud_sync_outlined,
      missingTitle: '图片正在从另一台设备同步',
      missingBody: '文件到达本机后会自动显示，不需要重新进入详情页。',
      onRefresh: () => unawaited(_refresh()),
    );
  }
}
