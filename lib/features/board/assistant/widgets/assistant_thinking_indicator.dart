import 'package:flutter/material.dart';
import 'package:yoloit/ui/widgets/bouncing_dots_indicator.dart';

class AssistantThinkingIndicator extends StatelessWidget {
  const AssistantThinkingIndicator({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return BouncingDotsIndicator(color: color);
  }
}
