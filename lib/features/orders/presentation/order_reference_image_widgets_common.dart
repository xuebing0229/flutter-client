import 'package:flutter/material.dart';

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
