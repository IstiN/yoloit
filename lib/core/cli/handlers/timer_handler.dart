import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/timer_manager.dart';

/// CLI handler for Timer panels (`board.timer`).
///
/// Supports the following actions:
/// - `start [--duration <seconds>] [--label <text>]` — start/reset & start timer
/// - `pause` — pause the running timer
/// - `resume` — resume the paused timer
/// - `reset` — reset timer to its initial duration
/// - `status` — get current timer status (remaining, running, etc.)
/// - `set [--duration <seconds>] [--label <text>]` — set duration/label without starting
class TimerCliHandler extends PanelCliHandler {
  const TimerCliHandler();

  @override
  String get typeId => 'board.timer';

  @override
  List<String> get supportedActions => [
    'start',
    'pause',
    'resume',
    'reset',
    'status',
    'set',
  ];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {
      'duration': panel.state['duration'] ?? 300,
      'remaining': panel.state['remaining'] ?? 300,
      'isRunning': panel.state['isRunning'] ?? false,
      'isPaused': panel.state['isPaused'] ?? false,
      'completed': panel.state['completed'] ?? false,
      'label': panel.state['label'] ?? '',
    };
  }

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'status':
        return CliActionResult(data: getContent(panel));

      case 'set': {
        final duration = args['duration'] != null
            ? _parseDuration(args['duration'])
            : panel.state['duration'] as int? ?? 300;
        final label = args['label'] as String?;
        final update = <String, dynamic>{
          'duration': duration,
          'remaining': duration,
          'isRunning': false,
          'isPaused': false,
          'completed': false,
        };
        if (label != null) update['label'] = label;
        return CliActionResult(
          message: 'Timer set to ${_fmt(duration)}',
          stateUpdate: update,
        );
      }

      case 'start': {
        final duration = args['duration'] != null
            ? _parseDuration(args['duration'])
            : (panel.state['duration'] as int? ?? 300);
        final label = args['label'] as String?;
        final update = <String, dynamic>{
          'duration': duration,
          'remaining': duration,
          'isRunning': true,
          'isPaused': false,
          'completed': false,
          'lastTick': DateTime.now().millisecondsSinceEpoch,
        };
        if (label != null) update['label'] = label;
        return CliActionResult(
          message: 'Timer started: ${_fmt(duration)}',
          stateUpdate: update,
        );
      }

      case 'pause': {
        if (panel.state['isRunning'] != true) {
          return const CliActionResult(
            ok: false,
            message: 'Timer is not running',
          );
        }
        return const CliActionResult(
          message: 'Timer paused',
          stateUpdate: {
            'isRunning': false,
            'isPaused': true,
          },
        );
      }

      case 'resume': {
        if (panel.state['isPaused'] != true) {
          return const CliActionResult(
            ok: false,
            message: 'Timer is not paused',
          );
        }
        return CliActionResult(
          message: 'Timer resumed',
          stateUpdate: {
            'isRunning': true,
            'isPaused': false,
            'lastTick': DateTime.now().millisecondsSinceEpoch,
          },
        );
      }

      case 'reset': {
        final duration = panel.state['duration'] as int? ?? 300;
        return CliActionResult(
          message: 'Timer reset to ${_fmt(duration)}',
          stateUpdate: {
            'remaining': duration,
            'isRunning': false,
            'isPaused': false,
            'completed': false,
          },
        );
      }

      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'start': const CliActionHelp(
      description: 'Start (or restart) the timer',
      params: {
        'duration': 'Duration in seconds (default: 300)',
        'label': 'Optional timer label',
      },
      example:
          'yoloit board <id> panel <id> action --action start --duration 600 --label "Pomodoro"',
    ),
    'pause': const CliActionHelp(
      description: 'Pause the running timer',
    ),
    'resume': const CliActionHelp(
      description: 'Resume the paused timer',
    ),
    'reset': const CliActionHelp(
      description: 'Reset timer to full duration',
    ),
    'status': const CliActionHelp(
      description: 'Show current timer status',
    ),
    'set': const CliActionHelp(
      description: 'Set duration/label without starting',
      params: {
        'duration': 'Duration in seconds',
        'label': 'Optional timer label',
      },
    ),
  };

  int _parseDuration(dynamic value) {
    if (value is int) return value.clamp(1, 86400);
    if (value is num) return value.toInt().clamp(1, 86400);
    final parsed = int.tryParse(value?.toString() ?? '');
    return (parsed ?? 300).clamp(1, 86400);
  }

  String _fmt(int seconds) {
    final m = (seconds ~/ 60).toString();
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
