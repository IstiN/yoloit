import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ChatProviderIcon extends StatelessWidget {
  const ChatProviderIcon({
    super.key,
    required this.provider,
    this.size = 16,
    this.color = const Color(0xFF34D399),
  });

  final String provider;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (provider) {
      'copilot' => SvgPicture.asset(
        'assets/images/copilot_mark.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
      'cursor' => SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            'C',
            style: TextStyle(
              fontSize: size * 0.75,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1,
            ),
          ),
        ),
      ),
      _ => Icon(Icons.auto_awesome, size: size, color: color),
    };
  }
}
