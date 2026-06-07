import 'package:flutter/material.dart';

/// Stateful widget that tracks mouse hover state and exposes it to [builder].
class HoverListener extends StatefulWidget {
  const HoverListener({required this.builder, super.key});

  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<HoverListener> createState() => _HoverListenerState();
}

class _HoverListenerState extends State<HoverListener> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}
