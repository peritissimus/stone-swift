#!/usr/bin/env bash
# Definition of done: package tests, architecture lint, and a warning-free app build.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
(cd "$root/Packages/StoneKit" && swift test)
"$root/Scripts/lint-architecture.sh"
(cd "$root" && xcodegen generate >/dev/null && xcodebuild -project Stone.xcodeproj -scheme Stone \
  -configuration Debug -derivedDataPath build -destination 'platform=macOS' build -quiet)
echo "✔ all checks passed"
