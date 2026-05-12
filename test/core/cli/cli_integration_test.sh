#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
# CLI Integration Test
#
# Requires: YoLoIT app running in dev mode
# Tests all CLI commands against the live app.
# ──────────────────────────────────────────────────────────────────────
set -euo pipefail

PORT_FILE="${HOME}/.config/yoloit/cli.port"
PASS=0
FAIL=0
ERRORS=""

# ── Helpers ────────────────────────────────────────────────────────────

_port() {
  if [[ ! -f "$PORT_FILE" ]]; then
    echo "❌ YoLoIT not running (no $PORT_FILE)" >&2
    exit 1
  fi
  cat "$PORT_FILE"
}

BASE="http://127.0.0.1:$(_port)/api"

_get()    { curl -sf -X GET    "${BASE}$1" -H "Content-Type: application/json" 2>/dev/null; }
_post()   { curl -sf -X POST   "${BASE}$1" -H "Content-Type: application/json" -d "${2:-{}}" 2>/dev/null; }
_put()    { curl -sf -X PUT    "${BASE}$1" -H "Content-Type: application/json" -d "${2:-{}}" 2>/dev/null; }
_delete() { curl -sf -X DELETE "${BASE}$1" -H "Content-Type: application/json" 2>/dev/null; }

_encode() { python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1"; }

_assert_json_field() {
  local json=$1 field=$2 expected=$3 label=$4
  local actual
  actual=$(echo "$json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('$field','__MISSING__'))" 2>/dev/null || echo "__ERROR__")
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS+1))
    echo "  ✅ $label"
  else
    FAIL=$((FAIL+1))
    ERRORS+="  ❌ $label: expected '$expected', got '$actual'\n"
    echo "  ❌ $label (expected '$expected', got '$actual')"
  fi
}

_assert_ok() {
  local json=$1 label=$2
  _assert_json_field "$json" "ok" "True" "$label"
}

_assert_contains() {
  local json=$1 needle=$2 label=$3
  if echo "$json" | grep -q "$needle"; then
    PASS=$((PASS+1))
    echo "  ✅ $label"
  else
    FAIL=$((FAIL+1))
    ERRORS+="  ❌ $label: '$needle' not found\n"
    echo "  ❌ $label"
  fi
}

_assert_not_empty() {
  local json=$1 label=$2
  if [[ -n "$json" && "$json" != "{}" && "$json" != "[]" && "$json" != "null" ]]; then
    PASS=$((PASS+1))
    echo "  ✅ $label"
  else
    FAIL=$((FAIL+1))
    ERRORS+="  ❌ $label: response was empty\n"
    echo "  ❌ $label (empty response)"
  fi
}

echo "════════════════════════════════════════════════════════════"
echo " YoLoIT CLI Integration Tests"
echo " Server: $BASE"
echo "════════════════════════════════════════════════════════════"
echo ""

# ── 1. Board Commands ──────────────────────────────────────────────────

echo "── Board Commands ──"

# List boards
r=$(_get "/boards")
_assert_contains "$r" '"boards"' "GET /boards returns boards array"

# Create board
r=$(_post "/boards" '{"name":"__CLI_TEST_BOARD__"}')
_assert_ok "$r" "POST /boards creates board"
TEST_BOARD_ID=$(echo "$r" | python3 -c "import json,sys; print(json.load(sys.stdin)['board']['id'])" 2>/dev/null || echo "")
_assert_not_empty "$TEST_BOARD_ID" "Board ID returned"

BID=$(_encode "__CLI_TEST_BOARD__")

# Get board
r=$(_get "/boards/${BID}")
_assert_contains "$r" '__CLI_TEST_BOARD__' "GET /boards/:name returns board"

# Rename board
r=$(_put "/boards/${BID}" '{"name":"__CLI_TEST_RENAMED__"}')
_assert_ok "$r" "PUT /boards/:name renames board"

BID=$(_encode "__CLI_TEST_RENAMED__")

# Focus board
r=$(_put "/boards/${BID}" '{"focus":true}')
_assert_ok "$r" "PUT /boards/:name focus switches board"

# Snapshot
r=$(_get "/boards/${BID}/snapshot")
_assert_not_empty "$r" "GET /boards/:name/snapshot returns markdown"

echo ""

# ── 2. Panel Commands ─────────────────────────────────────────────────

echo "── Panel Commands ──"

# Create note panel
r=$(_post "/boards/${BID}/panels" '{"type":"board.note.markdown","title":"__TEST_NOTE__"}')
_assert_ok "$r" "POST panels creates note"
NOTE_ID=$(echo "$r" | python3 -c "import json,sys; print(json.load(sys.stdin)['panel']['id'])" 2>/dev/null || echo "")

# Create kanban panel
r=$(_post "/boards/${BID}/panels" '{"type":"board.kanban","title":"__TEST_KANBAN__"}')
_assert_ok "$r" "POST panels creates kanban"

# Create checklist panel
r=$(_post "/boards/${BID}/panels" '{"type":"board.checklist","title":"__TEST_CHECKLIST__"}')
_assert_ok "$r" "POST panels creates checklist"

# Create code snippet panel
r=$(_post "/boards/${BID}/panels" '{"type":"board.code.snippet","title":"__TEST_CODE__"}')
_assert_ok "$r" "POST panels creates code snippet"

# Create webpage panel
r=$(_post "/boards/${BID}/panels" '{"type":"board.webpage","title":"__TEST_WEBPAGE__"}')
_assert_ok "$r" "POST panels creates webpage"

# Create playlist panel
r=$(_post "/boards/${BID}/panels" '{"type":"board.playlist","title":"__TEST_PLAYLIST__"}')
_assert_ok "$r" "POST panels creates playlist"

# List panels
r=$(_get "/boards/${BID}/panels")
_assert_contains "$r" '"panels"' "GET panels returns panels array"

# Get panel details
PID=$(_encode "__TEST_NOTE__")
r=$(_get "/boards/${BID}/panels/${PID}")
_assert_contains "$r" 'board.note.markdown' "GET panel returns type"

# Rename panel
r=$(_put "/boards/${BID}/panels/${PID}" '{"title":"__TEST_NOTE_RENAMED__"}')
_assert_ok "$r" "PUT panel renames"
PID=$(_encode "__TEST_NOTE_RENAMED__")

# Move panel
r=$(_put "/boards/${BID}/panels/${PID}" '{"x":200,"y":300}')
_assert_ok "$r" "PUT panel moves"

# Resize panel
r=$(_put "/boards/${BID}/panels/${PID}" '{"width":500,"height":400}')
_assert_ok "$r" "PUT panel resizes"

echo ""

# ── 3. Panel Actions ──────────────────────────────────────────────────

echo "── Note Actions ──"
PID=$(_encode "__TEST_NOTE_RENAMED__")

r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"set","text":"# Test Note\n\nHello from CLI test"}')
_assert_ok "$r" "note: set content"

sleep 0.3
r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"get"}')
_assert_contains "$r" 'Test Note' "note: get returns content"

r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"append","text":"\n\n## Appended"}')
_assert_ok "$r" "note: append content"

echo ""
echo "── Kanban Actions ──"
PID=$(_encode "__TEST_KANBAN__")

r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"add-column","name":"Todo"}')
_assert_ok "$r" "kanban: add-column Todo"
TODO_COL=$(echo "$r" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('columnId',''))" 2>/dev/null || echo "")

r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"add-column","name":"Done"}')
_assert_ok "$r" "kanban: add-column Done"
DONE_COL=$(echo "$r" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('columnId',''))" 2>/dev/null || echo "")

sleep 0.3
r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"columns"}')
_assert_contains "$r" 'Todo' "kanban: columns lists Todo"

r=$(_post "/boards/${BID}/panels/${PID}/action" "{\"action\":\"add-card\",\"column\":\"Todo\",\"title\":\"Test Card\"}")
_assert_ok "$r" "kanban: add-card"
CARD_ID=$(echo "$r" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('cardId',''))" 2>/dev/null || echo "")

sleep 0.3
if [[ -n "$CARD_ID" && -n "$DONE_COL" ]]; then
  r=$(_post "/boards/${BID}/panels/${PID}/action" "{\"action\":\"move-card\",\"cardId\":\"${CARD_ID}\",\"to\":\"Done\"}")
  _assert_ok "$r" "kanban: move-card"
fi

r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"rename-column","column":"Todo","name":"Backlog"}')
_assert_ok "$r" "kanban: rename-column"

echo ""
echo "── Checklist Actions ──"
PID=$(_encode "__TEST_CHECKLIST__")

r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"add","text":"Buy milk"}')
_assert_ok "$r" "checklist: add item"

sleep 0.3
r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"check","index":0}')
_assert_ok "$r" "checklist: check item"

r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"uncheck","index":0}')
_assert_ok "$r" "checklist: uncheck item"

r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"rename","index":0,"text":"Buy eggs"}')
_assert_ok "$r" "checklist: rename item"

r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"items"}')
_assert_contains "$r" 'Buy eggs' "checklist: items returns renamed"

echo ""
echo "── Code Snippet Actions ──"
PID=$(_encode "__TEST_CODE__")

r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"set","code":"print(42)","language":"python"}')
_assert_ok "$r" "code: set code"

sleep 0.3
r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"get"}')
_assert_contains "$r" 'print(42)' "code: get returns code"

echo ""
echo "── Webpage Actions ──"
PID=$(_encode "__TEST_WEBPAGE__")

r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"open","url":"https://example.com"}')
_assert_ok "$r" "webpage: open URL"

sleep 0.3
r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"get"}')
_assert_contains "$r" 'example.com' "webpage: get returns URL"

echo ""
echo "── Playlist Actions ──"
PID=$(_encode "__TEST_PLAYLIST__")

r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"add","path":"/music/test.mp3","title":"Test Song"}')
_assert_ok "$r" "playlist: add track"

sleep 0.3
r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"list"}')
_assert_contains "$r" 'Test Song' "playlist: list shows track"

r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"play","index":0}')
_assert_ok "$r" "playlist: play"

r=$(_post "/boards/${BID}/panels/${PID}/action" '{"action":"pause"}')
_assert_ok "$r" "playlist: pause"

echo ""

# ── 4. Link Commands ──────────────────────────────────────────────────

echo "── Link Commands ──"

# Get panel IDs for linking
PANELS_JSON=$(_get "/boards/${BID}/panels")
FIRST_PID=$(echo "$PANELS_JSON" | python3 -c "import json,sys; ps=json.load(sys.stdin)['panels']; print(ps[0]['id'])" 2>/dev/null || echo "")
SECOND_PID=$(echo "$PANELS_JSON" | python3 -c "import json,sys; ps=json.load(sys.stdin)['panels']; print(ps[1]['id'])" 2>/dev/null || echo "")

if [[ -n "$FIRST_PID" && -n "$SECOND_PID" ]]; then
  r=$(_post "/boards/${BID}/links/${FIRST_PID}/${SECOND_PID}")
  _assert_ok "$r" "POST link creates link"

  r=$(_get "/boards/${BID}/links")
  _assert_contains "$r" "$FIRST_PID" "GET links returns created link"

  r=$(_delete "/boards/${BID}/links/${FIRST_PID}/${SECOND_PID}")
  _assert_ok "$r" "DELETE link removes link"
else
  echo "  ⚠️  Skipping link tests (no panel IDs)"
fi

echo ""

# ── 5. Cleanup ────────────────────────────────────────────────────────

echo "── Cleanup ──"

# Delete all test panels
PANELS_JSON=$(_get "/boards/${BID}/panels")
PANEL_IDS=$(echo "$PANELS_JSON" | python3 -c "
import json,sys
ps = json.load(sys.stdin)['panels']
for p in ps:
    print(p['id'])
" 2>/dev/null || echo "")

for pid in $PANEL_IDS; do
  _delete "/boards/${BID}/panels/${pid}" >/dev/null 2>&1 || true
done
echo "  🧹 Deleted test panels"

# Delete test board
BID2=$(_encode "__CLI_TEST_RENAMED__")
_delete "/boards/${BID2}" >/dev/null 2>&1 || true
echo "  🧹 Deleted test board"

echo ""
echo "════════════════════════════════════════════════════════════"
echo " Results: $PASS passed, $FAIL failed"
echo "════════════════════════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
  exit 1
fi
