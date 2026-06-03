import 'package:flutter/material.dart';
import 'package:yoloit/features/board/assistant/yolo_voice_overlay.dart';
import 'package:yoloit/ui/components/typography/label.dart';

class VoiceOverlayDebug extends StatefulWidget {
  const VoiceOverlayDebug({super.key});

  @override
  State<VoiceOverlayDebug> createState() => _VoiceOverlayDebugState();
}

class _VoiceOverlayDebugState extends State<VoiceOverlayDebug> {
  String _voiceStatus = 'idle';
  bool _simulateToolsInProcessing = false;
  double _scale = 0.7;
  double _orbScale = 0.30;
  double _ovalWidth = 2.0;
  double _ovalHeight = 1.10;
  double _titleFontSize = 9.0;
  Color _titleColor = const Color(0xFF64DFFF);
  int _waveBarCount = 22;
  double _waveAmplitude = 0.85;
  int _waveSpeed = 1400;
  double _waveWidth = 160;
  double _waveSpread = 0.50;
  double _particleScale = 0.3;
  double _responseFontSize = 18.0;
  int _borderSpeed = 1200;
  String _voiceResponse =
      'This is a sample response from the LLM model. '
      'It demonstrates how text appears in the response card.';
  String _voiceTranscript = 'Show me the weather today';

  static const _statuses = [
    'idle',
    'listening',
    'processing',
    'thinking',
    'responding',
    'output',
  ];

  String get _debugPreviewStatus =>
      _simulateToolsInProcessing && _voiceStatus == 'processing'
          ? 'responding'
          : _voiceStatus;

  String get _debugPreviewResponse {
    if (_simulateToolsInProcessing && _voiceStatus == 'processing') {
      return '''
### Tools
- ⏳ running: yoloit_panel_focus
- yoloit panel:focus music 'Список покупок'
''';
    }
    return _voiceResponse;
  }

  List<Widget> _debugSlider(
    String label,
    double value,
    double min,
    double max,
    int divisions,
    ValueChanged<double> onChanged,
  ) => [
    Row(
      children: [
        Text(
          '$label: ${value.toStringAsFixed(2)}',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            activeColor: const Color(0xFF6644FF),
          ),
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Label('Voice Overlay State'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children:
                _statuses.map((s) {
                  final active = s == _voiceStatus;
                  return ChoiceChip(
                    label: Text(s),
                    selected: active,
                    onSelected: (_) => setState(() => _voiceStatus = s),
                    selectedColor: const Color(0xFF6644FF),
                    labelStyle: TextStyle(
                      color: active ? Colors.white : Colors.white70,
                      fontSize: 12,
                    ),
                    backgroundColor: const Color(0xFF2A2C3A),
                    side: BorderSide(
                      color:
                          active
                              ? const Color(0xFF6644FF)
                              : const Color(0xFF3A3C4E),
                    ),
                  );
                }).toList(),
          ),
          const SizedBox(height: 10),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _simulateToolsInProcessing,
            onChanged:
                (value) =>
                    setState(() => _simulateToolsInProcessing = value ?? false),
            activeColor: const Color(0xFF6644FF),
            title: const Text(
              'Simulate tool calls in processing',
              style: TextStyle(fontSize: 13, color: Colors.white),
            ),
            subtitle: const Text(
              'When enabled, processing preview shows the tool-stream bubble state.',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Scale:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Expanded(
                child: Slider(
                  value: _scale,
                  min: 0.3,
                  max: 2.0,
                  divisions: 34,
                  onChanged: (v) => setState(() => _scale = v),
                  activeColor: const Color(0xFF6644FF),
                ),
              ),
            ],
          ),
          ..._debugSlider('Orb Scale', _orbScale, 0.3, 2.0, 34, (v) => setState(() => _orbScale = v)),
          ..._debugSlider('Oval Width', _ovalWidth, 0.3, 2.0, 34, (v) => setState(() => _ovalWidth = v)),
          ..._debugSlider('Oval Height', _ovalHeight, 0.1, 1.5, 28, (v) => setState(() => _ovalHeight = v)),
          ..._debugSlider('YoLo Size', _titleFontSize, 8, 60, 52, (v) => setState(() => _titleFontSize = v)),
          Row(
            children: [
              const Text(
                'YoLo Color:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              for (final c in const [
                Color(0xFF64DFFF),
                Color(0xFFB980FF),
                Color(0xFF3CE8FF),
                Color(0xFFFFFFFF),
                Color(0xFF80FFB0),
                Color(0xFFFF80B0),
              ])
                GestureDetector(
                  onTap: () => setState(() => _titleColor = c),
                  child: Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            _titleColor == c ? Colors.white : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ..._debugSlider('Wave Bars', _waveBarCount.toDouble(), 4, 60, 56, (v) => setState(() => _waveBarCount = v.round())),
          ..._debugSlider('Wave Amp', _waveAmplitude, 0.1, 2.0, 38, (v) => setState(() => _waveAmplitude = v)),
          ..._debugSlider('Wave Speed', _waveSpeed.toDouble(), 400, 4000, 36, (v) => setState(() => _waveSpeed = v.round())),
          ..._debugSlider('Wave Width', _waveWidth, 60, 300, 48, (v) => setState(() => _waveWidth = v)),
          ..._debugSlider('Wave Spread', _waveSpread, 0.0, 1.0, 20, (v) => setState(() => _waveSpread = v)),
          ..._debugSlider('Particle Scale', _particleScale, 0.3, 3.0, 27, (v) => setState(() => _particleScale = v)),
          ..._debugSlider('Resp. Font', _responseFontSize, 10, 30, 20, (v) => setState(() => _responseFontSize = v)),
          ..._debugSlider('Border Speed', _borderSpeed.toDouble(), 400, 4000, 36, (v) => setState(() => _borderSpeed = v.round())),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            height: 600,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2A2C3A)),
            ),
            child: Center(
              child: YoloVoiceOverlay(
                status: _debugPreviewStatus,
                title: 'YoLo',
                hint: 'Esc to cancel  •  Space to send',
                transcript: _voiceTranscript,
                response: _debugPreviewResponse,
                animate: true,
                scale: _scale,
                orbScale: _orbScale,
                ovalWidth: _ovalWidth,
                ovalHeight: _ovalHeight,
                titleFontSize: _titleFontSize,
                titleColor: _titleColor,
                waveBarCount: _waveBarCount,
                waveAmplitude: _waveAmplitude,
                waveSpeed: _waveSpeed,
                waveWidth: _waveWidth,
                waveSpread: _waveSpread,
                particleScale: _particleScale,
                responseFontSize: _responseFontSize,
                borderSpeed: _borderSpeed,
                onHide: () => setState(() => _voiceStatus = 'idle'),
                onPrimaryAction: () {
                  final idx = _statuses.indexOf(_voiceStatus);
                  final next = (idx + 1) % _statuses.length;
                  setState(() => _voiceStatus = _statuses[next]);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Label('Response Text'),
          const SizedBox(height: 6),
          TextField(
            maxLines: 3,
            controller: TextEditingController(text: _voiceResponse),
            onChanged: (v) => setState(() => _voiceResponse = v),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF1E2030),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF3A3C4E)),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 12),
          const Label('Transcript Text'),
          const SizedBox(height: 6),
          TextField(
            controller: TextEditingController(text: _voiceTranscript),
            onChanged: (v) => setState(() => _voiceTranscript = v),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF1E2030),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF3A3C4E)),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }
}
