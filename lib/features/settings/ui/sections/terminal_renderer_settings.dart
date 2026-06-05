import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/terminal/data/tmux_service.dart';
import 'package:yoloit/features/terminal/models/terminal_backend_mode.dart';
import 'package:yoloit/ui/components/typography/caption.dart';

class TerminalRendererSettings extends StatefulWidget {
  const TerminalRendererSettings({super.key});

  @override
  State<TerminalRendererSettings> createState() =>
      TerminalRendererSettingsState();
}

class TerminalRendererSettingsState extends State<TerminalRendererSettings> {
  final _service = AgentConfigService.instance;
  final _tmux = TmuxService.instance;
  TerminalBackendMode _backendMode = TerminalBackendMode.local;
  bool _tmuxOn = false;

  @override
  void initState() {
    super.initState();
    _backendMode = _service.terminalBackendMode;
    _tmuxOn = _tmux.enabled;
    _service.load().then((_) {
      if (mounted) {
        setState(() {
          _backendMode = _service.terminalBackendMode;
        });
      }
    });
  }

  Future<void> _setBackendMode(TerminalBackendMode mode) async {
    setState(() {
      _backendMode = mode;
      _tmuxOn = mode == TerminalBackendMode.tmux;
    });
    await _service.setTerminalBackendMode(mode);
    await _tmux.setEnabled(mode == TerminalBackendMode.tmux);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Terminal renderer',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Caption('The embedded terminal uses xterm.dart.'),
          Divider(height: 24, color: colors.border),
          Row(
            children: [
              Icon(Icons.history_toggle_off, size: 18, color: colors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Terminal backend',
                      style: TextStyle(color: colors.textPrimary, fontSize: 13),
                    ),
                    const Caption(
                      'Runtime is the default persistent backend. Local PTY remains available as a fallback.',
                    ),
                  ],
                ),
              ),
              SegmentedButton<TerminalBackendMode>(
                segments:
                    TerminalBackendMode.values
                        .map(
                          (mode) => ButtonSegment(
                            value: mode,
                            label: Text(mode.label),
                            tooltip: mode.description,
                            enabled:
                                mode != TerminalBackendMode.tmux ||
                                _tmux.available,
                          ),
                        )
                        .toList(),
                selected: {_backendMode},
                onSelectionChanged:
                    (selected) => _setBackendMode(selected.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStateProperty.all(
                    const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          if (_backendMode == TerminalBackendMode.runtime) ...[
            const SizedBox(height: 8),
            Text(
              'Runtime is dev MVP on macOS/Linux. Existing sessions stay in the backend process.',
              style: TextStyle(color: colors.statusWarning, fontSize: 11),
            ),
          ] else if (_tmuxOn && _tmux.available) ...[
            const SizedBox(height: 8),
            Text(
              'For scroll debugging, turn this off and start a new terminal session.',
              style: TextStyle(color: colors.statusWarning, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
