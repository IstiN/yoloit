#!/bin/bash
# Start yoloit in debug mode on macOS.
#
# Hot reload / hot restart work through the run panel quick-action buttons
# (and `tmux send-keys` r / R): the script `exec`s flutter run so it inherits
# the session terminal as stdin — flutter_tools only installs its interactive
# key handler when stdin is a TTY (piping stdin into a FIFO silently disables
# the r/R/q keys).
set -e
cd "$(dirname "$0")"

export YOLOIT_PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

# xcode-select on this machine points at CommandLineTools, which has no
# xcodebuild — without this, `flutter run -d macos` fails at the Swift
# Package Manager resolution step. Point at the full Xcode when present.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

# This project needs Flutter 3.44.4. The Homebrew Flutter (3.47+) that comes
# first in a fresh login shell fails to compile flame_3d and force-migrates
# the macOS project to SwiftPM — prefer the pinned toolchain when present.
if [ -x "$HOME/development/flutter/bin/flutter" ]; then
  export PATH="$HOME/development/flutter/bin:$PATH"
fi

echo "🚀 Starting yoloit..."
echo "💡 Hot Reload / Hot Restart: run panel buttons or tmux send-keys r / R"

# exec: replace the shell so flutter's stdin is the session TTY itself.
exec flutter run -d macos --no-pub
