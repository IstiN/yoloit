import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';

class DebugSessionListView extends StatefulWidget {
  const DebugSessionListView({super.key, required this.sessions, required this.colors});

  final List<Map<String, dynamic>> sessions;
  final AppColorScheme colors;

  @override
  State<DebugSessionListView> createState() => DebugSessionListViewState();
}

class DebugSessionListViewState extends State<DebugSessionListView> {
  int _selectedIndex = 0;
  String _selectedTab = 'timings';

  static const _tabs = ['timings', 'messages', 'tools', 'raw output'];

  @override
  Widget build(BuildContext context) {
    final sessions = widget.sessions;
    final colors = widget.colors;
    final session = sessions.isEmpty ? null : sessions[_selectedIndex];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Session list (left side)
        SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Sessions (newest first)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.appColors.textMuted,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (_, i) {
                    final s = sessions[i];
                    final isActive = s['completedAt'] == null;
                    final isSelected = i == _selectedIndex;
                    final userMsg = '${s['userMessage'] ?? ''}'.trim();
                    final short =
                        userMsg.length > 32
                            ? '${userMsg.substring(0, 32)}…'
                            : userMsg;
                    final ts = s['requestAt'] as String? ?? '';
                    final time = ts.length >= 19 ? ts.substring(11, 19) : ts;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedIndex = i),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isSelected
                                  ? colors.primary.withAlpha(30)
                                  : colors.surfaceElevated,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                isSelected
                                    ? colors.primary.withAlpha(80)
                                    : colors.border.withAlpha(40),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (isActive)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: SizedBox(
                                      width: 8,
                                      height: 8,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: colors.primary,
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    time,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color:
                                          context.appColors.textMuted,
                                    ),
                                  ),
                                ),
                                if (s['error'] != null)
                                  Icon(
                                    Icons.error_outline,
                                    size: 12,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              short,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Detail panel (right side)
        Expanded(
          child:
              session == null
                  ? const SizedBox.shrink()
                  : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tab row
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children:
                              _tabs.map((tab) {
                                final sel = tab == _selectedTab;
                                return GestureDetector(
                                  onTap:
                                      () => setState(() => _selectedTab = tab),
                                  child: Container(
                                    margin: const EdgeInsets.only(
                                      right: 6,
                                      bottom: 6,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          sel
                                              ? colors.primary.withAlpha(40)
                                              : colors.surfaceElevated,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color:
                                            sel
                                                ? colors.primary
                                                : colors.border.withAlpha(60),
                                      ),
                                    ),
                                    child: Text(
                                      tab,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight:
                                            sel
                                                ? FontWeight.w700
                                                : FontWeight.normal,
                                        color:
                                            sel
                                                ? colors.primary
                                                : context.appColors.textMuted,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colors.border),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(
                              _buildDetailText(session, _selectedTab),
                              style: const TextStyle(
                                fontFamily: 'JetBrainsMono',
                                fontSize: 11,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                final text = _buildDetailText(
                                  session,
                                  _selectedTab,
                                );
                                copyToClipboard(text);
                              },
                              icon: const Icon(Icons.copy_outlined, size: 14),
                              label: const Text('Copy'),
                              style: TextButton.styleFrom(
                                textStyle: const TextStyle(fontSize: 11),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
        ),
      ],
    );
  }

  String _buildDetailText(Map<String, dynamic> s, String tab) {
    switch (tab) {
      case 'timings':
        return _buildTimingsText(s);
      case 'messages':
        final msgs = s['messages'];
        if (msgs is List) {
          return const JsonEncoder.withIndent('  ').convert(msgs);
        }
        return '${s['prompt'] ?? '(not captured yet)'}';
      case 'tools':
        return _buildToolsText(s);
      case 'raw output':
        return _buildRawOutputText(s);
      default:
        return '';
    }
  }

  String _buildTimingsText(Map<String, dynamic> s) {
    final buf = StringBuffer();

    final asr = s['asr'] as Map?;
    final requestAt = _parseTs(s['requestAt']);
    final promptSentAt = _parseTs(s['promptSentAt']);
    final firstTokenAt = _parseTs(s['firstTokenAt']);
    final completedAt = _parseTs(s['completedAt']);
    final toolCalls =
        (s['toolCalls'] as List?)?.whereType<Map<String, dynamic>>().toList() ??
        [];

    // ── helpers ──────────────────────────────────────────────────────────────
    String ms(int? v) => v != null ? '${v}ms' : '?';
    // Right-align a label/value row in a fixed 40-char line
    String row(String tag, String label, String? value) {
      final pad = (30 - label.length).clamp(1, 30);
      final dots = '.' * pad;
      return '$tag  $label$dots  ${value ?? '?'}';
    }

    // ── header ───────────────────────────────────────────────────────────────
    buf.writeln('User: ${s['userMessage'] ?? ''}');
    buf.writeln();
    // Model info line
    final modelId = s['modelId'] as String?;
    final modelProvider = s['modelProvider'] as String?;
    if (modelId != null) {
      final providerLabel = modelProvider != null ? '[$modelProvider]' : '';
      buf.writeln('Model: $modelId  $providerLabel'.trim());
      buf.writeln();
    }
    buf.writeln('══ Timeline ══════════════════════════════════');

    // ── [ASR] phase ──────────────────────────────────────────────────────────
    if (asr != null) {
      final asrMs = (asr['durationMs'] as num?)?.toInt();
      final asrStatus = asr['status'] as String? ?? '';
      final chars = asr['transcriptChars'] as num?;
      final mode = asr['mode'] as String? ?? '';
      final asrModel = asr['model'] as String?;
      final asrProvider = asr['provider'] as String?;
      final convMs = (asr['conversionMs'] as num?)?.toInt();
      final suffix = [
        if (asrStatus.isNotEmpty && asrStatus != 'ok') '($asrStatus)',
        if (mode.isNotEmpty) '[$mode]',
        if (chars != null) '$chars chars',
      ].join('  ');
      buf.writeln(row('[ASR]', 'audio → text', '${ms(asrMs)}  $suffix'.trim()));
      if (convMs != null) {
        buf.writeln(row('     ', '↳ wav→mp3 convert', ms(convMs)));
      }
      if (asrModel != null) {
        final provLabel = asrProvider != null ? '  [$asrProvider]' : '';
        buf.writeln(row('     ', '↳ model', '$asrModel$provLabel'));
      }
    }

    // ── [LLM] text → first token (TTFT) ──────────────────────────────────────
    final ttftMs =
        (promptSentAt != null && firstTokenAt != null)
            ? firstTokenAt.difference(promptSentAt).inMilliseconds
            : null;
    if (toolCalls.isNotEmpty) {
      buf.writeln(row('[LLM]', 'text → tools (TTFT)', ms(ttftMs)));
    } else {
      buf.writeln(row('[LLM]', 'text → first token (TTFT)', ms(ttftMs)));
    }

    // ── per-tool lines ────────────────────────────────────────────────────────
    DateTime? lastToolEnd;
    for (final tc in toolCalls) {
      final toolStart = _parseTs(tc['startAt'] as String?);
      final toolEnd = _parseTs(tc['endAt'] as String?);
      final durMs =
          (toolStart != null && toolEnd != null)
              ? toolEnd.difference(toolStart).inMilliseconds
              : null;
      final ok = tc['success'] as bool? ?? true;
      final name = tc['name'] as String? ?? '?';
      buf.writeln(row('[TOOL]', '↳ $name', '${ms(durMs)}  ${ok ? '✅' : '❌'}'));
      // Show up to 3 argument key=value pairs inline
      final args = tc['arguments'];
      if (args is Map && args.isNotEmpty) {
        var shown = 0;
        for (final entry in args.entries) {
          if (shown >= 3) break;
          final val = '${entry.value}';
          final truncVal = val.length > 40 ? '${val.substring(0, 37)}…' : val;
          buf.writeln(row('     ', '  ${entry.key}', truncVal));
          shown++;
        }
      }
      if (toolEnd != null) lastToolEnd = toolEnd;
    }

    // ── [LLM] tools → final response ─────────────────────────────────────────
    if (toolCalls.isNotEmpty && lastToolEnd != null && completedAt != null) {
      final finalMs = completedAt.difference(lastToolEnd).inMilliseconds;
      buf.writeln(row('[LLM]', 'tools → final message', ms(finalMs)));
    } else if (toolCalls.isEmpty &&
        firstTokenAt != null &&
        completedAt != null) {
      final genMs = completedAt.difference(firstTokenAt).inMilliseconds;
      buf.writeln(row('[LLM]', 'streaming response', ms(genMs)));
    }

    // ── totals ────────────────────────────────────────────────────────────────
    buf.writeln('──────────────────────────────────────────────');
    final asrMs = (asr?['durationMs'] as num?)?.toInt();
    if (asrMs != null && completedAt != null && promptSentAt != null) {
      final llmMs = completedAt.difference(promptSentAt).inMilliseconds;
      buf.writeln(row('     ', 'ASR + LLM total', ms(asrMs + llmMs)));
    }
    if (requestAt != null && completedAt != null) {
      final totalMs = completedAt.difference(requestAt).inMilliseconds;
      buf.writeln(row('     ', 'Wall time (total)', ms(totalMs)));
    }

    // ── error ─────────────────────────────────────────────────────────────────
    if (s['error'] != null) {
      buf.writeln();
      buf.writeln('❌ ERROR: ${s['error']}');
    }

    // ── Swift (MLX) section ───────────────────────────────────────────────────
    final swift = s['swiftTimings'] as Map?;
    if (swift != null) {
      buf.writeln();
      buf.writeln('══ MLX (Swift) ═══════════════════════════════');
      final cacheHit = swift['swiftCacheHit'];
      buf.writeln(
        row(
          '     ',
          'model cache',
          cacheHit == true
              ? 'HIT ✓'
              : cacheHit == false
              ? 'MISS (loaded)'
              : '-',
        ),
      );
      final loadMs = swift['swiftLoadMs'] as num?;
      if (loadMs != null) {
        buf.writeln(row('     ', 'load time', ms(loadMs.toInt())));
      }
      final ttft = swift['swiftFirstTokenMs'] as num?;
      if (ttft != null) {
        buf.writeln(row('     ', 'first token (TTFT)', ms(ttft.toInt())));
      }
      final genMs = swift['swiftGenerateMs'] as num?;
      if (genMs != null) {
        buf.writeln(row('     ', 'generation', ms(genMs.toInt())));
      }
      final totalMs = swift['swiftTotalMs'] as num?;
      if (totalMs != null) {
        buf.writeln(row('     ', 'swift total', ms(totalMs.toInt())));
      }
    }

    // ── model settings ────────────────────────────────────────────────────────
    buf.writeln();
    buf.writeln('══ Settings ══════════════════════════════════');
    buf.writeln(row('     ', 'maxTokens', '${s['maxTokens'] ?? '-'}'));
    buf.writeln(row('     ', 'temperature', '${s['temperature'] ?? '-'}'));

    return buf.toString();
  }

  String _buildToolsText(Map<String, dynamic> s) {
    final buf = StringBuffer();
    buf.writeln('=== Tool Schemas sent to LLM ===');
    buf.writeln();
    buf.writeln(s['toolSchemas'] ?? '(not captured yet)');
    buf.writeln();

    final toolCalls = s['toolCalls'] as List?;
    if (toolCalls != null && toolCalls.isNotEmpty) {
      buf.writeln('=== Tool Calls (raw) ===');
      buf.writeln();
      for (final tc in toolCalls) {
        if (tc is Map) {
          buf.writeln('Tool: ${tc['name']}');
          buf.writeln('Start: ${tc['startAt']}  End: ${tc['endAt']}');
          buf.writeln('Arguments:');
          try {
            buf.writeln(
              const JsonEncoder.withIndent('  ').convert(tc['arguments']),
            );
          } catch (_) {
            buf.writeln('  ${tc['arguments']}');
          }
          buf.writeln('Result:');
          try {
            final res = tc['result'];
            final decoded = jsonDecode(res as String);
            buf.writeln(const JsonEncoder.withIndent('  ').convert(decoded));
          } catch (_) {
            buf.writeln('  ${tc['result']}');
          }
          buf.writeln();
        }
      }
    } else {
      buf.writeln('(no tool calls in this session)');
    }

    return buf.toString();
  }

  String _buildRawOutputText(Map<String, dynamic> s) {
    final buf = StringBuffer();
    buf.writeln('=== Raw Chunks Output (before stripping) ===');
    buf.writeln();
    buf.writeln(s['rawChunksOutput'] ?? '(not captured yet)');
    buf.writeln();
    buf.writeln('=== Raw Final Response ===');
    buf.writeln();
    buf.writeln(s['rawFinalResponse'] ?? '(not captured yet)');
    buf.writeln();
    if (s['cleanedResponse'] != null) {
      buf.writeln('=== Cleaned Response (after tool echo stripping) ===');
      buf.writeln();
      buf.writeln(s['cleanedResponse']);
    }
    return buf.toString();
  }

  DateTime? _parseTs(Object? value) {
    if (value is! String || value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }
}
