@echo off
echo Requesting Administrator (required for firewall + network profile)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"\"%~dp0setup_usb_tether_firewall.ps1\"\"'"
echo.
echo If a UAC window appeared, click Yes, then retry on phone:
echo   http://172.24.168.80:8000/admin/
pause
