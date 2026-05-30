import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';

class ChatProviderIcon extends StatelessWidget {
  const ChatProviderIcon({
    super.key,
    required this.provider,
    this.size = 16,
    this.color,
  });

  final String provider;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final iconColor = color ?? colors.accentGreen;

    final cfg = AgentConfigService.instance.configForAgent(provider);
    if (cfg != null && !cfg.isBuiltIn && cfg.iconLabel.isNotEmpty) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            cfg.iconLabel,
            style: TextStyle(
              fontSize: size * 0.75,
              fontWeight: FontWeight.w700,
              color: iconColor,
              fontFamily: 'monospace',
              height: 1,
            ),
          ),
        ),
      );
    }

    final adapter = cfg?.streamAdapter ?? provider;
    return switch (adapter) {
      'copilot' => SvgPicture.asset(
        'assets/images/copilot_mark.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
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
              color: iconColor,
              height: 1,
            ),
          ),
        ),
      ),
      'local' => Icon(Icons.memory_rounded, size: size, color: iconColor),
      'opencode' => Icon(Icons.code_rounded, size: size, color: iconColor),
      'codex' => Icon(Icons.terminal_rounded, size: size, color: iconColor),
      'kimi' => _TextProviderIcon(label: 'K', size: size, color: iconColor),
      _ => Icon(Icons.auto_awesome, size: size, color: iconColor),
    };
  }
}

class _TextProviderIcon extends StatelessWidget {
  const _TextProviderIcon({
    required this.label,
    required this.size,
    required this.color,
  });

  final String label;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: size * 0.75,
            fontWeight: FontWeight.w700,
            color: color,
            fontFamily: 'monospace',
            height: 1,
          ),
        ),
      ),
    );
  }
}
