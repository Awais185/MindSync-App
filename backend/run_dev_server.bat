@echo off
cd /d "%~dp0"
if not exist "venv\Scripts\python.exe" (
  echo Missing venv. From this folder run:
  echo   python -m venv venv
  echo   venv\Scripts\python.exe -m pip install -r requirements.txt
  exit /b 1
)
call runserver.bat
