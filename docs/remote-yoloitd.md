# YoLoIT Remote Daemon

`yoloitd` is the headless YoLoIT daemon for remote workspaces, Codespaces, and
containers. It exposes a YoLoIT-compatible `/api` surface without starting the
Flutter desktop window.

Current MVP scope:

- board list/create/read/update/delete
- panel list/create/read/update/delete
- append-only panel history
- `board:undo`
- simple run process API
- token auth
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

## Docker

```bash
docker build -f docker/Dockerfile.yoloitd -t yoloitd:dev .
docker run --rm -p 43110:43110 \
  -e YOLOITD_TOKEN=dev-token \
  -v yoloitd-data:/data \
  yoloitd:dev
```

For Codespaces, expose/forward port `43110`, then connect from the local YoLoIT
CLI or desktop client using the forwarded URL and token.

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
GET  /api/boards/:id/panels/:panel
PUT  /api/boards/:id/panels/:panel
DELETE /api/boards/:id/panels/:panel

GET  /api/boards/:id/history
POST /api/boards/:id/undo

GET  /api/runs
POST /api/runs
GET  /api/runs/:id/log
POST /api/runs/:id/stop
```

When `--token`/`YOLOITD_TOKEN` is set, requests must include:

```text
Authorization: Bearer <token>
```
