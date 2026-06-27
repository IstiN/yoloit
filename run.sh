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
