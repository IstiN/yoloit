import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:yoloit/core/hotkeys/hotkeys.dart';

/// A single named hotkey binding.
class HotkeyDefinition {
  HotkeyDefinition({
    required this.id,
    required this.description,
    required this.category,
    required this.defaultActivator,
    required this.intent,
  }) : currentActivator = defaultActivator;

  /// Unique stable identifier used for persistence.
  final String id;
  final String description;
  final String category;
  final SingleActivator defaultActivator;
  final Intent intent;

  /// The active (possibly user-overridden) activator.
  SingleActivator currentActivator;

  bool get isOverridden => !_activatorsEqual(currentActivator, defaultActivator);

  static bool _activatorsEqual(SingleActivator a, SingleActivator b) =>
      a.trigger.keyId == b.trigger.keyId &&
      a.meta == b.meta &&
      a.shift == b.shift &&
      a.alt == b.alt &&
      a.control == b.control;

  /// Human-readable representation, e.g. "⌘⇧F".
  static String formatActivator(SingleActivator a) {
    final buf = StringBuffer();
    if (a.control) buf.write('⌃');
    if (a.alt) buf.write('⌥');
    if (a.shift) buf.write('⇧');
    if (a.meta) buf.write('⌘');
    buf.write(_keyLabel(a.trigger));
    return buf.toString();
  }

  static String _keyLabel(LogicalKeyboardKey key) {
    // Special display labels
    const labels = <int, String>{
      0x00100000008: '⌫',   // backspace
      0x00100000009: '⇥',   // tab
      0x0010000000d: '↩',   // enter
      0x0010000001b: '⎋',   // escape
      0x00100000020: '⎵',   // space
      0x00100000028: "'",   // quote
      0x0010000002c: ',',
      0x0010000002e: '.',
      0x0010000002f: '/',
      0x0010000003b: ';',
      0x0010000005b: '[',
      0x0010000005c: '\\',
      0x0010000005d: ']',
      0x00100000060: '`',
      0x0010000007e: '~',
      0x00100000301: '↑',   // arrow up
      0x00100000302: '↓',   // arrow down
      0x00100000303: '←',   // arrow left
      0x00100000304: '→',   // arrow right
    };
    if (labels.containsKey(key.keyId)) return labels[key.keyId]!;
    // Single printable character
    final label = key.keyLabel;
    if (label.length == 1) return label.toUpperCase();
    // Named keys like "F1", "Delete", etc.
    return label;
  }

  /// Serialize to a JSON-safe map.
  Map<String, dynamic> toJson() => {
        'keyId': currentActivator.trigger.keyId,
        'meta': currentActivator.meta,
        'shift': currentActivator.shift,
        'alt': currentActivator.alt,
        'control': currentActivator.control,
      };

  /// Restore [currentActivator] from a JSON-safe map.
  void fromJson(Map<String, dynamic> json) {
    final keyId = json['keyId'] as int?;
    if (keyId == null) return;
    final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
    if (key == null) return;
    currentActivator = SingleActivator(
      key,
      meta: json['meta'] as bool? ?? false,
      shift: json['shift'] as bool? ?? false,
      alt: json['alt'] as bool? ?? false,
      control: json['control'] as bool? ?? false,
    );
  }
}

/// All hotkey definitions in display order.
final kHotkeyDefinitions = <HotkeyDefinition>[
  // Navigation
  HotkeyDefinition(
    id: 'prev_tab',
    description: 'Previous agent tab',
    category: 'Navigation',
    defaultActivator:
        const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true),
    intent: const PreviousAgentTabIntent(),
  ),
  HotkeyDefinition(
    id: 'next_tab',
    description: 'Next agent tab',
    category: 'Navigation',
    defaultActivator:
        const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true),
    intent: const NextAgentTabIntent(),
  ),
  HotkeyDefinition(
    id: 'close_tab',
    description: 'Close terminal tab',
    category: 'Navigation',
    defaultActivator:
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true),
    intent: const CloseTerminalTabIntent(),
  ),
  // Panels
  HotkeyDefinition(
    id: 'toggle_workspace_panel',
    description: 'Toggle workspace panel',
    category: 'Panels',
    defaultActivator:
        const SingleActivator(LogicalKeyboardKey.backslash, meta: true),
    intent: const ToggleWorkspacePanelIntent(),
  ),
  HotkeyDefinition(
    id: 'toggle_terminal_panel',
    description: 'Toggle agents / terminal panel',
    category: 'Panels',
    defaultActivator:
        const SingleActivator(LogicalKeyboardKey.keyT, meta: true),
    intent: const ToggleTerminalPanelIntent(),
  ),
  HotkeyDefinition(
    id: 'toggle_review_panel',
    description: 'Toggle file tree panel',
    category: 'Panels',
    defaultActivator: const SingleActivator(LogicalKeyboardKey.backslash,
        meta: true, shift: true),
    intent: const ToggleReviewPanelIntent(),
  ),
  // Terminal
  HotkeyDefinition(
    id: 'focus_terminal',
    description: 'Focus terminal',
    category: 'Terminal',
    defaultActivator:
        const SingleActivator(LogicalKeyboardKey.backquote, meta: true),
    intent: const FocusTerminalIntent(),
  ),
  // Search
  HotkeyDefinition(
    id: 'file_search',
    description: 'Quick open (boards, panels, files)',
    category: 'Search',
    defaultActivator:
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
    intent: const OpenFileSearchIntent(),
  ),
  // Settings
  HotkeyDefinition(
    id: 'open_settings',
    description: 'Open settings',
    category: 'Settings',
    defaultActivator:
        const SingleActivator(LogicalKeyboardKey.comma, meta: true),
    intent: const OpenSettingsIntent(),
  ),
];
