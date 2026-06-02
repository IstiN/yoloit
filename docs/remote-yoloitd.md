# YoLoIT Remote Daemon

`yoloitd` is the headless YoLoIT daemon for remote workspaces, Codespaces, and
containers. It exposes a YoLoIT-compatible `/api` surface without starting the
Flutter desktop window.

Current MVP scope:

- board list/create/read/update/delete
- panel list/create/read/update/delete
- panel type catalog with local/remote platform capabilities
- typed panel state actions for all built-in widget types
- append-only panel history
- `board:undo`
- simple run process API
- token auth
- desktop UI connection to remote board groups
- optimistic board revision checks for multi-user writes
- tiny browser dashboard at `/`

## Run Locally

```bash
dart run bin/yoloitd.dart \
  --host 127.0.0.1 \
  --port 43110 \
  --data-dir ~/.local/share/yoloitd \
  --token dev-token
```

Connect the existing CLI to it:

```bash
tools/yoloit remote:connect http://127.0.0.1:43110 dev-token
tools/yoloit boards
tools/yoloit board:create "Remote Board"
tools/yoloit remote:disconnect
```

Environment variables are also supported:

```bash
YOLOIT_REMOTE_URL=http://127.0.0.1:43110 \
YOLOIT_REMOTE_TOKEN=dev-token \
tools/yoloit boards
```

## Connect From The Desktop UI

1. Start `yoloitd` locally, in Docker, or on a remote machine.
2. Open the YoLoIT desktop app.
3. Click `Remote` in the board toolbar, or open the board actions menu and
   choose `Connect remote YoLoIT`.
4. Enter the daemon URL, for example `http://127.0.0.1:43110`, and the token if
   one is configured.

Remote boards are shown in the board overview under `Remote boards`. They can be
opened and edited like local boards. Before the overview opens, the app refreshes
remote board snapshots from `yoloitd`.

After a successful connection the desktop app opens the board overview so all
boards from that remote are visible immediately. Remote board settings use the
daemon filesystem browser for `Default folder`; local file pickers are used only
for local boards.

Remote writes use optimistic revision checks. If another client has already
updated the same board, `yoloitd` rejects the stale write with `409`, and the
desktop app refreshes the board from the server instead of overwriting the newer
remote state.

## Docker

```bash
docker build -f docker/Dockerfile.yoloitd -t yoloitd:dev .
docker run --rm -p 43110:43110 \
  -e YOLOITD_TOKEN=dev-token \
  -v yoloitd-data:/data \
  yoloitd:dev
```

The image is a small runtime image: the Flutter/Dart SDK is used only in the
build stage, and the final container runs the compiled `yoloitd` executable.

For a deployable mini-server setup, copy `docker/yoloitd.env.example`, set a
strong token, and start the compose stack:

```bash
cp docker/yoloitd.env.example docker/yoloitd.env
$EDITOR docker/yoloitd.env
docker compose --env-file docker/yoloitd.env -f docker/compose.yoloitd.yml up -d --build
```

For Codespaces, expose/forward port `43110`, then connect from the local YoLoIT
CLI or desktop client using the forwarded URL and token.

For a remote Linux host:

```bash
docker run -d --restart unless-stopped \
  --name yoloitd \
  -p 43110:43110 \
  -e YOLOITD_TOKEN='<strong-token>' \
  -v yoloitd-data:/data \
  yoloitd:dev
```

Use SSH port forwarding if the daemon should not be exposed publicly:

```bash
ssh -L 43110:127.0.0.1:43110 user@remote-host
```

Then connect the desktop UI to `http://127.0.0.1:43110`.

## Mobile / iOS Client

The iOS app uses the mobile board entry point:

```bash
flutter run -d <ios-device-id> --target lib/main_mobile.dart
```

To auto-connect the mobile app to a daemon at launch, pass the remote URL and
token as Dart defines:

```bash
flutter run -d <ios-device-id> \
  --target lib/main_mobile.dart \
  --dart-define=YOLOIT_REMOTE_URL=http://127.0.0.1:43110 \
  --dart-define=YOLOIT_REMOTE_TOKEN=dev-token
```

For an iOS Simulator talking to a Docker daemon published on the Mac,
`127.0.0.1:<published-port>` reaches the Mac host. For a physical iPhone, use
the Mac or server LAN address instead.

For CI/build validation without signing:

```bash
flutter build ios --no-codesign --target lib/main_mobile.dart
```

The mobile app starts only the board client shell. It does not start the desktop
window manager, local CLI HTTP server, tmux bootstrap, or host run services.
Remote boards are connected from the board toolbar with `Connect remote YoLoIT`,
using the same daemon URL/token as the desktop client.

Widget availability is driven by `lib/core/remote/yoloitd_panel_catalog.dart`:

- local iOS boards expose only portable widgets
- remote iOS boards expose host-backed widgets through `yoloitd`
- the daemon remains the source of truth for remote panel actions and state

Example iOS-to-Docker flow:

```bash
docker build -f docker/Dockerfile.yoloitd -t yoloitd:dev .
docker run --rm -p 43110:43110 \
  -e YOLOITD_TOKEN=dev-token \
  -v yoloitd-data:/data \
  yoloitd:dev

flutter run -d <ios-device-id> \
  --target lib/main_mobile.dart \
  --dart-define=YOLOIT_REMOTE_URL=http://127.0.0.1:43110 \
  --dart-define=YOLOIT_REMOTE_TOKEN=dev-token
```

On a physical iPhone, connect to the Mac's LAN IP rather than `127.0.0.1`, for
example `http://192.168.1.20:43110`. If the daemon is on a remote machine, expose
the port through SSH forwarding, a private network, or a protected HTTPS reverse
proxy.

Known local build prerequisite: Xcode must have the iOS platform/runtime that
matches the connected device. If `xcodebuild -showdestinations` reports
`iOS <version> is not installed`, install that platform in
`Xcode > Settings > Components` before running to the device.

## Storage

The daemon stores data under `YOLOITD_DATA_DIR`:

```text
boards.json
active_board
boards_history/
  <board-id>/events/YYYY/MM/<op-id>_<actor-id>.json
```

`boards.json` is the current checkpoint. `boards_history` is append-only and is
used for history/undo. This mirrors the direction described in
`docs/board-architecture.md`: checkpoints are fast local state, and events are
the long-term sync primitive.

For multi-user editing, `metadata.historyRevision` is the server-side board
revision. UI clients store the last seen remote revision in local board metadata
and include it as `expectedRevision` when saving a remote board snapshot.

## API

```text
GET  /api/health
GET  /api/boards
POST /api/boards
GET  /api/boards/:id
PUT  /api/boards/:id
DELETE /api/boards/:id

GET  /api/boards/:id/panels
POST /api/boards/:id/panels
GET  /api/boards/:id/panel-types
GET  /api/boards/:id/panels/:panel
PUT  /api/boards/:id/panels/:panel
DELETE /api/boards/:id/panels/:panel
POST /api/boards/:id/panels/:panel/action

GET  /api/boards/:id/history
POST /api/boards/:id/undo

GET  /api/runs
POST /api/runs
GET  /api/runs/:id/log
POST /api/runs/:id/stop

GET  /api/files?path=<remote-directory>
```

When `--token`/`YOLOITD_TOKEN` is set, requests must include:

```text
Authorization: Bearer <token>
```

`PUT /api/boards/:id` accepts full board snapshots. When the request includes
`expectedRevision`, the daemon returns `409` if the server has a newer revision.

### Panel Type Capabilities

`GET /api/boards/:id/panel-types` returns one descriptor per built-in widget:

```json
{
  "type": "board.terminal",
  "displayName": "Terminal",
  "defaultSize": {"width": 520, "height": 360},
  "actions": ["config", "set-dir", "set-session"],
  "capabilities": {
    "localPlatforms": ["macos", "linux", "windows"],
    "remotePlatforms": ["macos", "linux", "windows", "ios"],
    "requiresNativeHost": true,
    "supportsRemoteState": true,
    "supportsHeadlessPreview": false
  }
}
```

The important distinction for iOS is:

- `localPlatforms` means the widget can run directly on the current device.
- `remotePlatforms` means the widget can be shown and controlled when the board
  is backed by `yoloitd`.
- `requiresNativeHost: true` means live work happens on the daemon machine:
  terminal processes, filesystem access, WebView/browser state, setup commands,
  run sessions, and similar host-bound behavior.

This lets an iOS client hide unsupported local widgets while still allowing the
same widgets on remote boards.

### Panel Actions

Use `POST /api/boards/:id/panels/:panel/action` to mutate a widget's declarative
state on the daemon. The request body always includes an `action` field plus
action-specific arguments:

```bash
curl -fsS \
  -H "Authorization: Bearer $YOLOITD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action":"set","shape":"diamond","text":"Decision"}' \
  "$YOLOITD_URL/api/boards/$BOARD_ID/panels/$PANEL_ID/action"
```

Supported examples:

```text
board.note.markdown: set, append, wrap, nowrap
board.sticky:        set, append, color
board.shape:         set
board.kanban:        add-column, rename-column, add-card, move-card, update-card
board.checklist:     add, check, uncheck, rename, remove
board.code.snippet:  set
board.webpage:       open
board.playlist:      add, play, pause, stop, next, prev
board.files:         open, add, remove, clear
board.file.preview:  open
board.filetree:      set-root, expand, collapse, open, refresh
board.terminal:      set-dir, set-session
board.chat:          config, send, messages, clear, status
board.setup_guide:   select, unselect, set-selected
board.run*:          set-group, select-session, clear-session
board.diff.preview:  set-root, open
board.yolo_assistant:set-mode, set-status, clear
board.widget.custom: set-widget, set-config, set
board.timer:         set, start, pause, resume, reset
```

Remote panel actions are intentionally state-first. They persist the panel state
that all connected clients render. Live side effects such as actually typing
into a terminal, running a setup install, or executing WebView JavaScript remain
separate daemon APIs because they target host processes rather than panel JSON.
