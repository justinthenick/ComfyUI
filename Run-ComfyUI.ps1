# Run-ComfyUI.ps1  (PowerShell 5.1 compatible)
# Cleaner logging + safer startup for ComfyUI
# [CmdletBinding()]
[CmdletBinding(PositionalBinding=$false)]

param(
    [switch]$GPU,           # Use GPU (omit --cpu)
    [int]$Port = 8188,      # ComfyUI port
    [switch]$NoTail,         # If set, don't live-tail the log
    [string[]]$ComfyArgs  # <-- new: for pass-through to ComfyUI
)

$ErrorActionPreference = 'Stop'

# ---- Paths ----
$ROOT   = Split-Path -Parent $PSCommandPath
#$APP    = Join-Path $ROOT 'ComfyUI'
#$MAINPY = Join-Path $APP  'main.py'
$VENV1  = Join-Path $ROOT 'venv\Scripts\python.exe'
$VENV2  = Join-Path $ROOT '.venv\Scripts\python.exe'
$LOGDIR = Join-Path $ROOT 'logs'

# External data dirs (you said user folder already exists here)
$env:COMFYUI_USER_PATH  = 'E:\ComfyUI_data\user'
$env:COMFYUI_MODEL_PATH = 'E:\ComfyUI_data\models'
$env:COMFYUI_OUTPUT_DIR = 'E:\ComfyUI_data\outputs'
$env:COMFYUI_TEMP_DIR   = 'E:\ComfyUI_data\outputs\temp'
$env:PYTHONUTF8         = '1'


# ---- Ensure dirs ----
$null = New-Item -ItemType Directory -Force -Path $LOGDIR
$null = New-Item -ItemType Directory -Force -Path $env:COMFYUI_OUTPUT_DIR
$null = New-Item -ItemType Directory -Force -Path $env:COMFYUI_TEMP_DIR
# user dir is expected to exist already, but make sure:
$null = New-Item -ItemType Directory -Force -Path $env:COMFYUI_USER_PATH


# ---- Logfiles (separate stdout/stderr in PS 5.1) ----
$ts      = Get-Date -Format 'yyyyMMdd_HHmmss'
$logBase = Join-Path $LOGDIR ("comfyui_{0}" -f $ts)
$logOut  = "$logBase.out.log"
$logErr  = "$logBase.err.log"
$log     = "$logBase.log"       # merged at process end (optional)

Write-Host "[INFO] Log (stdout): $logOut" -ForegroundColor DarkCyan
Write-Host "[INFO] Log (stderr): $logErr" -ForegroundColor DarkCyan

# ---- Custom nodes: ensure top-level dir + nested link/dir ----
# This way, you can drop custom nodes in E:\ComfyUI_windows_portable\custom_nodes
# and they will be visible in ComfyUI (which expects them in ComfyUI\custom_nodes)
# Note: mklink /J requires admin rights, so we fall back to a plain dir if it fails
# (which you can then manually populate with copies or symlinks if you want)    
$TopNodes     = 'E:\ComfyUI_windows_portable\custom_nodes'
$NestedNodes  = 'E:\ComfyUI_windows_portable\ComfyUI\custom_nodes'

if (-not (Test-Path $TopNodes))    { New-Item -ItemType Directory -Path $TopNodes -Force | Out-Null }
if (-not (Test-Path $NestedNodes)) {
    try {
        # Try for a junction (best)
        cmd /c mklink /J "$NestedNodes" "$TopNodes" | Out-Null
    } catch {
        # Fall back to a plain empty dir if mklink is unavailable
        New-Item -ItemType Directory -Path $NestedNodes -Force | Out-Null
    }
}


# ---- Pick Python (prefer venvs) ----
$pyExe  = $null
$pyArgs = @()

if (Test-Path $VENV1)      { $pyExe = $VENV1 }
elseif (Test-Path $VENV2)  { $pyExe = $VENV2 }
else {
    $cmd = Get-Command py -ErrorAction SilentlyContinue
    if ($cmd) {
        $pyExe  = $cmd.Source
        $pyArgs = @('-3.11')  # prefer 3.11 if present
    } else {
        $cmd = Get-Command python -ErrorAction SilentlyContinue
        if ($cmd) {
            $pyExe = $cmd.Source
        } else {
            $p311 = Join-Path $env:LocalAppData 'Programs\Python\Python311\python.exe'
            $p310 = Join-Path $env:LocalAppData 'Programs\Python\Python310\python.exe'
            if     (Test-Path $p311) { $pyExe = $p311 }
            elseif (Test-Path $p310) { $pyExe = $p310 }
        }
    }
}

if (-not $pyExe) {
    Write-Host "[ERROR] No Python interpreter found (venv/.venv/py/python). Install 3.11/3.10 or create a venv." -ForegroundColor Red
    exit 1
}

# ---- DB URL + preflight probe (keep this if you already added it) ----
function ConvertTo-SqliteUrl([string]$p) { "sqlite:///" + ($p -replace '\\','/') }
$dbFile = Join-Path $env:COMFYUI_USER_PATH 'comfyui.db'
$dbUrl  = ConvertTo-SqliteUrl $dbFile
Write-Host "[INFO] Database (target file): $dbFile" -ForegroundColor DarkCyan
Write-Host "[INFO] Database URL: $dbUrl" -ForegroundColor DarkCyan

# ---- Build Python interpreter args (no script path!) ----
$pyInterpArgs = @($pyArgs) + @('-m','ComfyUI.main')   # <- important: no $MAINPY

# ---- Build ComfyUI program args ----
$extraModelYaml = Join-Path $ROOT 'extra_model_paths.yaml'
$progArgs = @(
    '--windows-standalone-build',
    '--port', $Port,
    '--user-directory',   $env:COMFYUI_USER_PATH,
    '--output-directory', $env:COMFYUI_OUTPUT_DIR,
    '--temp-directory',   $env:COMFYUI_TEMP_DIR,
    '--database-url',     $dbUrl
)
if (-not $GPU) { $progArgs += '--cpu' }
if (Test-Path $extraModelYaml) {
    $progArgs += @('--extra-model-paths-config', $extraModelYaml)
} else {
    Write-Host "[INFO] extra_model_paths.yaml not found. Skipping --extra-model-paths-config." -ForegroundColor DarkYellow
}
if ($ComfyArgs) { $progArgs += $ComfyArgs }  # e.g. '--listen','--verbose','INFO'

# ---- Show the exact command for sanity ----
Write-Host "[DEBUG] Launch: $pyExe $($pyInterpArgs -join ' ') $($progArgs -join ' ')" -ForegroundColor Gray

# ---- Separate stdout/stderr (PS 5.1 limitation) and launch ----
$p = Start-Process -FilePath $pyExe `
    -ArgumentList ($pyInterpArgs + $progArgs) `
    -NoNewWindow `
    -RedirectStandardOutput $logOut `
    -RedirectStandardError  $logErr `
    -PassThru

    
# Wait for ComfyUI to start listening on the port (up to 120s)
$hostToCheck = '127.0.0.1'   # or use $env:COMFYUI_HOST if you add one
$portToCheck = 8188
$deadline = (Get-Date).AddSeconds(120)

Write-Host "[INFO] Waiting for "${hostToCheck}":$portToCheck to accept connections..."
while ((Get-Date) -lt $deadline) {
    if (Test-NetConnection $hostToCheck -Port $portToCheck -InformationLevel Quiet) {
        Write-Host "[INFO] ComfyUI is listening on "${hostToCheck}":$portToCheck"
        break
    }
    Start-Sleep -Seconds 1
}
if (-not (Test-NetConnection $hostToCheck -Port $portToCheck -InformationLevel Quiet)) {
    Write-Warning "[WARN] Port check timed out. Use: netstat -ano | findstr :$portToCheck  (PID should match the ComfyUI process)"
}

# ---- Tail log (unless -NoTail) ----
# On exit, merge stdout+stderr into single log file (best-effort)
if (-not $NoTail) {
    try { Get-Content -Path $logOut, $logErr -Wait } finally {
        $p.WaitForExit()
        $code = $p.ExitCode
        try { Get-Content $logOut, $logErr | Set-Content $log } catch {}
        if ($code -ne 0) {
            Write-Host "[WARN] ComfyUI exited with code $code. Merged log: $log" -ForegroundColor Yellow
        } else {
            Write-Host "[OK] ComfyUI exited normally. Merged log: $log" -ForegroundColor Green
        }
    }
} else {
    Write-Host "[INFO] Not tailing log (use -NoTail). PID: $($p.Id). Logs: $logOut | $logErr" -ForegroundColor Gray
}
