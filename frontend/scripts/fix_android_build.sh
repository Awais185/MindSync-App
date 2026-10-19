#!/usr/bin/env bash
# Repair Gradle caches and rebuild — checks disk space first.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

min_free_gb="${MIN_FREE_GB:-8}"
avail_kb="$(df -k /System/Volumes/Data 2>/dev/null | awk 'NR==2 {print $4}')"
if [[ -z "${avail_kb}" ]]; then
  avail_kb="$(df -k . | awk 'NR==2 {print $4}')"
fi
avail_gb=$((avail_kb / 1024 / 1024))
echo "==> Free disk: ~${avail_gb} GB (need at least ${min_free_gb} GB for Android debug build)"

if [[ "${avail_gb}" -lt "${min_free_gb}" ]]; then
  echo "ERROR: Disk almost full. Free space first, then re-run this script."
  echo "  Safe cleanups:"
  echo "    cd \"$ROOT\" && flutter clean"
  echo "    rm -rf \"\$HOME/.gradle/caches/9.3.1\" \"\$HOME/.gradle/caches/build-cache-1\""
  echo "    rm -rf \"\$HOME/.gradle/caches/8.14/transforms\" \"\$HOME/.gradle/caches/8.14/kotlin-dsl\""
  echo "  Empty Trash and remove old Xcode/Android SDK system images if needed."
  exit 1
fi

# Remove broken partial APK from failed copies (invalid manifest / aapt errors).
rm -f \
  "$ROOT/build/app/outputs/flutter-apk/app-debug.apk" \
  "$ROOT/build/app/outputs/apk/debug/app-debug.apk" 2>/dev/null || true

if [[ "${SKIP_FLUTTER_CLEAN:-0}" != "1" ]]; then
  echo "==> Flutter clean + pub get (set SKIP_FLUTTER_CLEAN=1 to skip)"
  flutter clean
fi
flutter pub get

echo "==> Stop Gradle daemons and clear broken caches"
if [[ -d "$ROOT/android" ]]; then
  (cd "$ROOT/android" && ./gradlew --stop) || true
fi
rm -rf "${HOME}/.gradle/caches/8.14/transforms" "${HOME}/.gradle/caches/8.14/kotlin-dsl"
rm -rf "$ROOT/android/.gradle"

echo "==> USB: map phone localhost:8000 -> Mac :8000 (ignore if no device)"
if command -v adb >/dev/null 2>&1; then
  adb reverse tcp:8000 tcp:8000 || true
fi

echo "==> Build debug APK (10–20 min after cache wipe)"
flutter build apk --debug

echo "Done. Run: flutter run"
