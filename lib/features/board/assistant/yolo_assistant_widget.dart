import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/assistant/assistant_voice_visualizer.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Main widget for the YoLo Assistant panel.
///
/// Supports two modes: **text** (chat) and **voice** (voice-to-voice).
class YoloAssistantWidget extends StatefulWidget {
  const YoloAssistantWidget({
    super.key,
    required this.panel,
    required this.onUpdateState,
  });

  final BoardPanelInstance panel;
  final ValueChanged<Map<String, dynamic>> onUpdateState;

  @override
  State<YoloAssistantWidget> createState() => _YoloAssistantWidgetState();
}

class _YoloAssistantWidgetState extends State<YoloAssistantWidget> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();

  static const _kAccent = Color(0xFF8B5CF6);

  // ── Derived state from panel ──────────────────────────────────────────────

  List<Map<String, dynamic>> get _messages => List<Map<String, dynamic>>.from(
    (widget.panel.state['messages'] as List<dynamic>?) ?? [],
  );

  List<String> get _activeSkills => List<String>.from(
    (widget.panel.state['activeSkills'] as List<dynamic>?) ?? _defaultSkills,
  );

  String get _mode => widget.panel.state['mode'] as String? ?? 'text';
  bool get _isListening => widget.panel.state['isListening'] as bool? ?? false;
  bool get _isSpeaking => widget.panel.state['isSpeaking'] as bool? ?? false;

  static const _defaultSkills = ['Terminal', 'Board Control', 'Web Search'];
  static const _allSkills = [
    'Terminal',
    'Board Control',
    'Web Search',
    'Code Analysis',
    'File Manager',
    'Git Tools',
    'Notes',
    'Calendar',
  ];

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  // ── State helpers ─────────────────────────────────────────────────────────

  void _updateState(Map<String, dynamic> patch) {
    final merged = Map<String, dynamic>.from(widget.panel.state)..addAll(patch);
    widget.onUpdateState(merged);
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();

    final msgs = _messages;
    msgs.add({
      'id': 'msg-${DateTime.now().millisecondsSinceEpoch}',
      'role': 'user',
      'content': text,
      'timestamp': DateTime.now().toIso8601String(),
    });
    // Demo: echo a simple assistant reply
    msgs.add({
      'id': 'msg-${DateTime.now().millisecondsSinceEpoch + 1}',
      'role': 'assistant',
      'content':
          'Got it! (YoLo Assistant demo — real AI integration coming soon)',
      'timestamp': DateTime.now().toIso8601String(),
    });
    _updateState({'messages': msgs});
    _scrollToBottom();
  }

  void _toggleMode() {
    _updateState({
      'mode': _mode == 'text' ? 'voice' : 'text',
      'isListening': false,
      'isSpeaking': false,
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Skills ────────────────────────────────────────────────────────────────

  void _addSkill(String skill) {
    final skills = List<String>.from(_activeSkills);
    if (!skills.contains(skill)) {
      skills.add(skill);
      _updateState({'activeSkills': skills});
    }
  }

  void _removeSkill(String skill) {
    final skills = List<String>.from(_activeSkills);
    skills.remove(skill);
    _updateState({'activeSkills': skills});
  }

  void _showAddSkillSheet() {
    final available =
        _allSkills.where((s) => !_activeSkills.contains(s)).toList();
    showModalBottomSheet<void>(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Add Skill',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                if (available.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('All skills are active'),
                  )
                else
                  ...available.map(
                    (s) => ListTile(
                      title: Text(s),
                      leading: const Icon(Icons.add_circle_outline, size: 20),
                      onTap: () {
                        _addSkill(s);
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return _mode == 'voice' ? _buildVoiceMode() : _buildTextMode();
  }

  // ── Text (chat) mode ──────────────────────────────────────────────────────

  Widget _buildTextMode() {
    final colors = context.appColors;
    return Column(
      children: [
        _buildSkillsBar(colors),
        Expanded(child: _buildMessageList(colors)),
        _buildInputBar(colors),
      ],
    );
  }

  Widget _buildSkillsBar(AppColorScheme colors) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            ..._activeSkills.map(
              (skill) => Padding(
                padding: const EdgeInsets.only(right: 6, top: 8, bottom: 8),
                child: InputChip(
                  label: Text(skill, style: const TextStyle(fontSize: 11)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => _removeSkill(skill),
                  backgroundColor: _kAccent.withAlpha(25),
                  selectedColor: _kAccent.withAlpha(50),
                  side: BorderSide(color: _kAccent.withAlpha(60)),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: ActionChip(
                avatar: const Icon(Icons.add, size: 14),
                label: const Text('Add', style: TextStyle(fontSize: 11)),
                onPressed: _showAddSkillSheet,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(AppColorScheme colors) {
    final msgs = _messages;
    if (msgs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 48,
              color: _kAccent.withAlpha(80),
            ),
            const SizedBox(height: 12),
            Text(
              'YoLo Assistant',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _kAccent.withAlpha(180),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Ask me anything!',
              style: TextStyle(fontSize: 12, color: colors.border),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: msgs.length,
      itemBuilder: (_, i) => _buildMessageBubble(msgs[i], colors),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, AppColorScheme colors) {
    final isUser = msg['role'] == 'user';
    final content = msg['content'] as String? ?? '';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isUser ? _kAccent.withAlpha(30) : colors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                isUser ? _kAccent.withAlpha(50) : colors.border.withAlpha(40),
          ),
        ),
        child: Text(
          content,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar(AppColorScheme colors) {
    final textColor =
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    final hintColor =
        Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurface.withAlpha(153);
    return Container(
      margin: const EdgeInsets.fromLTRB(1.5, 0, 1.5, 1.5),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Voice mode toggle
          GestureDetector(
            onTap: _toggleMode,
            child: Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.graphic_eq, size: 14, color: _kAccent),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocusNode,
              style: TextStyle(fontSize: 13, color: textColor, height: 1.4),
              decoration: InputDecoration(
                hintText: 'Ask YoLo…',
                hintStyle: TextStyle(fontSize: 13, color: hintColor),
                filled: true,
                fillColor: colors.surfaceElevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: _kAccent, width: 0.8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                isDense: true,
              ),
              maxLines: 4,
              minLines: 1,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 6),
          // Microphone button
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('ASR coming soon'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.mic_none, size: 15, color: _kAccent),
            ),
          ),
          const SizedBox(width: 6),
          // Send button
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: _kAccent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.arrow_upward, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ── Voice mode ────────────────────────────────────────────────────────────

  Widget _buildVoiceMode() {
    final colors = context.appColors;

    VoiceVisualizerState vizState;
    String label;
    if (_isListening) {
      vizState = VoiceVisualizerState.listening;
      label = 'Listening…';
    } else if (_isSpeaking) {
      vizState = VoiceVisualizerState.speaking;
      label = 'Speaking…';
    } else {
      vizState = VoiceVisualizerState.idle;
      label = 'Tap to speak';
    }

    return Column(
      children: [
        _buildSkillsBar(colors),
        Expanded(
          child: GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Voice-to-Voice coming soon'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AssistantVoiceVisualizer(
                    state: vizState,
                    size: 160,
                    color: _kAccent,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: _kAccent.withAlpha(200),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: TextButton.icon(
            onPressed: _toggleMode,
            icon: const Icon(Icons.keyboard, size: 18),
            label: const Text('Back to text'),
            style: TextButton.styleFrom(foregroundColor: _kAccent),
          ),
        ),
      ],
    );
  }
}
