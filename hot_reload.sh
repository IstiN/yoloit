#!/bin/bash
# Hot reload the running yoloit app.
#
# run.sh `exec`s flutter run on the session TTY, so keys are delivered with
# tmux send-keys. The run panel Hot Reload button does the same thing.
# Sessions are matched by pane working directory so other projects' run
# sessions are never touched.

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -p /tmp/yoloit_flutter_stdin ]]; then
  # Legacy run.sh (pre-TTY setup): still supports the FIFO channel.
  echo "🔥 Hot reloading..."
  echo "r" > /tmp/yoloit_flutter_stdin
  echo "✅ Hot reload triggered."
  exit 0
fi

command -v tmux >/dev/null 2>&1 || { echo "❌ tmux not found"; exit 1; }

SESS="$(tmux list-panes -a -F '#{session_name}|#{pane_current_path}' 2>/dev/null \
  | grep -F "$REPO_DIR" | head -1 | cut -d'|' -f1)"
if [[ -z "$SESS" ]]; then
  echo "❌ No yoloit run session found (is the app running via run.sh?)"
  exit 1
fi

echo "🔥 Hot reloading ($SESS)..."
tmux send-keys -t "$SESS" r
echo "✅ Hot reload triggered."
