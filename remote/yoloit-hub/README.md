# yoloit-hub

A thin Go re-implementation of the YoLoIT remote daemon (`yoloitd`) REST
contract. The Flutter desktop app and the `tools/yoloit` CLI connect to it
without any client-side changes: point them at the hub URL instead of the Dart
daemon.

- Standard library only (`net/http`, Go 1.22+ method/path patterns). No
  third-party dependencies.
- Same on-disk layout as `yoloitd`, so data directories are interchangeable:
  `boards.json`, `active_board`, and append-only history events under
  `boards_history/<board-id>/events/YYYY/MM/`.
- Same auth semantics: optional shared token via `Authorization: Bearer
  <token>` or `?token=` query param; open access when no token is configured.

Default port is **43111** (yoloitd uses 43110), so both can run side by side.

## Run

Requires Go 1.25+.

```bash
cd remote/yoloit-hub
go run . \
  -host 127.0.0.1 \
  -port 43111 \
  -data-dir ~/.local/share/yoloit-hub \
  -token dev-token
```

## Build

```bash
cd remote/yoloit-hub
go build -o yoloit-hub .
./yoloit-hub -data-dir /tmp/hub-data -token dev-token
```

## Test

```bash
cd remote/yoloit-hub
go vet ./... && go test ./...
gofmt -l .   # must print nothing
```

## Configuration

Environment variables with CLI flag overrides (flags win):

| Env var                   | Flag             | Default                      | Meaning                                        |
|---------------------------|------------------|------------------------------|------------------------------------------------|
| `YOLOIT_HUB_HOST`         | `-host`          | `127.0.0.1`                  | Listen host. Use `0.0.0.0` in containers.      |
| `YOLOIT_HUB_PORT`         | `-port`          | `43111`                      | Listen port (yoloitd: 43110).                  |
| `YOLOIT_HUB_DATA_DIR`     | `-data-dir`      | `~/.local/share/yoloit-hub`  | Boards/history storage directory.              |
| `YOLOIT_HUB_TOKEN`        | `-token`         | *(empty = open access)*      | Shared bearer token. Set one for any network exposure. |
| `YOLOIT_HUB_ACTOR`        | `-actor`         | `yoloit-hub`                 | Actor id recorded in history event files.      |
| `YOLOIT_HUB_CORS_ORIGINS` | `-cors-origins`  | `*`                          | Comma-separated allowed origins for CORS.      |

## Docker

```bash
cd remote/yoloit-hub
docker build -t yoloit-hub:dev .
docker run --rm -p 43111:43111 \
  -e YOLOIT_HUB_TOKEN=dev-token \
  -v yoloit-hub-data:/data \
  yoloit-hub:dev
```

Compose stack (token is **required** — compose fails fast without it):

```bash
cp yoloit-hub.env.example yoloit-hub.env
$EDITOR yoloit-hub.env   # set a strong YOLOIT_HUB_TOKEN
docker compose --env-file yoloit-hub.env -f compose.yml up -d --build
```

## Exposing the service

Never expose an untokenized hub beyond localhost. With a strong token set:

```bash
# SSH port-forward (no public exposure)
ssh -L 43111:127.0.0.1:43111 user@remote-host

# Tailscale (private mesh)
tailscale serve 43111

# Cloudflare tunnel (public URL; keep the token!)
cloudflared tunnel --url http://127.0.0.1:43111
```

## Connecting clients

Desktop app: open the board toolbar `Remote` action (or board menu →
`Connect remote YoLoIT`), enter `http://<host>:43111` and the token.

CLI:

```bash
tools/yoloit remote:connect http://127.0.0.1:43111 dev-token
tools/yoloit boards
tools/yoloit board:create "Remote Board"
tools/yoloit remote:disconnect
```

Or via environment:

```bash
YOLOIT_REMOTE_URL=http://127.0.0.1:43111 \
YOLOIT_REMOTE_TOKEN=dev-token \
tools/yoloit boards
```

## Implemented in this phase

```text
GET    /api                     service identity envelope
GET    /api/health              health + dataDir (+ watch:false capability flag)
GET    /                        tiny browser dashboard
GET    /api/boards              list summaries (?includeArchived=true)
POST   /api/boards              create board
GET    /api/boards/:id          full board JSON
PUT    /api/boards/:id          snapshot replace w/ expectedRevision → 409 on conflict
DELETE /api/boards/:id          delete board
POST   /api/boards/:id/archive
POST   /api/boards/:id/unarchive
GET    /api/boards/:id/panel-types   static capability catalog
GET    /api/boards/:id/snapshot      plain-text markdown table
GET    /api/boards/:id/history       full event log
POST   /api/boards/:id/undo          revert latest panel-history event
POST   /api/boards/:id/redo          replay (in-memory redo stack)
GET    /api/boards/:id/panels        list panels
POST   /api/boards/:id/panels        create panel
GET    /api/boards/:id/panels/:p     panel JSON + supportedActions/actionHelp
PUT    /api/boards/:id/panels/:p     update panel
DELETE /api/boards/:id/panels/:p     delete panel
POST   /api/boards/:id/panels/:p/action   state-only panel actions
GET    /api/boards/:id/links         list links
POST   /api/boards/:id/links         create link
PUT    /api/boards/:id/links/:l      update link
DELETE /api/boards/:id/links/:l      delete link
GET    /api/boards/:id/groups        list groups
POST   /api/boards/:id/groups        create group
PUT    /api/boards/:id/groups/:g     update group
DELETE /api/boards/:id/groups/:g     delete group
POST   /api/boards/:id/groups/:g/panels   add panels (ids in body)
DELETE /api/boards/:id/groups/:g/panels   remove panels (ids in body)
POST   /api/boards/:id/groups/:g/move     reorder/move group
```

Runs, terminals, files, setup, templates, `board.ui` actions, and the
WebSocket watch channel are intentionally excluded (native-host features or
later phases); those routes return the contract's
`404 {"ok": false, "error": "not found"}`.

## Relay mode (device → hub reverse tunnel)

A Mac running YoLoIT can share its boards without any inbound connectivity:
it dials **out** to the hub over a WebSocket, and clients reach it through
the hub. The hub stays thin — it routes, the Mac executes against its live
board state.

```text
POST   /api/devices                 create device → {deviceId, key} (hub token)
GET    /api/devices                 list devices with online status (hub token)
DELETE /api/devices/:id             revoke device (hub token)
GET    /api/relay/connect?deviceId  WS upgrade, auth: Bearer <device key>
ALL    /api/devices/:id/*           proxied to the device over its WS
```

Client base URL for a relayed device is `https://<hub>/api/devices/<id>` —
the existing `YoloitRemoteClient` works unchanged. Instead of POST, a
pre-shared static device can be configured via env
(`YOLOIT_HUB_DEVICE_KEY` / `YOLOIT_HUB_DEVICE_ID` / `YOLOIT_HUB_DEVICE_NAME`),
which survives Cloud Run redeploys.

See `docs/remote-hub.md` and `remote/contract/README.md` for contract details
and golden fixtures.
