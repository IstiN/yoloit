import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// CLI handler for YoLo Assistant panels (`board.yolo_assistant`).
class AssistantCliHandler extends PanelCliHandler {
  const AssistantCliHandler();

  @override
  String get typeId => 'board.yolo_assistant';

  @override
  List<String> get supportedActions => [
    'send',
    'messages',
    'clear',
    'skills',
    'add-skill',
    'remove-skill',
    'mode',
    'voice-start',
    'voice-stop',
  ];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    final messages = panel.state['messages'] as List<dynamic>? ?? [];
    final skills = panel.state['activeSkills'] as List<dynamic>? ?? [];
    return {
      'mode': panel.state['mode'] ?? 'text',
      'isListening': panel.state['isListening'] ?? false,
      'isSpeaking': panel.state['isSpeaking'] ?? false,
      'activeSkills': skills,
      'messageCount': messages.length,
      'messages':
          messages.map((m) {
            final msg = m as Map<String, dynamic>;
            return {
              'role': msg['role'] ?? 'unknown',
              'content': _truncate(msg['content'] as String? ?? '', 200),
            };
          }).toList(),
    };
  }

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'send':
        return _handleSend(args, panel);
      case 'messages':
        return _handleMessages(args, panel);
      case 'clear':
        return const CliActionResult(
          message: 'Assistant chat cleared',
          stateUpdate: {'messages': <Map<String, dynamic>>[]},
        );
      case 'skills':
        return CliActionResult(
          data: {'activeSkills': panel.state['activeSkills'] ?? <String>[]},
        );
      case 'add-skill':
        return _handleAddSkill(args, panel);
      case 'remove-skill':
        return _handleRemoveSkill(args, panel);
      case 'mode':
        final mode = args['mode'] as String?;
        if (mode != 'text' && mode != 'voice') {
          return const CliActionResult(
            ok: false,
            message: 'Mode must be "text" or "voice"',
          );
        }
        return CliActionResult(
          message: 'Switched to $mode mode',
          stateUpdate: {
            'mode': mode,
            'isListening': false,
            'isSpeaking': false,
          },
        );
      case 'voice-start':
        return CliActionResult(
          message: 'Listening started',
          stateUpdate: {
            'mode': 'voice',
            'isListening': true,
            'isSpeaking': false,
          },
        );
      case 'voice-stop':
        return CliActionResult(
          message: 'Listening stopped',
          stateUpdate: {'isListening': false, 'isSpeaking': false},
        );
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  CliActionResult _handleSend(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final text = args['text'] as String? ?? args['message'] as String?;
    if (text == null || text.isEmpty) {
      return const CliActionResult(ok: false, message: 'Missing "text" field');
    }
    final messages = List<Map<String, dynamic>>.from(
      (panel.state['messages'] as List<dynamic>?) ?? [],
    );
    messages.add({
      'id': 'cli-${DateTime.now().millisecondsSinceEpoch}',
      'role': 'user',
      'content': text,
      'timestamp': DateTime.now().toIso8601String(),
    });
    return CliActionResult(
      message: 'Message sent',
      stateUpdate: {'messages': messages},
    );
  }

  CliActionResult _handleMessages(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final msgs = panel.state['messages'] as List<dynamic>? ?? [];
    final limit = args['limit'] as int? ?? msgs.length;
    final filtered =
        msgs.length > limit ? msgs.sublist(msgs.length - limit) : msgs;
    return CliActionResult(data: {'total': msgs.length, 'messages': filtered});
  }

  CliActionResult _handleAddSkill(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final skill = args['skill'] as String?;
    if (skill == null || skill.isEmpty) {
      return const CliActionResult(ok: false, message: 'Missing "skill" field');
    }
    final skills = List<String>.from(
      (panel.state['activeSkills'] as List<dynamic>?) ?? [],
    );
    if (skills.contains(skill)) {
      return CliActionResult(
        ok: false,
        message: 'Skill already active: $skill',
      );
    }
    skills.add(skill);
    return CliActionResult(
      message: 'Added skill: $skill',
      stateUpdate: {'activeSkills': skills},
    );
  }

  CliActionResult _handleRemoveSkill(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final skill = args['skill'] as String?;
    if (skill == null || skill.isEmpty) {
      return const CliActionResult(ok: false, message: 'Missing "skill" field');
    }
    final skills = List<String>.from(
      (panel.state['activeSkills'] as List<dynamic>?) ?? [],
    );
    if (!skills.remove(skill)) {
      return CliActionResult(ok: false, message: 'Skill not active: $skill');
    }
    return CliActionResult(
      message: 'Removed skill: $skill',
      stateUpdate: {'activeSkills': skills},
    );
  }

  String _truncate(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}…' : s;

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'send': const CliActionHelp(
      description: 'Send a message to the assistant',
      params: {'text': 'Message text'},
    ),
    'messages': const CliActionHelp(
      description: 'Get assistant messages',
      params: {'limit': 'Max messages to return'},
    ),
    'clear': const CliActionHelp(description: 'Clear all messages'),
    'skills': const CliActionHelp(description: 'List active skills'),
    'add-skill': const CliActionHelp(
      description: 'Add a skill',
      params: {'skill': 'Skill name'},
    ),
    'remove-skill': const CliActionHelp(
      description: 'Remove a skill',
      params: {'skill': 'Skill name'},
    ),
    'mode': const CliActionHelp(
      description: 'Switch mode',
      params: {'mode': '"text" or "voice"'},
    ),
    'voice-start': const CliActionHelp(description: 'Start voice listening'),
    'voice-stop': const CliActionHelp(description: 'Stop voice listening'),
  };
}
