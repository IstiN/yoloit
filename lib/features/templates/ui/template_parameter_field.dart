import 'package:flutter/material.dart';
import 'package:yoloit/core/utils/color_utils.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

/// Renders a single template parameter input based on its type.
class TemplateParameterField extends StatefulWidget {
  const TemplateParameterField({
    super.key,
    required this.parameter,
    required this.value,
    required this.onChanged,
    this.error,
  });

  final TemplateParameter parameter;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final String? error;

  @override
  State<TemplateParameterField> createState() => _TemplateParameterFieldState();
}

class _TemplateParameterFieldState extends State<TemplateParameterField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value?.toString() ?? widget.parameter.defaultValue?.toString() ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant TemplateParameterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newText = widget.value?.toString() ?? '';
    if (_controller.text != newText && !(_controller.value.text == newText)) {
      _controller.text = newText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final param = widget.parameter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLabel(context),
        if (param.description != null && param.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              param.description!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(160),
              ),
            ),
          ),
        _buildControl(context),
        if (widget.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              widget.error!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLabel(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            widget.parameter.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          if (widget.parameter.required)
            Text(
              ' *',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControl(BuildContext context) {
    switch (widget.parameter.type) {
      case TemplateParameterType.boolean:
        return _buildBoolean(context);
      case TemplateParameterType.choice:
        return _buildChoice(context);
      case TemplateParameterType.path:
        return _buildPath(context);
      case TemplateParameterType.color:
        return _buildColor(context);
      case TemplateParameterType.text:
        return _buildText(context, maxLines: 4);
      case TemplateParameterType.string:
        return _buildText(context);
    }
  }

  Widget _buildText(BuildContext context, {int maxLines = 1}) {
    return TextField(
      controller: _controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      onChanged: (value) => widget.onChanged(value),
    );
  }

  Widget _buildBoolean(BuildContext context) {
    final value = widget.value is bool
        ? widget.value as bool
        : widget.value?.toString().toLowerCase() == 'true';
    return Row(
      children: [
        Switch(
          value: value,
          onChanged: (newValue) => widget.onChanged(newValue),
        ),
        Text(value ? 'Yes' : 'No'),
      ],
    );
  }

  Widget _buildChoice(BuildContext context) {
    final options = widget.parameter.options ?? const [];
    final currentValue = widget.value?.toString() ??
        widget.parameter.defaultValue?.toString() ??
        (options.isNotEmpty ? options.first.value : '');
    return DropdownButtonFormField<String>(
      initialValue: currentValue,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      items:
          options
              .map(
                (option) => DropdownMenuItem<String>(
                  value: option.value,
                  child: Text(option.label),
                ),
              )
              .toList(),
      onChanged: (value) {
        if (value != null) widget.onChanged(value);
      },
    );
  }

  Widget _buildPath(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onChanged: (value) => widget.onChanged(value),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.folder_open, size: 20),
          tooltip: 'Browse',
          onPressed: () => _pickPath(context),
        ),
      ],
    );
  }

  Widget _buildColor(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onChanged: (value) => widget.onChanged(value),
          ),
        ),
        const SizedBox(width: 8),
        _ColorPreview(value: _controller.text),
      ],
    );
  }

  Future<void> _pickPath(BuildContext context) async {
    final picker = widget.parameter.picker ?? TemplateParameterPicker.directory;
    final String? path;
    if (picker == TemplateParameterPicker.file) {
      final selection = await BoardFilePicker.pickFile(
        context,
        initialPath: _controller.text,
      );
      path = selection?.path;
    } else {
      path = await BoardFilePicker.pickDirectory(
        context,
        initialPath: _controller.text,
      );
    }
    if (path != null) {
      _controller.text = path;
      widget.onChanged(path);
    }
  }
}

class _ColorPreview extends StatelessWidget {
  const _ColorPreview({required this.value});

  final String value;

  Color? get _color => parseColor(value);

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color ?? Colors.transparent,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withAlpha(120),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
