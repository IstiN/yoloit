import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/features/board/chat/chat_panel_plugin_base.dart';

/// Board panel plugin for an AI chat powered by CLI tools (Copilot, etc.).
class ChatPanelPlugin extends ChatPanelPluginBase {
  const ChatPanelPlugin();

  static const String kTypeId = ChatPanelPluginBase.kTypeId;

  @override
  Set<PlatformCapability> get requiredCapabilities => const {
        PlatformCapability.processes,
      };
}
