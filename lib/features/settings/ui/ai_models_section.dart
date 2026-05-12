import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';

/// Model download status.
enum ModelStatus { notDownloaded, downloading, ready }

/// Settings section for selecting ASR, TTS, and LLM models.
class AiModelsSection extends StatefulWidget {
  const AiModelsSection({super.key});

  @override
  State<AiModelsSection> createState() => _AiModelsSectionState();
}

class _AiModelsSectionState extends State<AiModelsSection> {
  // ASR
  String _asrModel = 'Whisper Large V3';
  final ModelStatus _asrStatus = ModelStatus.notDownloaded;
  static const _asrOptions = [
    'Whisper Large V3',
    'Whisper Medium',
    'Whisper Small',
    'Distil-Whisper',
  ];

  // TTS
  String _ttsModel = 'Kokoro';
  final ModelStatus _ttsStatus = ModelStatus.notDownloaded;
  static const _ttsOptions = ['Kokoro', 'Piper', 'eSpeak'];

  // LLM
  String _llmModel = 'Local (Llama 3.1 8B)';
  final ModelStatus _llmStatus = ModelStatus.notDownloaded;
  static const _llmOptions = [
    'Local (Llama 3.1 8B)',
    'Local (Mistral 7B)',
    'Copilot',
    'OpenAI GPT-4',
    'Claude',
  ];
  final _apiKeyController = TextEditingController();
  bool _apiKeyObscured = true;

  bool get _isCloudLlm =>
      _llmModel == 'Copilot' ||
      _llmModel == 'OpenAI GPT-4' ||
      _llmModel == 'Claude';

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  void _showComingSoon(String action) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$action coming soon')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModelCard(
          icon: Icons.mic,
          title: 'ASR Model (Speech-to-Text)',
          options: _asrOptions,
          value: _asrModel,
          status: _asrStatus,
          onChanged: (v) => setState(() => _asrModel = v!),
          onAction: () => _showComingSoon('Download'),
          actionLabel: 'Download',
        ),
        const SizedBox(height: 16),
        _ModelCard(
          icon: Icons.record_voice_over,
          title: 'TTS Model (Audio)',
          options: _ttsOptions,
          value: _ttsModel,
          status: _ttsStatus,
          onChanged: (v) => setState(() => _ttsModel = v!),
          onAction: () => _showComingSoon('Download'),
          actionLabel: 'Download',
        ),
        const SizedBox(height: 16),
        _ModelCard(
          icon: Icons.psychology,
          title: 'YoLo Assistant LLM',
          options: _llmOptions,
          value: _llmModel,
          status: _llmStatus,
          onChanged: (v) => setState(() => _llmModel = v!),
          onAction:
              () =>
                  _showComingSoon(_isCloudLlm ? 'Test Connection' : 'Download'),
          actionLabel: _isCloudLlm ? 'Test Connection' : 'Download',
          extra: _isCloudLlm ? _buildApiKeyField() : null,
        ),
      ],
    );
  }

  Widget _buildApiKeyField() {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextField(
        controller: _apiKeyController,
        obscureText: _apiKeyObscured,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'API Key',
          hintStyle: TextStyle(
            color:
                Theme.of(context).textTheme.bodySmall?.color ??
                Theme.of(context).colorScheme.onSurface,
            fontSize: 12,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.border),
          ),
          suffixIcon: IconButton(
            icon: Icon(
              _apiKeyObscured
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 16,
            ),
            color:
                Theme.of(context).textTheme.bodySmall?.color ??
                Theme.of(context).colorScheme.onSurface,
            onPressed: () => setState(() => _apiKeyObscured = !_apiKeyObscured),
          ),
        ),
      ),
    );
  }
}

// ─── Reusable model card ──────────────────────────────────────────────────────

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.icon,
    required this.title,
    required this.options,
    required this.value,
    required this.status,
    required this.onChanged,
    required this.onAction,
    required this.actionLabel,
    this.extra,
  });

  final IconData icon;
  final String title;
  final List<String> options;
  final String value;
  final ModelStatus status;
  final ValueChanged<String?> onChanged;
  final VoidCallback onAction;
  final String actionLabel;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(icon, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Dropdown + status + action
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: value,
                  items:
                      options
                          .map(
                            (o) => DropdownMenuItem(value: o, child: Text(o)),
                          )
                          .toList(),
                  onChanged: onChanged,
                  dropdownColor: colors.surfaceElevated,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.border),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _StatusChip(status: status),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: Text(actionLabel),
              ),
            ],
          ),
          if (extra != null) extra!,
        ],
      ),
    );
  }
}

// ─── Status chip ──────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final ModelStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ModelStatus.notDownloaded => ('Not Downloaded', AppColors.textMuted),
      ModelStatus.downloading => ('Downloading...', AppColors.neonBlue),
      ModelStatus.ready => ('Ready', AppColors.neonGreen),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
