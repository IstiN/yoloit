import 'package:flutter/material.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/features/board/chat/widgets/chat_setup_view_common.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';
import 'package:yoloit/features/settings/ui/settings_page.dart';

class ChatSetupView extends StatefulWidget {
  const ChatSetupView({
    required this.panelId,
    required this.config,
    required this.models,
    this.remoteInfo,
    required this.onStart,
  });

  final String panelId;
  final ChatSessionConfig config;
  final List<ChatModelInfo> models;
  final RemoteBoardInfo? remoteInfo;
  final ValueChanged<ChatSessionConfig> onStart;

  @override
  State<ChatSetupView> createState() => _ChatSetupViewState();
}

class _ChatSetupViewState extends State<ChatSetupView> {
  late TextEditingController _sessionCtrl;
  List<CloudLlmConfig> _configs = [];
  String? _selectedConfigId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _sessionCtrl = TextEditingController(text: widget.config.sessionName);
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    final configs = await CloudLlmSettingsService.instance.loadConfigs();
    if (!mounted) return;
    setState(() {
      _configs = configs;
      _loading = false;
      if (configs.isNotEmpty) {
        _selectedConfigId = configs.first.id;
      }
    });
  }

  @override
  void dispose() {
    _sessionCtrl.dispose();
    super.dispose();
  }

  void _start() {
    final config = _configs.firstWhere((c) => c.id == _selectedConfigId);
    var sessionName = _sessionCtrl.text.trim();
    if (sessionName.isEmpty) {
      sessionName = 'chat-${DateTime.now().millisecondsSinceEpoch}';
    }
    widget.onStart(
      ChatSessionConfig(
        provider: 'cloud:${config.id}',
        model: config.model,
        sessionName: sessionName,
        workingDir: '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final styles = ChatSetupStyles(context);
    final inputFill = styles.colors.surfaceElevated;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_configs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Text(
              'No cloud providers configured.',
              textAlign: TextAlign.center,
              style: styles.inputTextStyle,
            ),
            const SizedBox(height: 12),
            ChatSetupStartButton(
              onPressed: () => SettingsPage.show(
                context,
                initialCategory: 'Cloud Providers',
              ),
              label: 'Open Settings',
            ),
            const Spacer(),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Cloud Provider', style: styles.labelStyle),
          const SizedBox(height: 4),
          ChatSetupDropdown<String>(
            value: _selectedConfigId,
            fillColor: inputFill,
            dropdownColor: styles.colors.surface,
            style: styles.inputTextStyle,
            items:
                _configs
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.id,
                        child: Text('${c.name} (${c.model})'),
                      ),
                    )
                    .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selectedConfigId = v);
            },
          ),
          const SizedBox(height: 14),
          Text('Session Name', style: styles.labelStyle),
          const SizedBox(height: 4),
          ChatSetupSessionNameField(
            controller: _sessionCtrl,
            styles: styles,
          ),
          const Spacer(),
          ChatSetupStartButton(
            onPressed: _start,
            label: 'Start Chat',
          ),
        ],
      ),
    );
  }
}
