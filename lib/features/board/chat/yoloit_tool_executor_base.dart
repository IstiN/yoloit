import 'package:yoloit/features/board/chat/chat_provider.dart';

/// Abstract interface for invoking YoLoIT tools from chat providers.
abstract interface class YoloitToolExecutor {
  /// Invoke a YoLoIT tool by [functionName] with the provided [arguments].
  ///
  /// When [argumentsPreNormalized] is true, [arguments] have already been run
  /// through [YoloitCliToolArgumentNormalizer.normalize].
  Future<String> invoke(
    String functionName,
    Map<String, Object?> arguments, {
    ChatRuntimeContext? runtimeContext,
    bool argumentsPreNormalized = false,
  });
}
