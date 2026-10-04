import 'package:flutter/material.dart';

import 'layout_spacing.dart';

class CollectionBulkItem {
  const CollectionBulkItem({
    required this.id,
    required this.title,
    this.subtitle,
  });

  final String id;
  final String title;
  final String? subtitle;
}

class SearchFilterOption {
  const SearchFilterOption({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class CollectionSearchField extends StatefulWidget {
  const CollectionSearchField({
    required this.controller,
    required this.query,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
    this.filters = const [],
    this.selectedFilter,
    this.onFilterChanged,
    super.key,
  });

  final TextEditingController controller;
  final String query;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final List<SearchFilterOption> filters;
  final String? selectedFilter;
  final ValueChanged<String>? onFilterChanged;

  @override
  State<CollectionSearchField> createState() => _CollectionSearchFieldState();
}

class _CollectionSearchFieldState extends State<CollectionSearchField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  void _exitSearch() {
    widget.onClear();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final searching = _focusNode.hasFocus || widget.query.isNotEmpty;
    final showFilters = searching && widget.filters.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            onChanged: widget.onChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _focusNode.unfocus(),
            decoration: InputDecoration(
              hintText: widget.hintText,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: searching
                  ? IconButton(
                      tooltip: '退出搜索',
                      onPressed: _exitSearch,
                      icon: const Icon(Icons.close_rounded),
                    )
                  : null,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (showFilters) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final option in widget.filters) ...[
                    ChoiceChip(
                      label: Text(option.label),
                      selected: widget.selectedFilter == option.id,
                      onSelected: (_) {
                        widget.onFilterChanged?.call(option.id);
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class CollectionToolbar extends StatelessWidget {
  const CollectionToolbar({
    required this.title,
    required this.count,
    this.sortControl,
    this.cardView = false,
    this.onToggleView,
    this.helpMessage,
    this.summaryText,
    super.key,
  });

  final String title;
  final int count;
  final Widget? sortControl;
  final bool cardView;
  final VoidCallback? onToggleView;
  final String? helpMessage;
  final String? summaryText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  '$title $count',
                  maxLines: 1,
                  softWrap: false,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (summaryText != null) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        summaryText!,
                        maxLines: 1,
                        softWrap: false,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ),
                ],
                if (helpMessage != null) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: helpMessage!,
                    triggerMode: TooltipTriggerMode.tap,
                    child: Icon(
                      Icons.help_outline_rounded,
                      size: 18,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (sortControl != null) sortControl!,
          if (onToggleView != null)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onToggleView,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      cardView
                          ? Icons.grid_view_rounded
                          : Icons.view_agenda_outlined,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(cardView ? '卡片视图' : '列表视图'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> showCollectionQuickActions({
  required BuildContext context,
  required String title,
  required bool isPinned,
  required VoidCallback onTogglePinned,
  VoidCallback? onArchive,
  VoidCallback? onBulkArchive,
  required VoidCallback onDelete,
  VoidCallback? onBulkDelete,
}) {
  FocusManager.instance.primaryFocus?.unfocus();

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: media.size.height * 0.78,
          ),
          child: SingleChildScrollView(
            padding: AppLayoutSpacing.bottomSheetContentPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('快捷操作'),
                ),
                ListTile(
                  leading: Icon(
                    isPinned
                        ? Icons.push_pin_outlined
                        : Icons.push_pin_rounded,
                  ),
                  title: Text(isPinned ? '取消置顶' : '置顶'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onTogglePinned();
                  },
                ),
                if (onArchive != null)
                  ListTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: const Text('归档'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onArchive();
                    },
                  ),
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red,
                  ),
                  title: const Text(
                    '删除',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onDelete();
                  },
                ),
                if (onBulkArchive != null || onBulkDelete != null)
                  const Divider(height: 12),
                if (onBulkArchive != null)
                  ListTile(
                    leading: const Icon(Icons.library_add_check_outlined),
                    title: const Text('批量归档'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onBulkArchive();
                    },
                  ),
                if (onBulkDelete != null)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_sweep_outlined,
                      color: Colors.red,
                    ),
                    title: const Text(
                      '批量删除',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onBulkDelete();
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<bool> confirmLocalDelete({
  required BuildContext context,
  required String noun,
  required String title,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text('删除这个$noun？'),
        content: Text('“$title”删除后将从本地数据中移除。'),
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
  return confirmed == true;
}


Future<Set<String>?> showCollectionBulkPicker({
  required BuildContext context,
  required String title,
  required String confirmLabel,
  required List<CollectionBulkItem> items,
  Set<String> initialSelection = const <String>{},
  bool destructive = false,
}) {
  final selected = <String>{
    for (final id in initialSelection)
      if (items.any((item) => item.id == id)) id,
  };

  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final allSelected =
              items.isNotEmpty && selected.length == items.length;

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.72,
              child: Column(
                children: [
                  ListTile(
                    title: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '已选择 ${selected.length} 项',
                    ),
                    trailing: TextButton(
                      onPressed: items.isEmpty
                          ? null
                          : () {
                              setSheetState(() {
                                if (allSelected) {
                                  selected.clear();
                                } else {
                                  selected
                                    ..clear()
                                    ..addAll(items.map((item) => item.id));
                                }
                              });
                            },
                      child: Text(allSelected ? '取消全选' : '全选'),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final checked = selected.contains(item.id);
                        return CheckboxListTile(
                          value: checked,
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: item.subtitle == null
                              ? null
                              : Text(
                                  item.subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onChanged: (_) {
                            setSheetState(() {
                              if (checked) {
                                selected.remove(item.id);
                              } else {
                                selected.add(item.id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: AppLayoutSpacing.bulkSheetFooterPadding,
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: destructive
                            ? FilledButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).colorScheme.error,
                                foregroundColor:
                                    Theme.of(context).colorScheme.onError,
                              )
                            : null,
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.of(sheetContext).pop(
                                  Set<String>.from(selected),
                                ),
                        icon: Icon(
                          destructive
                              ? Icons.delete_sweep_outlined
                              : Icons.done_all_rounded,
                        ),
                        label: Text(
                          '$confirmLabel（${selected.length}）',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
