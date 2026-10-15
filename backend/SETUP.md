# Backend — single virtual environment

Use **only** this folder:

`MindSync/backend/venv/`

Do **not** create a `.venv` at the repo parent (`MindSync (1)/.venv`). That caused broken paths when switching Python 3.13 / 3.14.

## PostgreSQL (required)

The backend uses **PostgreSQL** for all Django data (users, tracking, subscriptions, chat, etc.). SQLite (`db.sqlite3`) is no longer used.

### Start database (Docker — recommended)

```bash
cd MindSync-App/backend
docker compose up -d
```

Defaults: database `mindsync`, user/password `mindsync`, port `5432`.

Copy `.env.example` → `.env` (includes `POSTGRES_*` variables) or set:

```bash
export POSTGRES_DB=mindsync
export POSTGRES_USER=mindsync
export POSTGRES_PASSWORD=mindsync
export POSTGRES_HOST=127.0.0.1
export POSTGRES_PORT=5432
```

### Install driver + create tables

```bash
source venv/bin/activate   # or venv\Scripts\activate on Windows
pip install 'psycopg[binary]>=3.1'
python manage.py migrate
python manage.py runserver
```

Optional superuser: `python manage.py createsuperuser`

### Remove old SQLite files (one-time)

If you still have `db.sqlite3` from an older setup, delete it after migrating to Postgres (data is not auto-copied):

```bash
rm -f db.sqlite3 db.sqlite3-wal db.sqlite3-shm
```

## Create or refresh `venv` (Windows / Git Bash)

Pick **one** Python on your PATH (e.g. 3.13 from the Microsoft Store, or `py -3.13`), then:

```bash
cd MindSync/backend
python -m venv venv --clear
./venv/Scripts/python.exe -m pip install --upgrade pip
./venv/Scripts/python.exe -m pip install -r requirements.txt
./venv/Scripts/python.exe manage.py migrate
./venv/Scripts/python.exe manage.py runserver
```

Always run Django with:

`backend\venv\Scripts\python.exe`

or activate first: `source venv/Scripts/activate` (Git Bash).

## Optional lighter install

If you cannot install PyTorch (large download), use `requirements-core.txt` instead of `requirements.txt` — emotion/video ML features may not work.

## macOS (Intel) + Python 3.12

Full `requirements.txt` may fail on **torch 2.12** / **tensorflow 2.21** pins. Use:

```bash
cd MindSync-App/backend
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements-macos-intel-py312.txt
python manage.py migrate
python manage.py runserver
```

If `requirements.txt` was saved as UTF-16 (pip shows `a\x00b\x00s\x00l\x00...`), re-save it as UTF-8 or run:

```bash
python3 -c "
p='requirements.txt'
open(p,'w',encoding='utf-8').write(open(p,'r',encoding='utf-16-le').read())
"
```

**Face identity match** — Android posts the unlock still to `POST /api/face/verify-track/` with the user’s JWT. The server compares the probe to **that user’s** enrolled `UserProfile.face_image` (embedding pipeline in `face_verification_service.py`). For reliable matches across lighting/angle, install ArcFace embeddings:

```bash
pip install -r requirements-face-insight.txt
```

Without InsightFace, OpenCV face-crop pixels are used (weaker; re-enroll after installing InsightFace).

Default match threshold is **80%** (`FACE_MATCH_THRESHOLD=0.80` on the server; Android sends `match_threshold=0.80`).

**Emotion model preload** warnings at startup are non-fatal. To skip them:

```bash
export MINDSYNC_SKIP_EMOTION_PRELOAD=1
```

**`no such table: tracking_videoclip`** — run `python manage.py migrate` before `runserver`.

## Environment (optional)

Copy `.env.example` → `.env`. Useful keys:

- `DJANGO_SECRET_KEY` — required in production (default insecure dev key otherwise)
- `DJANGO_DEBUG=false` — production
- `MINDSYNC_DISABLE_AUTO_WORKERS=1` — skip background video/OpenFace threads (CI, light dev)
- `MINDSYNC_SKIP_EMOTION_PRELOAD=1` — skip HF emotion model load at startup

## Smoke test

```bash
python manage.py check
python manage.py test website --verbosity=1
```
