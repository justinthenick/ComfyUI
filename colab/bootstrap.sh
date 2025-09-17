#!/usr/bin/env bash
set -euo pipefail

# --- Settings (override with env) ---
PORT="${PORT:-8188}"
DATA_ROOT="${DATA_ROOT:-/content/ComfyUI_data}"
LOCK_PATH="${LOCK_PATH:-./inventory/stack.lock.json}"
PY="${PYTHON:-python3}"

echo "== ComfyUI Colab bootstrap =="
echo "PORT=$PORT"
echo "DATA_ROOT=$DATA_ROOT"

# Ensure git present
git --version >/dev/null

# 0) Update submodules
git submodule sync --recursive
git submodule update --init --recursive

# 1) (Optional) Restore exact SHAs from lock if present
if [[ -f "$LOCK_PATH" ]]; then
  echo "[restore] Using lock: $LOCK_PATH"
  # checkout SHAs
  jq -r '.core, .nodes[] | .path + " " + .commit' "$LOCK_PATH" | while read -r path sha; do
    echo "[restore] $path -> $sha"
    (cd "$path" && git fetch --tags --all -q && git checkout -q "$sha")
  done
else
  echo "[restore] No lock file found, proceeding with current submodule SHAs"
fi

# 2) Python env: Colab has a working Python; use it
# $PY -m pip install --upgrade pip wheel setuptools
$PY -m pip install -r inventory/requirements-colab.txt
# Optional: plus ComfyUI requirements if you prefer
# $PY -m pip install -r requirements.txt

# 3) Install ComfyUI + node deps (base first)
if [[ -f requirements.txt ]]; then
  $PY -m pip install -r requirements.txt
fi

# Common extras for performance if available (best-effort)
$PY - <<'PY'
import sys, subprocess
def try_install(pkg):
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install", pkg])
    except Exception:
        pass
# Try xformers (CUDA-only; may fail on some Colab images)
try_install("xformers==0.0.27.post2")
PY

# 4) Prepare portable directories
mkdir -p "$DATA_ROOT/user" "$DATA_ROOT/outputs" "$DATA_ROOT/outputs/temp"

# 5) Launch
COMFY_ROOT="./ComfyUI"
CMD=(
  "$PY" "$COMFY_ROOT/main.py"
  --port "$PORT"
  --listen 0.0.0.0
  --user-directory "$DATA_ROOT/user"
  --output-directory "$DATA_ROOT/outputs"
  --temp-directory "$DATA_ROOT/outputs/temp"
  --database-url "sqlite:///$DATA_ROOT/user/comfyui.db"
  --extra-model-paths-config "./extra_model_paths.yaml"
)
echo "[launch] ${CMD[*]}"
exec "${CMD[@]}"
# --- End of script ---