#!/usr/bin/env bash
# Compare live-switch CLI captures vs offscreen renderer PNGs.
set -euo pipefail

YOLOIT="${YOLOIT:-$HOME/.config/yoloit/yoloit}"
OUT="${1:-/tmp/yolo/compare}"
LIVE="$OUT/live"
OFF="$OUT/offscreen"
PORT_FILE="${HOME}/.config/yoloit/cli.port"

mkdir -p "$LIVE" "$OFF"

boards=$("$YOLOIT" boards 2>/dev/null | python3 -c "
import json, sys, re
raw = sys.stdin.read()
try:
    data = json.loads(raw)
    boards = data.get('boards') or []
except json.JSONDecodeError:
    boards = []
for b in boards:
    if (b.get('panelCount') or 0) == 0:
        continue
    name = b['name']
    bid = b['id']
    slug = re.sub(r'[^a-zA-Z0-9]+', '-', name).strip('-').lower() or bid
    print(f\"{name}|{slug}|{bid}\")
")

if [[ -f "$PORT_FILE" ]]; then
  PORT=$(tr -d '[:space:]' < "$PORT_FILE")
  BASE="http://127.0.0.1:${PORT}/api"
else
  BASE=""
fi

echo "Output: $OUT"
printf "%-30s %10s %10s %8s\n" "Board" "Live(KB)" "Off(KB)" "Ratio"
echo "----------------------------------------------------------------"

while IFS='|' read -r name slug bid; do
  [[ -z "$name" ]] && continue
  live="$LIVE/${slug}.png"
  off="$OFF/${slug}.png"

  "$YOLOIT" board:screenshot "$name" "$live" >/dev/null

  if [[ -n "$BASE" ]]; then
    encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$bid'))")
    curl -sf "${BASE}/boards/${encoded}/screenshot?mode=offscreen" -o "$off" || rm -f "$off"
  fi

  live_bytes=$(stat -f%z "$live" 2>/dev/null || stat -c%s "$live")
  live_kb=$((live_bytes / 1024))
  if [[ -f "$off" ]]; then
    off_bytes=$(stat -f%z "$off")
    off_kb=$((off_bytes / 1024))
    ratio=$(python3 -c "print(f'{$live_kb/max($off_kb,1):.1f}x')")
  else
    off_kb="-"
    ratio="-"
  fi
  printf "%-30s %9sK %9sK %7s\n" "$name" "$live_kb" "$off_kb" "$ratio"
done <<< "$boards"

echo
echo "Live captures:      $LIVE"
echo "Offscreen captures: $OFF"
open "$OUT" 2>/dev/null || true
