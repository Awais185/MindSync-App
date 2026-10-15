#!/usr/bin/env bash
# Physical Android + Django on this Mac (USB debugging).
set -euo pipefail
cd "$(dirname "$0")/.."

LAN_IP=""
for iface in en0 en1; do
  if command -v ipconfig >/dev/null 2>&1; then
    LAN_IP="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
    [[ -n "$LAN_IP" ]] && break
  fi
done

DART_DEFINES=()
if [[ -n "$LAN_IP" ]]; then
  DART_DEFINES+=(--dart-define=DEV_LAN_HOST="$LAN_IP")
  echo "LAN fallback: DEV_LAN_HOST=$LAN_IP (same Wi‑Fi, backend must bind 0.0.0.0:8000)"
fi

if command -v adb >/dev/null 2>&1; then
  adb reverse tcp:8000 tcp:8000 || true
  echo "adb reverse tcp:8000 tcp:8000 (phone 127.0.0.1:8000 → laptop :8000)"
else
  echo "adb not found — use Wi‑Fi only; start backend with: ./runserver.sh"
fi

flutter pub get
flutter run -d android "${DART_DEFINES[@]}"
