# yoloitd — YoLoIT Terminal Runtime Daemon

Go replacement for the Python `yoloit_runtime.py` PTY proxy.

## Why Go?

- `github.com/creack/pty` works out-of-the-box on macOS/Linux/Windows
- Goroutines make concurrent session handling trivial
- Single static binary, easy to bundle with Flutter app
- UTF-8 incremental decoding built-in (no broken multi-byte chars across read chunks)

## Project layout

```
.
├── main.go          # entry point, signal handling, home dir logic
├── server/          # session registry (create/get/list/kill)
├── session/         # PTY lifecycle, ring buffer, subscribers, UTF-8 decoder
└── handler/         # HTTP routes (NDJSON streaming, JSON API)
```

## Run locally

```bash
cd tools/yoloitd
go mod tidy
go run . --home ~/.config/yoloit-dev/runtime
```

## Run tests

```bash
cd tools/yoloitd
go test ./...
```

## Build release binary

```bash
# macOS ARM64
cd tools/yoloitd
GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o yoloitd-darwin-arm64

# macOS AMD64
GOOS=darwin GOARCH=amd64 go build -ldflags="-s -w" -o yoloitd-darwin-amd64

# Linux AMD64
GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o yoloitd-linux-amd64
```

## API

Same as the Python runtime:

- `GET  /health`
- `GET  /sessions`
- `POST /sessions`
- `GET  /sessions/:id/stream?replay=1`
- `POST /sessions/:id/input`
- `POST /sessions/:id/resize`
- `POST /sessions/:id/kill`
