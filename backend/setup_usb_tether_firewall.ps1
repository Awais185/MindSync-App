# Run as Administrator (right-click -> Run with PowerShell as Admin)
# Fixes: phone cannot open http://172.24.168.80:8000 on USB tethering

$ErrorActionPreference = "Stop"

Write-Host "MindSync USB tether setup" -ForegroundColor Cyan

# 1) USB tether adapter is often "Public" -> Windows blocks inbound port 8000
$iface = "Ethernet 5"
$profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceAlias -eq $iface }
if ($profiles) {
    Set-NetConnectionProfile -InterfaceAlias $iface -NetworkCategory Private
    Write-Host "Set '$iface' network category to Private." -ForegroundColor Green
} else {
    Write-Host "Adapter '$iface' not found. Current adapters:" -ForegroundColor Yellow
    Get-NetConnectionProfile | Format-Table InterfaceAlias, NetworkCategory
    Write-Host "If your USB tether uses another name, run:" -ForegroundColor Yellow
    Write-Host '  Set-NetConnectionProfile -InterfaceAlias "YOUR_NAME" -NetworkCategory Private'
}

# 2) Allow inbound TCP 8000 (all profiles)
$ruleName = "MindSync Django 8000"
$existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($existing) {
    Remove-NetFirewallRule -DisplayName $ruleName
}
New-NetFirewallRule -DisplayName $ruleName `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort 8000 `
    -Profile Any `
    -Enabled True | Out-Null
Write-Host "Firewall rule added: inbound TCP 8000" -ForegroundColor Green

# 3) Allow Python (venv) if present
$py = Join-Path $PSScriptRoot "venv\Scripts\python.exe"
if (Test-Path $py) {
    $pyRule = "MindSync Python venv"
    Get-NetFirewallRule -DisplayName $pyRule -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName $pyRule `
        -Direction Inbound `
        -Action Allow `
        -Program $py `
        -Profile Any `
        -Enabled True | Out-Null
    Write-Host "Firewall rule added for: $py" -ForegroundColor Green
}

Write-Host ""
Write-Host "On your phone Chrome, open:" -ForegroundColor Cyan
Write-Host "  http://172.24.168.80:8000/admin/" -ForegroundColor White
Write-Host ""
Write-Host "Backend (other window):" -ForegroundColor Cyan
Write-Host "  python manage.py runserver 0.0.0.0:8000" -ForegroundColor White
