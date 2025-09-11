# ComfyUI (Fork) — Customised, Git‑Tracked, External Data Layout

This repository is my **customised ComfyUI** setup on Windows with:
- **System Python** (no embedded Python) for full control.
- **ComfyUI Manager** installed as a **Git submodule** under `ComfyUI/custom_nodes/comfyui-manager` so it can self‑update.
- **Large/volatile data** stored **outside** the repo in `E:\ComfyUI_data` (models, outputs, user, extra nodes).
- A simple **launcher BAT** that runs ComfyUI via `.\ComfyUI\main.py` and redirects outputs.

> Repo root on this machine: `E:\ComfyUI_windows_portable`  
> System Python: `C:\Users\justi\AppData\Local\Programs\Python\Python310\python.exe`

---

## 1) Prereqs (one‑time)
- Install **Git for Windows** and **Python 3.10+**.
- Install a matching **PyTorch** (GPU/CPU) for your setup (see PyTorch install page), then:
  ```bat
  pip install -r ComfyUI/requirements.txt
  ```

---

## 2) External data layout (NOT in Git)
All heavy data lives in `E:\ComfyUI_data`:

```
E:\ComfyUI_data\
├─ models\
│  ├─ checkpoints\
│  ├─ vae\
│  ├─ loras\
│  ├─ controlnet\
│  ├─ embeddings\
│  └─ upscale_models\
├─ outputs\
│  └─ temp\
├─ user\                  # profiles, saved workflows, configs
└─ custom_nodes_extra\    # optional extra custom nodes (not tracked in Git)
```

---

## 3) Repo layout (Git‑tracked)
```
E:\ComfyUI_windows_portable\
├─ ComfyUI\               # core ComfyUI sources
│  ├─ main.py
│  ├─ requirements.txt               
│  └─ custom_nodes\
│     └─ comfyui-manager\   # ComfyUI Manager (Git submodule)
├─ extra_model_paths.yaml   # maps external model/node dirs
├─ run_cpu_MasterPython_wrapper.bat   # launcher (uses .\ComfyUI\main.py)
├─ logs\                    # created at runtime by launcher
└─ .gitignore, README.md, .gitmodules, etc.
```

> **Note:** We deliberately use `.\ComfyUI\main.py` (not a root `main.py`).

---

## 4) extra_model_paths.yaml
This file makes ComfyUI look in `E:\ComfyUI_data` for models and extra custom nodes.

```yaml
external:
  base_path: "E:/ComfyUI_data"
  checkpoints: "models/checkpoints"
  vae: "models/vae"
  loras: "models/loras"
  controlnet: "models/controlnet"
  embeddings: "models/embeddings"
  upscale_models: "models/upscale_models"
  custom_nodes: "custom_nodes_extra"
```

Place this file **in the repo root** so ComfyUI auto‑loads it on start.

---

## 5) Launcher (Windows BAT)
Use `run_cpu_MasterPython_wrapper.bat` in repo root. It:
- Forces **system Python**
- Runs `.\ComfyUI\main.py`
- Passes `--user-directory`, `--output-directory`, `--temp-directory` to point at your external data

Typical command used inside the BAT:
```bat
"C:\Users\justi\AppData\Local\Programs\Python\Python310\python.exe" -u -s ".\ComfyUI\main.py" ^
  --user-directory "E:\ComfyUI_data\user" ^
  --output-directory "E:\ComfyUI_data\outputs" ^
  --temp-directory "E:\ComfyUI_data\outputs\temp"
```

> The BAT also writes timestamped logs to `.\logs\`. If you prefer console‑only, remove the redirections.

---

## 6) ComfyUI Manager (submodule)
Add once (path is **under `ComfyUI/custom_nodes`**):
```bash
git submodule add https://github.com/ltdrdata/ComfyUI-Manager.git ComfyUI/custom_nodes/comfyui-manager
git commit -m "Add ComfyUI Manager submodule"
```

**If you previously added it to the wrong path** (e.g. `custom_nodes/comfyui-manager` at repo root), move it cleanly:
```bash
# from repo root
git submodule deinit -f custom_nodes/comfyui-manager
git rm -f custom_nodes/comfyui-manager
rd /s /q .git\modules\custom_nodes\comfyui-manager  2>nul

git submodule add https://github.com/ltdrdata/ComfyUI-Manager.git ComfyUI/custom_nodes/comfyui-manager
git commit -m "Re-add Manager submodule under ComfyUI/custom_nodes"
```

**Update Manager** (either way):
- In UI: **Manager → Update** (then commit the submodule pointer):
  ```bash
  git add ComfyUI/custom_nodes/comfyui-manager
  git commit -m "Update Manager submodule"
  ```
- Or CLI:
  ```bash
  cd ComfyUI/custom_nodes/comfyui-manager
  git pull
  cd ../../..
  git add ComfyUI/custom_nodes/comfyui-manager
  git commit -m "Update Manager submodule"
  ```

**Fresh clone** with submodules:
```bash
git clone --recurse-submodules <your-fork-url> ComfyUI_windows_portable
```

---

## 7) Updating ComfyUI core
```bash
git remote add upstream https://github.com/comfyanonymous/ComfyUI.git  (once)
git fetch upstream
git merge upstream/master
pip install -r ComfyUI/requirements.txt
```

---

## 8) Rebuild from scratch (checklist)
1. Install Git + Python
2. `git clone --recurse-submodules <your-fork>`
3. Install PyTorch, then `pip install -r ComfyUI/requirements.txt`
4. Create `E:\ComfyUI_data\` with subfolders shown above
5. Put models into `E:\ComfyUI_data\models\...`
6. Put saved workflows into `E:\ComfyUI_data\user\...` (optional)
7. Verify `extra_model_paths.yaml` in repo root (see above)
8. Launch `run_cpu_MasterPython_wrapper.bat`

---

## 9) Notes
- This repo **intentionally** excludes models/outputs/user from Git.
- `extra_model_paths.yaml` is **tracked** so the mapping is portable.
- You can keep **extra custom nodes** in `E:\ComfyUI_data\custom_nodes_extra`.
- To symlink instead of YAML, use `mklink /J` (Admin) from repo to `E:\ComfyUI_data\...`.
