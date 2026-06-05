import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yoloit/core/hotkeys/hotkey_definition.dart';
import 'package:yoloit/core/hotkeys/hotkey_registry.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Dialog that captures the next key combo the user presses.
class KeyCaptureDialog extends StatefulWidget {
  const KeyCaptureDialog({super.key, required this.definition});
  final HotkeyDefinition definition;

  @override
  State<KeyCaptureDialog> createState() => KeyCaptureDialogState();
}

class KeyCaptureDialogState extends State<KeyCaptureDialog> {
  final _focusNode = FocusNode();
  SingleActivator? _captured;
  String? _conflict;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;

    // Ignore pure modifier keys
    final modifiers = {
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
    };
    if (modifiers.contains(key)) return;

    // Escape = cancel
    if (key == LogicalKeyboardKey.escape &&
        !HardwareKeyboard.instance.isMetaPressed) {
      Navigator.of(context).pop();
      return;
    }

    final activator = SingleActivator(
      key,
      meta: HardwareKeyboard.instance.isMetaPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
      alt: HardwareKeyboard.instance.isAltPressed,
      control: HardwareKeyboard.instance.isControlPressed,
    );

    // Check for conflict
    final conflict =
        HotkeyRegistry.instance.definitions
            .where((d) => d.id != widget.definition.id)
            .where(
              (d) =>
                  d.currentActivator.trigger.keyId == key.keyId &&
                  d.currentActivator.meta == activator.meta &&
                  d.currentActivator.shift == activator.shift &&
                  d.currentActivator.alt == activator.alt &&
                  d.currentActivator.control == activator.control,
            )
            .firstOrNull;

    setState(() {
      _captured = activator;
      _conflict = conflict?.description;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: KeyboardListener(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(120),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Remap: ${widget.definition.description}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              // Capture area
              GestureDetector(
                onTap: () => _focusNode.requestFocus(),
                child: Container(
                  width: double.infinity,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _captured != null ? colors.primary : colors.border,
                      width: _captured != null ? 2 : 1,
                    ),
                  ),
                  child:
                      _captured == null
                          ? Text(
                            'Press a key combination…',
                            style: TextStyle(
                              color: context.appColors.textMuted,
                              fontSize: 14,
                            ),
                          )
                          : Text(
                            HotkeyDefinition.formatActivator(_captured!),
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                            ),
                          ),
                ),
              ),
              if (_conflict != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber,
                      size: 14,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Conflicts with "$_conflict" — saving will override it',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed:
                        _captured == null
                            ? null
                            : () => Navigator.of(context).pop(_captured),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
