# Starts Django on :8000 and (optionally) launches ngrok if available in PATH.
#
# Mobile app:
# - Set EXPO_PUBLIC_API_URL to the ngrok https URL + /api (no trailing slash), OR
# - Set app.json -> expo.extra.API_URL
#
# Example:
#   $env:EXPO_PUBLIC_API_URL="https://xxxx.ngrok-free.app/api"

$ErrorActionPreference = "Stop"

$backendRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

Write-Host "Starting Django on http://127.0.0.1:8000 (backend: $backendRoot) ..."
Start-Process -NoNewWindow -FilePath "python" -ArgumentList @("manage.py","runserver","0.0.0.0:8000") -WorkingDirectory $backendRoot

$ngrok = Get-Command ngrok -ErrorAction SilentlyContinue
if ($null -ne $ngrok) {
  Write-Host "Starting ngrok tunnel to localhost:8000 ..."
  Start-Process -NoNewWindow -FilePath "ngrok" -ArgumentList @("http","8000")
} else {
  Write-Host "ngrok not found in PATH. Install ngrok and run: ngrok http 8000"
}
