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

`PUT /api/boards/:id` accepts full board snapshots. When the request includes
`expectedRevision`, the daemon returns `409` if the server has a newer revision.
