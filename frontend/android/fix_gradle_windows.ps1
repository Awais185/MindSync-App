# Run from repo:  powershell -ExecutionPolicy Bypass -File android/fix_gradle_windows.ps1
# Fixes: Gradle wrapper lock timeout, stale partial downloads, stuck daemons.
# For UnknownHostException (services.gradle.org): fix DNS/network first — see messages below.

$ErrorActionPreference = "Continue"
Write-Host "MindSync Gradle cleanup (Windows)" -ForegroundColor Cyan

# 1) Stop Gradle daemons so nothing holds the wrapper zip lock
$androidDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $androidDir
if (Test-Path ".\gradlew.bat") {
    Write-Host "Stopping Gradle daemons..."
    & .\gradlew.bat --stop 2>$null
}
Pop-Location

# 2) Kill orphaned Java processes ONLY if they're Gradle (optional — user can skip)
# Get-Process java -ErrorAction SilentlyContinue | Where-Object { ... } — too risky; skip.

# 3) Remove incomplete Gradle 8.14 wrapper downloads / lock files
$distsRoot = Join-Path $env:USERPROFILE ".gradle\wrapper\dists"
$patterns = @("gradle-8.14-bin", "gradle-8.14-all")
foreach ($p in $patterns) {
    $folder = Join-Path $distsRoot $p
    if (Test-Path $folder) {
        Write-Host "Removing stale wrapper folder: $folder" -ForegroundColor Yellow
        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "DNS check (services.gradle.org):" -ForegroundColor Cyan
try {
    $r = Resolve-DnsName services.gradle.org -ErrorAction Stop | Select-Object -First 1
    Write-Host "  OK: $($r.Name) -> $($r.IPAddress)" -ForegroundColor Green
} catch {
    Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Fix: reconnect Wi‑Fi, disable VPN briefly, set DNS to 8.8.8.8 / 1.1.1.1, run: ipconfig /flushdns" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Next: cd to frontend folder, then:  flutter run" -ForegroundColor Green
