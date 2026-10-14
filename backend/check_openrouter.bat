@echo off
REM Quick check: is OPENROUTER_API_KEY loaded and does chat API respond?
cd /d "%~dp0"
if not exist "venv\Scripts\python.exe" (
  echo Run from backend folder with venv installed.
  exit /b 1
)
venv\Scripts\python.exe -c "import os,django; os.environ.setdefault('DJANGO_SETTINGS_MODULE','backend.settings'); django.setup(); from django.conf import settings; k=settings.OPENROUTER_API_KEY; print('Key loaded:', bool(k), ('prefix '+k[:12]+'...') if k else 'MISSING — fix backend/.env'); import urllib.request,json,urllib.error; 
assert k, 'No key'
req=urllib.request.Request('https://openrouter.ai/api/v1/chat/completions', data=json.dumps({'model':'openai/gpt-4o-mini','messages':[{'role':'user','content':'ping'}],'max_tokens':3}).encode(), method='POST', headers={'Authorization':'Bearer '+k,'Content-Type':'application/json','HTTP-Referer':'http://localhost:8000','X-Title':'MindSync'});
try:
 r=urllib.request.urlopen(req,timeout=30); print('OpenRouter chat test: HTTP', r.status, 'OK')
except urllib.error.HTTPError as e:
 print('OpenRouter chat test: HTTP', e.code); print(e.read().decode()[:300])"
