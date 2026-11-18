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

# When configured on this checkout, publish the tested ARM64 build to Drive.
# Set FIRECHECK_UPLOAD_APK=0 for a local-only build.
if [[ "${FIRECHECK_UPLOAD_APK:-1}" != "0" && -f server/drive-gateway/.secrets/apk-release.json ]]; then
  server/drive-gateway/node_modules/.bin/tsx server/drive-gateway/tools/publish-apk.ts --apply
fi
