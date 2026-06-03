import 'package:flutter/material.dart';
import 'package:yoloit/features/board/assistant/yolo_voice_overlay.dart';
import 'package:yoloit/ui/components/typography/label.dart';

class PlectrumDebug extends StatefulWidget {
  const PlectrumDebug({super.key});

  @override
  State<PlectrumDebug> createState() => _PlectrumDebugState();
}

class _PlectrumDebugState extends State<PlectrumDebug> {
  double _rotation = 0.0;
  double _size = 250.0;
  Color _color = const Color(0xFF3CE8FF);

  static const _colors = [
    ('Cyan', Color(0xFF3CE8FF)),
    ('Blue', Color(0xFF5A7AFF)),
    ('Purple', Color(0xFFAA66FF)),
    ('Pink', Color(0xFFE060E0)),
    ('Magenta', Color(0xFFFF60CC)),
  ];

  Widget _colorChip(String label, Color c) {
    final active = _color.value == c.value;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => setState(() => _color = c),
      selectedColor: c.withValues(alpha: 0.6),
      labelStyle: TextStyle(
        color: active ? Colors.white : Colors.white70,
        fontSize: 11,
      ),
      backgroundColor: const Color(0xFF2A2C3A),
      side: BorderSide(color: active ? c : const Color(0xFF3A3C4E)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Label('Single Plectrum Shape'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final (name, c) in _colors) _colorChip(name, c),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Rotation: ${(_rotation * 180 / 3.14159).toStringAsFixed(0)}°',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: _rotation,
                  min: 0,
                  max: 6.28,
                  onChanged: (v) => setState(() => _rotation = v),
                  activeColor: const Color(0xFF6644FF),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                'Size: ${_size.toStringAsFixed(0)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: _size,
                  min: 80,
                  max: 400,
                  onChanged: (v) => setState(() => _size = v),
                  activeColor: const Color(0xFF6644FF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            height: 350,
            decoration: BoxDecoration(
              color: const Color(0xFF0D0E16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2A2C3A)),
            ),
            child: Center(
              child: SinglePlectrumPreview(
                color: _color,
                rotation: _rotation,
                size: _size,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
