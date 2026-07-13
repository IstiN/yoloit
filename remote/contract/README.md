# yoloitd / yoloit-hub REST Contract

This directory holds the shared REST contract that **both** remote daemons
implement:

- `yoloitd` — the original Dart daemon (`bin/yoloitd.dart`, sources in
  `lib/core/remote/`, documented in `docs/remote-yoloitd.md`).
- `yoloit-hub` — the thin Go re-implementation in `remote/yoloit-hub/`
  (documented in `docs/remote-hub.md`).

The contract is the wire surface the Flutter desktop app and the `tools/yoloit`
CLI already speak: JSON envelopes (`{"ok": true, ...}` / `{"ok": false,
"error": ...}`), the `RemoteBoard` / `RemotePanel` / `RemoteHistoryEvent`
shapes from `lib/core/remote/yoloitd_models.g.dart`, token auth
(`Authorization: Bearer <token>` or `?token=`, open access when unset), the
on-disk store layout (`boards.json`, `active_board`,
`boards_history/<board-id>/events/YYYY/MM/<op-id>_<actor-id>.json`), and
optimistic concurrency via `expectedRevision` → `409` with
`currentRevision` + the authoritative board.

When the written spec and the Dart code disagree, the Dart code is the source
of truth (clients are already deployed against it).

## Fixtures

`fixtures/*.json` are golden request/response examples captured from a live
`yoloit-hub` instance:

- `health.json` — `GET /api/health`
- `board-create-response.json` — `POST /api/boards`
- `board-put-response.json` — `PUT /api/boards/:id` snapshot replace
- `board-get-response.json` — `GET /api/boards/:id` full board
- `board-revision-conflict.json` — `409` on stale `expectedRevision`
- `board-archive-response.json` — `POST /api/boards/:id/archive`
- `panel-types-excerpt.json` — first entries of `GET /api/boards/:id/panel-types`
- `board-snapshot.md` — `GET /api/boards/:id/snapshot` (text/plain)
- `panels-create-response.json` — `POST /api/boards/:id/panels`
- `panel-get-response.json` — `GET /api/boards/:id/panels/:panel` with
  `supportedActions` / `actionHelp` catalog enrichment
- `history-excerpt.json` — first events of `GET /api/boards/:id/history`
- `undo-response.json` — `POST /api/boards/:id/undo`
- `links-create-response.json` — `POST /api/boards/:id/links`
- `groups-create-response.json` — `POST /api/boards/:id/groups`

Timestamps, ids, and `dataDir` paths are obviously environment-specific;
treat shapes, field names, and status codes as the contract, not the values.

## Conformance testing

Today, conformance is enforced by each implementation's own test suite:

- Dart: `test/` coverage of `lib/core/remote/yoloitd_*.dart`.
- Go: `cd remote/yoloit-hub && go test ./...` (httptest-based contract tests:
  auth, CRUD, revision increment, 409 body keys, archive, panel-types,
  snapshot format, atomic store round-trip, history event file paths,
  panel CRUD + action dispatch, history ordering, undo/redo round-trips,
  links CRUD, groups CRUD/membership/move).

A cross-implementation smoke test against the golden fixtures is a planned
follow-up: boot either daemon, replay the fixture flow, and compare response
shapes.
