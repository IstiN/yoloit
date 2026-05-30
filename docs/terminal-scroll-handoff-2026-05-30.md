# Terminal scroll handoff (2026-05-30)

## Контекст

Проблема: в board terminal (`ts_demo terminal`) на macOS скролл двумя пальцами не прокручивает сессию как ожидается. Ранее скролл иногда переводился в историю команд (стрелки вверх/вниз), а также мог сдвигать canvas board.

## Что уже сделано

1. **Секреты env перестали печататься как команды**
   - `tmux send-keys "export ..."` убран для инжекта env.
   - Перешли на `tmux setenv` + `tmux show-environment -s`.
   - Файл: `lib/features/terminal/data/tmux_service.dart`.

2. **Отключен fallback скролла в стрелки в xterm**
   - В `TerminalView` для основных терминалов выставлено `simulateScroll: false`.
   - Это убирает автогенерацию `arrowUp/arrowDown` при scroll в alt buffer.
   - Файлы:
     - `lib/features/terminal/ui/terminal_panel.dart`
     - `lib/features/collaboration/ui/guest_terminal_view.dart`

3. **Сделан явный трекинг trackpad-жестов**
   - Добавлен `PointerPanZoomUpdateEvent` хендлинг для прокрутки.
   - Добавлен `ScrollController` для terminal view.
   - Файл: `lib/features/terminal/ui/terminal_panel.dart`.

4. **Изоляция скролла терминала от board canvas**
   - `ScrollableCardRegion` + `CanvasInteractionLock` доработаны для блокировки панорамирования board во время скролла над терминалом.
   - В `BoardView` добавлен rollback трансформации при активном lock.
   - Файлы:
     - `lib/features/mindmap/widgets/canvas_interaction_lock.dart`
     - `lib/features/board/ui/board_view.dart`
     - `lib/features/board/terminal/board_terminal_panel_widget.dart`

5. **Добавлены тесты**
   - Widget/golden тесты на скролл длинного контента и отсутствие PTY output в alt-buffer fallback-сценарии.
   - Файлы:
     - `test/widget/features/terminal/terminal_panel_test.dart`
     - `test/widget/features/collaboration/guest_terminal_view_test.dart`
     - `test/golden/terminal_scroll_goldens_test.dart`
     - `test/golden/goldens/terminal_scroll_after_trackpad_pan_zoom.png`

## Что показали последние dev-логи

Лог: `/var/folders/rb/mdj9k7w532d7s78dzhr0b1dm0000gn/T/yoloit_clip/clip_1780128602675.txt`

Ключевые факты:

- `keyFallback=false` (то есть стрелки xterm fallback больше не отправляются из нашего кода).
- `alt=true`, `scrollBack=0`, `max=0` (в alt-buffer нет scrollback внутри xterm viewport).
- `mouse=false` в строках `TerminalScroll ... alt ...` (wheel события не принимаются целевым приложением на стороне терминального протокола в текущем состоянии).

Вывод: текущая проблема уже не в нашем старом key-fallback. Узкое место сместилось на обработку mouse/scroll в alt-buffer + tmux/runtime settings.

## Что планировалось сделать дальше (следующий девелопер)

1. **Доприменить tmux runtime-настройки к уже работающему серверу**
   - Сейчас в `TmuxService.init()` runtime применяется только `status off`.
   - Нужно также применять:
     - `set -g mouse on`
     - `set -g history-limit 50000`
     - `set -sg escape-time 0`
   - Причина: если tmux-сервер уже запущен, `-f tmux.conf` может не переинициализировать эти опции.

2. **Добавить unit-тесты для `TmuxService`**
   - Проверить, что при `init()` отправляются runtime-команды (не только `status off`).
   - Желательно через инъекцию process runner (или аналогичный существующий паттерн моков процесса).

3. **Прогнать проверку в dev app (`ts_demo terminal`)**
   - Полный restart (не только hot reload).
   - Проверить в логах, что после старта tmux имеет `mouse on` и поведение скролла изменилось.

4. **Если проблема останется**
   - Добавить временный лог сырого PTY output для wheel-событий в board terminal path, чтобы увидеть, какие ESC-последовательности реально уходят в процесс.
   - Проверить, не находится ли процесс в режиме, где wheel не репортится/игнорируется на стороне приложения.

## Полезные файлы для продолжения

- `lib/features/terminal/data/tmux_service.dart`
- `lib/features/terminal/ui/terminal_panel.dart`
- `lib/features/board/terminal/board_terminal_panel_widget.dart`
- `lib/features/mindmap/widgets/canvas_interaction_lock.dart`
- `lib/features/board/ui/board_view.dart`
- `packages/xterm/lib/src/ui/scroll_handler.dart`

