# Backend — single virtual environment

Use **only** this folder:

`MindSync/backend/venv/`

Do **not** create a `.venv` at the repo parent (`MindSync (1)/.venv`). That caused broken paths when switching Python 3.13 / 3.14.

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
