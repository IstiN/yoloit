import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Common visual tokens for the chat setup view on VM and web.
class ChatSetupStyles {
  ChatSetupStyles(BuildContext context)
    : colors = context.appColors,
      colorScheme = Theme.of(context).colorScheme,
      labelStyle = TextStyle(
        fontSize: 11,
        color: context.appColors.textMuted.withAlpha(153),
      ),
      inputTextStyle = TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      hintStyle = TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurface.withAlpha(100),
      );

  final AppColorScheme colors;
  final ColorScheme colorScheme;
  final TextStyle labelStyle;
  final TextStyle inputTextStyle;
  final TextStyle hintStyle;
}

/// A styled [DropdownButton] wrapped in a rounded container.
class ChatSetupDropdown<T> extends StatelessWidget {
  const ChatSetupDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.style,
    required this.fillColor,
    required this.dropdownColor,
    super.key,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final TextStyle style;
  final Color fillColor;
  final Color dropdownColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: fillColor,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: dropdownColor,
          style: style,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// The primary "Start Chat" action button used by both VM and web setup.
class ChatSetupStartButton extends StatelessWidget {
  const ChatSetupStartButton({
    required this.onPressed,
    required this.label,
    super.key,
  });

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: context.appColors.statusActive,
        foregroundColor: context.appColors.background,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
