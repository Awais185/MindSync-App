@echo off
cd /d "%~dp0"
if not exist "venv\Scripts\python.exe" (
  echo Missing venv. Run: python -m venv venv
  echo Then: venv\Scripts\python.exe -m pip install -r requirements.txt
  exit /b 1
)
if "%~1"=="" (
  echo.
  echo  MindSync API — http://0.0.0.0:8000
  echo  PC USB tether IP: 172.24.168.80
  echo  Phone app URL:    http://127.0.0.1:8000  (run: adb reverse tcp:8000 tcp:8000)
  echo  Phone Chrome test: http://127.0.0.1:8000/admin/
  echo.
  venv\Scripts\python.exe manage.py runserver 0.0.0.0:8000
) else (
  venv\Scripts\python.exe manage.py runserver %*
)
