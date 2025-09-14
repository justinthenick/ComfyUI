# Run-ComfyUI.ps1  (PowerShell 5.1 compatible)
$ErrorActionPreference = 'Stop'

$ROOT   = Split-Path -Parent $PSCommandPath
$APP    = Join-Path $ROOT 'ComfyUI'
$VENV1  = Join-Path $ROOT 'venv\Scripts\python.exe'
$VENV2  = Join-Path $ROOT '.venv\Scripts\python.exe'
$LOGDIR = Join-Path $ROOT 'logs'

# External data dirs — adjust if needed
$env:COMFYUI_USER_PATH  = 'E:\ComfyUI_data\user'
$env:COMFYUI_MODEL_PATH = 'E:\ComfyUI_data\models'
$env:COMFYUI_OUTPUT_DIR = 'E:\ComfyUI_data\outputs'
$env:COMFYUI_TEMP_DIR   = 'E:\ComfyUI_data\outputs\temp'
$env:PYTHONUTF8         = '1'

# Ensure log dir + logfile
New-Item -ItemType Directory -Force -Path $LOGDIR | Out-Null
$ts  = Get-Date -Format 'yyyyMMdd_HHmmss'
$log = Join-Path $LOGDIR ("comfyui_{0}.log" -f $ts)

# ---- Pick Python (prefer venvs) ----
$pyExe  = $null
$pyArgs = @()

if (Test-Path $VENV1) { $pyExe = $VENV1 }
elseif (Test-Path $VENV2) { $pyExe = $VENV2 }
else {
    # Try 'py' launcher
    $cmd = Get-Command py -ErrorAction SilentlyContinue
    if ($cmd) {
        $pyExe = $cmd.Source
        $pyArgs = @('-3.11')   # prefer 3.11 if present
    } else {
        # Try 'python' on PATH
        $cmd = Get-Command python -ErrorAction SilentlyContinue
        if ($cmd) {
            $pyExe = $cmd.Source
        } else {
            # Common install paths
            $p311 = Join-Path $env:LocalAppData 'Programs\Python\Python311\python.exe'
            $p310 = Join-Path $env:LocalAppData 'Programs\Python\Python310\python.exe'
            if (Test-Path $p311) { $pyExe = $p311 }
            elseif (Test-Path $p310) { $pyExe = $p310 }
        }
    }
}

if (-not $pyExe) {
    Write-Host "[ERROR] No Python interpreter found (venv/.venv/py/python). Install 3.11/3.10 or create a venv." -ForegroundColor Red
    exit 1
}

# ---- Compose args ----
$mainPy          = Join-Path $APP 'main.py'
$extraModelYaml  = Join-Path $ROOT 'extra_model_paths.yaml'

$comfyArgs = @(
    $mainPy,
    '--windows-standalone-build',
    '--cpu',                                 # remove this if you have a working GPU
    '--extra-model-paths', $extraModelYaml,
    '--user-directory',   $env:COMFYUI_USER_PATH,
    '--output-directory', $env:COMFYUI_OUTPUT_DIR,
    '--temp-directory',   $env:COMFYUI_TEMP_DIR
)

# Pass through any extra args from BAT call, e.g. --port 8188
if ($args.Count -gt 0) { $comfyArgs += $args }

Write-Host "[INFO] Python: $pyExe $($pyArgs -join ' ')" -ForegroundColor Cyan
Write-Host "[INFO] Log: $log" -ForegroundColor DarkCyan

# ---- Simple tee pipeline (stdout+stderr) ----
$oldEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'   # don't treat native stderr as terminating

& $pyExe @pyArgs @comfyArgs 2>&1 | Tee-Object -FilePath $log
$code = $LASTEXITCODE

$ErrorActionPreference = $oldEAP

if ($code -ne 0) {
  Write-Host "[WARN] ComfyUI exited with code $code. See log: $log" -ForegroundColor Yellow
} else {
  Write-Host "[OK] ComfyUI exited normally. Log: $log" -ForegroundColor Green
}
