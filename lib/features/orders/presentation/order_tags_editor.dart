import 'package:flutter/material.dart';

import '../../shared/presentation/detail_form_widgets.dart';
import '../domain/queue_order.dart';

/// An order owns its labels: the same values travel through backup and sync.
class OrderTagsEditor extends StatefulWidget {
  const OrderTagsEditor({
    required this.selectedTags,
    required this.availableTags,
    required this.onChanged,
    super.key,
  });

  final List<String> selectedTags;
  final Iterable<String> availableTags;
  final ValueChanged<List<String>> onChanged;

  @override
  State<OrderTagsEditor> createState() => _OrderTagsEditorState();
}

class _OrderTagsEditorState extends State<OrderTagsEditor> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addTag([String? suggestion]) {
    final value = (suggestion ?? _controller.text).trim();
    if (value.isEmpty) return;
    widget.onChanged(
      normalizeOrderTags(<String>[...widget.selectedTags, value]),
    );
    if (suggestion == null) _controller.clear();
  }

  void _removeTag(String tag) {
    widget.onChanged(<String>[
      for (final value in widget.selectedTags)
        if (value != tag) value,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedTags.map((tag) => tag.toLowerCase()).toSet();
    final suggestions = normalizeOrderTags(widget.availableTags)
        .where((tag) => !selected.contains(tag.toLowerCase()))
        .toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FormFieldLabel('自定义标签'),
        if (widget.selectedTags.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final tag in widget.selectedTags)
                InputChip(
                  label: Text(tag),
                  onDeleted: () => _removeTag(tag),
                  deleteIcon: const Icon(Icons.close_rounded, size: 17),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _controller,
          maxLength: 24,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _addTag(),
          decoration: InputDecoration(
            hintText: '输入标签名称，点击加号添加',
            prefixIcon: const Icon(Icons.label_outline_rounded),
            suffixIcon: IconButton(
              tooltip: '添加标签',
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _addTag(),
            ),
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          Text(
            '已有标签（点击添加）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final tag in suggestions)
                ActionChip(
                  label: Text(tag),
                  onPressed: () => _addTag(tag),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
