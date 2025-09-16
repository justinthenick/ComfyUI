# Run-ComfyUI.ps1  (PowerShell 5.1+)
# Clean, portable launcher with optional external listen and verbosity switches

[CmdletBinding(PositionalBinding=$false)]
param(
  [switch]$GPU,
  [int]$Port = 8188,
  [switch]$NoTail,
  [string[]]$ComfyArgs,

  # Convenience
  [switch]$Listen,
  [string]$BindAddress = '0.0.0.0',
  [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR')]
  [string]$VerboseLevel = 'INFO'
)

$ErrorActionPreference = 'Stop'

# ---- Paths ----
$ROOT    = Split-Path -Parent $PSCommandPath
$AppRoot = Join-Path $ROOT 'ComfyUI'

# Portable data roots (first existing, else create under USERPROFILE)
$Candidates = @(
  'E:\ComfyUI_data',
  (Join-Path $env:USERPROFILE 'ComfyUI_data'),
  (Join-Path $ROOT 'Data')
) | Where-Object { Test-Path $_ }

if (-not $Candidates) { $Candidates = @((Join-Path $env:USERPROFILE 'ComfyUI_data')) }
$DATA = $Candidates[0]

$env:COMFYUI_USER_PATH  = Join-Path $DATA 'user'
$env:COMFYUI_MODEL_PATH = Join-Path $DATA 'models'
$env:COMFYUI_OUTPUT_DIR = Join-Path $DATA 'outputs'
$env:COMFYUI_TEMP_DIR   = Join-Path $env:COMFYUI_OUTPUT_DIR 'temp'
$env:PYTHONUTF8         = '1'

# Ensure dirs
$null = New-Item -ItemType Directory -Force -Path $env:COMFYUI_USER_PATH,$env:COMFYUI_MODEL_PATH,$env:COMFYUI_OUTPUT_DIR,$env:COMFYUI_TEMP_DIR
$LogDir = Join-Path $ROOT 'logs'
$null = New-Item -ItemType Directory -Force -Path $LogDir

# Custom nodes junction (portable)
$TopNodes    = Join-Path $ROOT    'custom_nodes'
$NestedNodes = Join-Path $AppRoot 'custom_nodes'
if (-not (Test-Path $TopNodes)) { New-Item -ItemType Directory -Force -Path $TopNodes | Out-Null }
if (-not (Test-Path $NestedNodes)) {
  try {
    cmd /c mklink /J "$NestedNodes" "$TopNodes" | Out-Null
  } catch {
    New-Item -ItemType Directory -Force -Path $NestedNodes | Out-Null
  }
}

# Choose Python
$VENV1 = Join-Path $ROOT 'venv\Scripts\python.exe'
$VENV2 = Join-Path $ROOT '.venv\Scripts\python.exe'
$pyExe = $null; $pyArgs = @()
if     (Test-Path $VENV1) { $pyExe = $VENV1 }
elseif (Test-Path $VENV2) { $pyExe = $VENV2 }
else {
  $cmd = Get-Command py -ErrorAction SilentlyContinue
  if ($cmd) { $pyExe = $cmd.Source; $pyArgs = @('-3.11') }
  else {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { $pyExe = $cmd.Source }
    else {
      $p311 = Join-Path $env:LocalAppData 'Programs\Python\Python311\python.exe'
      $p310 = Join-Path $env:LocalAppData 'Programs\Python\Python310\python.exe'
      if     (Test-Path $p311) { $pyExe = $p311 }
      elseif (Test-Path $p310) { $pyExe = $p310 }
    }
  }
}
if (-not $pyExe) { Write-Host "[ERROR] Python 3.10/3.11 not found." -ForegroundColor Red; exit 1 }

# DB URL
function ConvertTo-SqliteUrl([string]$p) { "sqlite:///" + ($p -replace '\\','/') }
$dbFile = Join-Path $env:COMFYUI_USER_PATH 'comfyui.db'
$dbUrl  = ConvertTo-SqliteUrl $dbFile

# Build args
$MainPy = Join-Path $AppRoot 'main.py'
$pyInterpArgs = @($pyArgs) + @($MainPy)

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
if (Test-Path $extraModelYaml) { $progArgs += @('--extra-model-paths-config', $extraModelYaml) }
if ($Listen) { $progArgs += @('--listen', $BindAddress) }
if ($VerboseLevel) { $progArgs += @('--verbose', $VerboseLevel) }
if ($ComfyArgs) { $progArgs += $ComfyArgs }

# Logs
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$logOut = Join-Path $LogDir "comfyui_${ts}.out.log"
$logErr = Join-Path $LogDir "comfyui_${ts}.err.log"
$log    = Join-Path $LogDir "comfyui_${ts}.log"

Write-Host "[INFO] WorkingDirectory: $AppRoot" -ForegroundColor DarkCyan
Write-Host "[INFO] User: $($env:COMFYUI_USER_PATH)" -ForegroundColor DarkCyan
Write-Host "[INFO] Output: $($env:COMFYUI_OUTPUT_DIR)" -ForegroundColor DarkCyan
Write-Host "[INFO] Temp: $($env:COMFYUI_TEMP_DIR)" -ForegroundColor DarkCyan
Write-Host "[INFO] DB: $dbFile" -ForegroundColor DarkCyan
Write-Host "[DEBUG] Launch: $pyExe $($pyInterpArgs -join ' ') $($progArgs -join ' ')" -ForegroundColor Gray

# Launch
$p = Start-Process -FilePath $pyExe `
  -WorkingDirectory $AppRoot `
  -ArgumentList ($pyInterpArgs + $progArgs) `
  -NoNewWindow `
  -RedirectStandardOutput $logOut `
  -RedirectStandardError  $logErr `
  -PassThru

# Tail logs unless NoTail
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
  Write-Host "[INFO] Not tailing logs. PID: $($p.Id)  OUT: $logOut  ERR: $logErr" -ForegroundColor Gray
}
