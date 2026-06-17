#!/usr/bin/env bash
# Merge per-arch latest-mac-*.yml fragments into a single latest-mac.yml
# compatible with electron-updater / Squirrel.Mac clients.
set -euo pipefail

ARTIFACTS_DIR="${1:-.}"
OUTPUT="${2:-$ARTIFACTS_DIR/latest-mac.yml}"

ARM64_FILE=""
X64_FILE=""

for candidate in \
  "$ARTIFACTS_DIR/latest-mac-arm64.yml" \
  "$ARTIFACTS_DIR"/**/latest-mac-arm64.yml; do
  if [[ -f "$candidate" ]]; then
    ARM64_FILE="$candidate"
    break
  fi
done

for candidate in \
  "$ARTIFACTS_DIR/latest-mac-x64.yml" \
  "$ARTIFACTS_DIR"/**/latest-mac-x64.yml; do
  if [[ -f "$candidate" ]]; then
    X64_FILE="$candidate"
    break
  fi
done

if [[ -z "$ARM64_FILE" && -z "$X64_FILE" ]]; then
  echo "No latest-mac-*.yml fragments found under $ARTIFACTS_DIR" >&2
  exit 1
fi

python3 - "$ARM64_FILE" "$X64_FILE" "$OUTPUT" <<'PY'
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
  sys.stderr.write("PyYAML required: pip install pyyaml\n")
  sys.exit(1)

arm64_path, x64_path, output_path = sys.argv[1:4]
fragments = []
for path in (arm64_path, x64_path):
    if not path:
        continue
    p = Path(path)
    if not p.is_file():
        continue
    fragments.append(yaml.safe_load(p.read_text()))

if not fragments:
    raise SystemExit("No manifest fragments to merge")

merged_files = []
version = fragments[0].get("version")
release_date = fragments[0].get("releaseDate")
for fragment in fragments:
    version = fragment.get("version", version)
    release_date = fragment.get("releaseDate", release_date)
    merged_files.extend(fragment.get("files") or [])

if not version or not merged_files:
    raise SystemExit("Invalid manifest fragments")

primary = merged_files[0]
merged = {
    "version": str(version),
    "files": merged_files,
    "path": primary["url"],
    "sha512": primary["sha512"],
    "releaseDate": release_date,
}

Path(output_path).write_text(yaml.safe_dump(merged, sort_keys=False))
print(f"Wrote {output_path} with {len(merged_files)} file entries")
PY
