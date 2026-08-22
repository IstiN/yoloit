#!/bin/bash
# Start yoloit in debug mode on macOS
# hot_reload.sh uses the FIFO pipe to send commands to flutter run

set -e
cd "$(dirname "$0")"

FIFO="/tmp/yoloit_flutter_stdin"
VM_FILE="/tmp/yoloit_vm_url.txt"

# Clean up old FIFO
rm -f "$FIFO"
mkfifo "$FIFO"

# Open the FIFO read+write so `flutter run <&3` does not block waiting for a
# separate writer (hot_reload.sh opens the pipe briefly to send "r").
exec 3<>"$FIFO"

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
echo "💡 Use ./hot_reload.sh to hot reload"

# Run flutter reading from FIFO and capture VM URL
# --no-pub skips `flutter pub get` on every launch (run `flutter pub get`
# manually when pubspec.yaml changes).  This saves ~3-5 s per restart.
flutter run -d macos --no-pub <&3 2>&1 | tee /tmp/yoloit_flutter_log.txt | while IFS= read -r line; do
  echo "$line"
  if [[ "$line" == *"Dart VM Service on macOS is available at:"* ]]; then
    url="${line##*at: }"
    echo "$url" > "$VM_FILE"
    echo "💾 VM URL saved → $VM_FILE"
  fi
done

exec 3>&-
rm -f "$FIFO"
