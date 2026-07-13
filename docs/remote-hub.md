# YoLoIT Hub (`yoloit-hub`)

`yoloit-hub` is a thin Go re-implementation of the `yoloitd` REST contract
(see `docs/remote-yoloitd.md` for the full API reference). It exists so the
remote daemon can run anywhere Go runs — no Flutter/Dart SDK needed — while
existing clients (Flutter desktop app, iOS shell, `tools/yoloit` CLI) connect
unchanged.

- Code: `remote/yoloit-hub/` (standard library only, Go 1.25+).
- Contract fixtures: `remote/contract/`.
- Default port: **43111** (yoloitd: 43110) so both can run side by side.

## Relationship to yoloitd

Both daemons implement the same contract and use the **same on-disk store
layout** (`boards.json`, `active_board`, `boards_history/...`), so a data
directory can be moved between them. `yoloitd` remains the reference
implementation: where this document and the Dart code disagree, the Dart code
wins.

## Implemented (Phase 1-core)

- `GET /api`, `GET /api/health` (+ `watch: false` capability flag)
- `GET /` browser dashboard
- Board CRUD: `GET/POST /api/boards`, `GET/PUT/DELETE /api/boards/:id`
- `POST /api/boards/:id/archive`, `POST /api/boards/:id/unarchive`
- `GET /api/boards/:id/panel-types` (full static catalog mirrored from
  `lib/core/remote/yoloitd_panel_catalog.dart`)
- `GET /api/boards/:id/snapshot` (plain-text markdown table)
- `GET /api/boards/:id/history`, `POST /api/boards/:id/undo`,
  `POST /api/boards/:id/redo` (per-board in-memory redo stacks, lost on
  restart — same as yoloitd)
- Panel CRUD: `GET/POST /api/boards/:id/panels`,
  `GET/PUT/DELETE /api/boards/:id/panels/:panel` (GET includes
  `supportedActions` / `actionHelp` catalog enrichment)
- `POST /api/boards/:id/panels/:panel/action` — the state-only actions of
  `handleRemotePanelAction` (note/sticky/shape/kanban/checklist/code/webpage/
  playlist/files/filetree/terminal/timer/chat/setup_guide/run/table/calendar/
  chart/diff.preview/yolo_assistant/widget.custom). `board.ui` actions are
  NOT ported (they need `UiViewBindings`); they return yoloitd's
  unsupported-action envelope `400 {"ok": false, "message": "Unknown
  action: <action>"}`
- Links: `GET/POST /api/boards/:id/links`,
  `PUT/DELETE /api/boards/:id/links/:link`
- Groups: `GET/POST /api/boards/:id/groups`,
  `PUT/DELETE /api/boards/:id/groups/:group`,
  `POST/DELETE /api/boards/:id/groups/:group/panels` (ids in the body),
  `POST /api/boards/:id/groups/:group/move`
- Optimistic concurrency: `expectedRevision` → `409` with `currentRevision`
  and the authoritative board; `metadata.historyRevision` increments on every
  eventful mutation
- Append-only history event files for snapshot and panel mutations
  (`panel.created` / `panel.updated` / `panel.deleted` / `panel.restored` /
  `board.updated`); links and groups mutations are not eventful, like yoloitd
- Token auth identical to `isAuthorized()` (Bearer or `?token=`, open when unset)
- CORS middleware (configurable via `YOLOIT_HUB_CORS_ORIGINS`, default `*`) —
  additive; yoloitd has none

## Excluded (later phases)

`board.ui` panel actions, `/api/runs`, `/api/terminals`, `/api/files`,
`/api/setup`, `/api/templates`, and WebSocket board watch. Unimplemented
routes return the contract's `404 {"ok": false, "error": "not found"}`.

## Run / deploy

See `remote/yoloit-hub/README.md` for build, env vars, Docker, compose, and
client connection instructions.
