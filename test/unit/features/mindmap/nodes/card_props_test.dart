import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';
import 'package:yoloit/features/terminal/models/agent_phase.dart';

void main() {
  group('AgentCardProps.fromJson hookPhase parsing', () {
    test('parses every known phase string', () {
      final phases = <String, Type>{
        'thinking': ThinkingPhase,
        'tool:bash': ToolPhase,
        'awaiting_approval': AwaitingApprovalPhase,
        'done': DonePhase,
        'error': ErrorPhase,
      };
      for (final entry in phases.entries) {
        final props = AgentCardProps.fromJson(<String, dynamic>{
          'name': 'a',
          'hookPhase': entry.key,
        });
        expect(props.hookPhase.runtimeType, entry.value,
            reason: 'phase ${entry.key}');
      }
    });

    test('keeps the tool name for tool phases', () {
      final props = AgentCardProps.fromJson(<String, dynamic>{
        'name': 'a',
        'hookPhase': 'tool:read_file',
      });
      expect(props.hookPhase, isA<ToolPhase>());
      expect((props.hookPhase! as ToolPhase).toolName, 'read_file');
    });

    test('maps missing, null and unknown phases to null', () {
      for (final json in <Map<String, dynamic>>[
        <String, dynamic>{'name': 'a'},
        <String, dynamic>{'name': 'a', 'hookPhase': null},
        <String, dynamic>{'name': 'a', 'hookPhase': 'bogus'},
        <String, dynamic>{'name': 'a', 'hookPhase': ''},
      ]) {
        expect(AgentCardProps.fromJson(json).hookPhase, isNull, reason: '$json');
      }
    });

    test('parses lastLines and repos defensively', () {
      final props = AgentCardProps.fromJson(<String, dynamic>{
        'name': 'Copilot',
        'status': 'live',
        'isRunning': true,
        'typeName': 'copilot',
        'isIdle': true,
        'lastLines': <dynamic>['x', 42],
        'repos': <dynamic>[
          <String, dynamic>{'repo': 'yoloit', 'branch': 'main'},
        ],
      });
      expect(props.lastLines, <String>['x', '42']);
      expect(props.repos.single.repo, 'yoloit');
      expect(props.repos.single.branch, 'main');
      expect(props.isRunning, isTrue);
      expect(props.isIdle, isTrue);
    });

    test('defaults when fields are absent', () {
      final props = AgentCardProps.fromJson(<String, dynamic>{});
      expect(props.name, '');
      expect(props.status, 'idle');
      expect(props.isRunning, isFalse);
      expect(props.lastLines, isEmpty);
      expect(props.repos, isEmpty);
    });
  });
}
