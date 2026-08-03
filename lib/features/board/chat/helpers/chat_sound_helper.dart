import 'package:yoloit/features/board/chat/helpers/chat_sound_helper_vm.dart'
    if (dart.library.html) 'package:yoloit/features/board/chat/helpers/chat_sound_helper_web.dart';

export 'package:yoloit/features/board/chat/helpers/chat_sound_helper_vm.dart'
    if (dart.library.html) 'package:yoloit/features/board/chat/helpers/chat_sound_helper_web.dart';

/// Plays the chat completion sound.
///
/// A mutable top-level so tests can stub out the real `Process.run` call
/// (spawning processes inside the widget-test fake-async zone leaks timers).
Future<void> Function() playChatCompletionSound = ChatSoundHelper.play;
