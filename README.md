# ComfyUI (Fork) — Windows portable, external data, Git-friendly

This is **my fork of ComfyUI** (origin: `justinthenick/ComfyUI`, upstream: `comfyanonymous/ComfyUI`) configured for a **portable Windows** workflow:

- **External data** lives in `E:\ComfyUI_data\` (models, outputs, user profiles).
- **ComfyUI-Manager** is a **standalone Git repo** at `ComfyUI/custom_nodes/ComfyUI-Manager` so it can **self-update from the UI** (not tracked by this fork).
- **Launchers** (`Run-ComfyUI.bat` + `Run-ComfyUI.ps1`) run via **my venv** or system Python and tee logs.
- **VS Code + GitLens** for easy rebase on upstream and task-based workflows.

> Repo root: `E:\ComfyUI_windows_portable`  
> External data root: `E:\ComfyUI_data`  
> Python: prefer `.venv\Scripts\python.exe` (3.10/3.11)

---

## 1) External data layout (not in Git)

```
E:\ComfyUI_data\
├─ models\
│  ├─ checkpoints\  ├─ vae\  ├─ loras\  ├─ controlnet\  ├─ embeddings\  └─ upscale_models\
├─ outputs\
│  └─ temp\
└─ user\                 # profiles, workflows, configs
```

(You can also keep extra custom nodes here if you like: `E:\ComfyUI_data\custom_nodes_extra\`)

---

## 2) extra_model_paths.yaml (repo root)

```yaml
external:
  base_path: "E:/ComfyUI_data"
  checkpoints: "models/checkpoints"
  vae: "models/vae"
  loras: "models/loras"
  controlnet: "models/controlnet"
  embeddings: "models/embeddings"
  upscale_models: "models/upscale_models"
```

This keeps the repo lean; ComfyUI discovers models under `E:\ComfyUI_data`.

---

## 3) Launching ComfyUI

Use the provided launchers:

- **Run-ComfyUI.bat** → calls **Run-ComfyUI.ps1** → prefers `.venv\Scripts\python.exe`, falls back to `py` or `python`, tees output to `.\logs\comfyui_YYYYMMDD_HHMMSS.log`.

Direct run (from repo root) if needed:
```powershell
.\.venv\Scripts\python.exe .\ComfyUI\main.py --windows-standalone-build `
  --user-directory   "E:\ComfyUI_data\user" `
  --output-directory "E:\ComfyUI_data\outputs" `
  --temp-directory   "E:\ComfyUI_data\outputs\temp" `
  --port 8188
```

> Remove `--cpu` in the launcher if you’re using GPU.

---

## 4) Python deps (venv)

```powershell
.\.venv\Scripts\python.exe -m pip install --upgrade pip wheel setuptools
.\.venv\Scripts\python.exe -m pip install -r .\ComfyUI\requirements.txt
Get-ChildItem ".\ComfyUI\custom_nodes" -Recurse -Filter requirements.txt |
  % { .\.venv\Scripts\python.exe -m pip install -r $_.FullName }
```

---

## 5) ComfyUI-Manager (standalone repo under custom_nodes)

Clone once (already done):
```powershell
git -C .\ComfyUI\custom_nodes clone git@github.com:Comfy-Org/ComfyUI-Manager.git
```

Update:
- **In the UI** (preferred): Manager → Update
- **CLI**: `git -C .\ComfyUI\custom_nodes\ComfyUI-Manager pull --rebase`

> If Windows ownership gets weird, whitelist or take ownership:
> `git config --global --add safe.directory E:/ComfyUI_windows_portable/ComfyUI/custom_nodes/ComfyUI-Manager`

---

## 6) Keep fork in sync with upstream

```powershell
git fetch upstream
git rebase upstream/master
git push origin master
```

Use **GitLens → Remotes → upstream → Fetch** then **Rebase Current Branch onto upstream/master** if you prefer GUI.

---

## 7) Updating core ComfyUI (periodically)

If you keep it as a submodule pointer inside this fork, do:
```powershell
git submodule update --remote --merge ComfyUI
git add ComfyUI
git commit -m "submodule: bump ComfyUI"
git push
```
(Otherwise, if you keep core directly in-tree in your fork, just rebase on upstream as above.)

---

## 8) Handy scripts

- `Run-ComfyUI.bat` / `Run-ComfyUI.ps1` — robust launcher + logging
- `Check-GitStatus.ps1` — shows branch tracking, remotes, submodule + Manager commit/remote
- (optional) VS Code tasks for: sync fork, update Manager, install node requirements, run ComfyUI

---

## 9) Why this layout

- Fork stays small: **no models/outputs/venv** in Git
- Manager can **self-update** without polluting fork history
- Rebase on upstream is straightforward (GitLens makes it painless)

### Git topology
```markdown
```mermaid
graph TD
  subgraph Fork
    A[Wrapper Repo<br/>justinthenick/ComfyUI]
  end
  subgraph Upstream
    B[ComfyUI<br/>comfyanonymous/ComfyUI]
  end
  subgraph Custom Nodes
    C[ComfyUI-Manager<br/>Comfy-Org/ComfyUI-Manager]
  end

  A -->|rebase| B
  A -->|git clone| C
