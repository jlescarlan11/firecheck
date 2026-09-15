#!/usr/bin/env bash
# Build smaller standalone APKs; fail if a package exceeds the size budget.
set -euo pipefail
cd "$(dirname "$0")/.."
# Each build keeps its own symbols for later crash symbolication.
symbol_dir="build/release-symbols/$(date -u +%Y%m%dT%H%M%SZ)-$$"
flutter build apk --release --split-per-abi --split-debug-info="$symbol_dir" "$@"
# Keep Java/Kotlin de-obfuscation data alongside the matching Dart symbols.
if [[ -f build/app/outputs/mapping/release/mapping.txt ]]; then
  cp build/app/outputs/mapping/release/mapping.txt "$symbol_dir/r8-mapping.txt"
fi
python3 tool/check_apk_size.py \
  build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk \
  build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  build/app/outputs/flutter-apk/app-x86_64-release.apk \
  --report "$symbol_dir/apk-size-report.json"
printf 'Archive APKs and matching symbols from %s together.\n' "$symbol_dir"
