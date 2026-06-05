import 'package:flutter/material.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

class NotificationsSection extends StatefulWidget {
  const NotificationsSection({super.key});

  @override
  State<NotificationsSection> createState() => NotificationsSectionState();
}

class NotificationsSectionState extends State<NotificationsSection> {
  bool _agentSoundsEnabled = true;
  bool _approvalSoundEnabled = true;
  bool _completionSoundEnabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final agent = await SessionPrefs.isAgentSoundsEnabled();
    final approval = await SessionPrefs.isApprovalSoundEnabled();
    final completion = await SessionPrefs.isCompletionSoundEnabled();
    if (mounted) {
      setState(() {
        _agentSoundsEnabled = agent;
        _approvalSoundEnabled = approval;
        _completionSoundEnabled = completion;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sound alerts when AI agents change state.',
          style: TextStyle(color: context.appColors.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 16),
        SettingsToggle(
          title: 'Enable agent sounds',
          subtitle: 'Master switch — disables all agent sound alerts',
          value: _agentSoundsEnabled,
          onChanged: (v) {
            setState(() => _agentSoundsEnabled = v);
            SessionPrefs.saveAgentSoundsEnabled(v);
          },
        ),
        const SizedBox(height: 8),
        SettingsToggle(
          title: 'Approval request sound (Sosumi)',
          subtitle: 'Plays when agent is waiting for tool approval',
          value: _approvalSoundEnabled && _agentSoundsEnabled,
          enabled: _agentSoundsEnabled,
          onChanged:
              _agentSoundsEnabled
                  ? (v) {
                    setState(() => _approvalSoundEnabled = v);
                    SessionPrefs.saveApprovalSoundEnabled(v);
                  }
                  : null,
        ),
        const SizedBox(height: 8),
        SettingsToggle(
          title: 'Completion sound (Glass)',
          subtitle: 'Plays when agent finishes responding',
          value: _completionSoundEnabled && _agentSoundsEnabled,
          enabled: _agentSoundsEnabled,
          onChanged:
              _agentSoundsEnabled
                  ? (v) {
                    setState(() => _completionSoundEnabled = v);
                    SessionPrefs.saveCompletionSoundEnabled(v);
                  }
                  : null,
        ),
      ],
    );
  }
}

class SettingsToggle extends StatelessWidget {
  const SettingsToggle({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color:
                        enabled
                            ? Theme.of(context).colorScheme.onSurface
                            : context.appColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.appColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: colors.primary,
          ),
        ],
      ),
    );
  }
}
