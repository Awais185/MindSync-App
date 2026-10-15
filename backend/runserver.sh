#!/usr/bin/env bash
# Bind all interfaces so physical phones can reach Django over Wi‑Fi (LAN).
# USB debugging still works with: adb reverse tcp:8000 tcp:8000
set -euo pipefail
cd "$(dirname "$0")"
if [[ -d venv ]]; then
  # shellcheck source=/dev/null
  source venv/bin/activate
fi
exec python manage.py runserver 0.0.0.0:8000
