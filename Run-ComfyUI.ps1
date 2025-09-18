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
  [string]$BindAddress = '127.0.0.1',
  [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR')]
  [string]$VerboseLevel = 'INFO',

  # Portable data drive (e.g., "E" or "E:"); defaults to wrapper's drive
  [string]$DataDrive = 'E'
)

$ErrorActionPreference = 'Stop'

# ---- Config load (default + local) ----
function Join-Config($base, $override) {
  if (-not $override) { return $base }
  $h = @{}
  $base.PSObject.Properties    | ForEach-Object { $h[$_.Name] = $_.Value }
  $override.PSObject.Properties| ForEach-Object { $h[$_.Name] = $_.Value }
  return [pscustomobject]$h
}


$CfgDefaultPath = Join-Path $PSScriptRoot 'comfy_config\settings.default.json'
$CfgLocalPath   = Join-Path $PSScriptRoot 'comfy_config\settings.local.json'

$cfg = $null
if (Test-Path $CfgDefaultPath) { $cfg = Get-Content $CfgDefaultPath -Raw | ConvertFrom-Json }
if (Test-Path $CfgLocalPath)   { $cfg = Join-Config $cfg (Get-Content $CfgLocalPath -Raw | ConvertFrom-Json) }

# Apply config defaults only when the CLI option wasn't provided
if ($null -ne $cfg) {
  if ( ($null -eq $PSBoundParameters['Port'])         -and $cfg.Port)        { $Port        = [int]$cfg.Port }
  if ( ($null -eq $PSBoundParameters['Listen'])       -and $cfg.Listen)      { $Listen      = [bool]$cfg.Listen }
  if ( ($null -eq $PSBoundParameters['BindAddress'])  -and $cfg.BindAddress) { $BindAddress = [string]$cfg.BindAddress }
  if ( ($null -eq $PSBoundParameters['VerboseLevel']) -and $cfg.VerboseLevel){ $VerboseLevel= [string]$cfg.VerboseLevel }
  if ( ($null -eq $PSBoundParameters['DataDrive'])    -and $cfg.DataDrive)   { $DataDrive   = [string]$cfg.DataDrive }
}


# ---- Paths ----
$ROOT    = Split-Path -Parent $PSCommandPath
$AppRoot = Join-Path $ROOT 'ComfyUI'
$env:PYTHONPATH = if ($env:PYTHONPATH) {
  "$AppRoot;$env:PYTHONPATH"
} else {
  $AppRoot
}

# ---- Portable data root selection (with -DataDrive) ----
function Get-NormalizedDriveRoot([string]$driveLetterOrRoot) {
  if (-not $driveLetterOrRoot) { return $null }
  $d = $driveLetterOrRoot.Trim()

  # Accept "D", "D:", "D:\"
  if ($d.Length -ge 2 -and $d[1] -eq ':') { $d = $d.Substring(0,1) }
  $d = $d.TrimEnd('\', ':')

  if ($d.Length -ne 1) { return $null }  # must be a single letter
  $letter = $d.ToUpper()

  $ps = Get-PSDrive -Name $letter -ErrorAction SilentlyContinue
  if ($ps) { return $ps.Root }           # e.g., "E:\"
  else      { return "$letter`:\" }      # best-effort fallback
}

# 1) Prefer explicit -DataDrive if valid; otherwise use wrapper's drive
$driveRoot = Get-NormalizedDriveRoot $DataDrive
if (-not $driveRoot) {
  $driveRoot = (Get-Item -LiteralPath $ROOT).PSDrive.Root  # e.g., "E:\"
}

# Standardised portable root name (from config)
$rootName = if ($cfg.UserRootName) { [string]$cfg.UserRootName } else { 'ComfyUI_data' }

$preferred = @(
  (Join-Path $driveRoot $rootName),            # E:\ComfyUI_data
  (Join-Path $env:USERPROFILE 'ComfyUI_data'),       # %USERPROFILE%\ComfyUI_data
  (Join-Path $ROOT 'Data')                           # .\Data
)

# 3) Pick the first existing; otherwise choose the first and normalise
$DATA = $preferred | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $DATA) { $DATA = $preferred[0] }

# 4) Normalise to an absolute path (ensures "E:\..." not "E")
try   { $DATA = (Resolve-Path -LiteralPath $DATA -ErrorAction Stop).Path }
catch { $DATA = [System.IO.Path]::GetFullPath($DATA) }

# 5) Now safely derive subpaths
$env:COMFYUI_USER_PATH  = Join-Path $DATA 'user'
$ModelRoot = Join-Path $DATA 'models'
$env:COMFYUI_OUTPUT_DIR = Join-Path $DATA 'outputs'
$env:COMFYUI_TEMP_DIR   = Join-Path $env:COMFYUI_OUTPUT_DIR 'temp'
$env:COMFYUI_DATABASE_DIR = Join-Path $DATA 'db'


# ----------------- Python env vars -----------------
$env:PYTHONUTF8         = '1'

# Ensure dirs
$null = New-Item -ItemType Directory -Force -Path $env:COMFYUI_USER_PATH,$ModelRoot,$env:COMFYUI_OUTPUT_DIR,$env:COMFYUI_TEMP_DIR
$LogDir = Join-Path $ROOT 'logs'
$null = New-Item -ItemType Directory -Force -Path $LogDir
New-Item -ItemType Directory -Force -Path $env:COMFYUI_DATABASE_DIR | Out-Null

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



# ---- Build ComfyUI program args ----
$progArgs = @(
  '--windows-standalone-build',
  '--port', $Port,
  '--user-directory',   $env:COMFYUI_USER_PATH,
  '--output-directory', $env:COMFYUI_OUTPUT_DIR,
  '--temp-directory',   $env:COMFYUI_TEMP_DIR,
  '--database-url',     $dbUrl
)

# CPU-only flags (single place)
if (-not $GPU) {
  $env:CUDA_VISIBLE_DEVICES = '-1'
  $progArgs += '--cpu'
  if ($cfg -and $cfg.DisableXformersOnCPU) { $progArgs += '--disable-xformers' }
}

# ---- Extra model paths (supports generated OR template) ----
$usedCfg  = $null
$genYaml  = Join-Path $ROOT '.generated.extra_model_paths.yaml'
$explicit = $null

if ($cfg -and $cfg.ExtraModelPathsConfig) {
  $p = $cfg.ExtraModelPathsConfig
  $explicit = if ([System.IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $ROOT $p }
}

# Case 1: config points straight at the generated file -> use it as-is
if ($explicit -and ($explicit -like '*\.generated.extra_model_paths.yaml') -and (Test-Path -LiteralPath $explicit)) {
  $usedCfg = $explicit
}
else {
  # Case 2: config (or default) is a template -> generate
  $template = if ($explicit) { $explicit } else { Join-Path $ROOT 'extra_model_paths.template.yaml' }
  if (Test-Path -LiteralPath $template) {
    $raw         = Get-Content -LiteralPath $template -Raw
    $dataForward = $DATA.ToString().Replace('\','/')
    $raw.Replace('{{DATA_ROOT}}', $dataForward) | Set-Content -LiteralPath $genYaml -Encoding UTF8
    $usedCfg = $genYaml
  }
}

if ($usedCfg) {
  $progArgs += @('--extra-model-paths-config', $usedCfg)
  Write-Host "[INFO] ExtraModelPaths: $usedCfg"
} else {
  Write-Host "[WARN] No extra-model paths config found or generated."
}


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

# ---- Inventory (bootstrap + pre-snapshot) ----
try {
  $InventoryScript = Join-Path $ROOT 'Tools\NodeInventory.ps1'
  if (Test-Path $InventoryScript) {
    . $InventoryScript

    $InvDir     = Join-Path $ROOT 'inventory'
    New-Item -ItemType Directory -Force -Path $InvDir | Out-Null

    $DesiredInv = Join-Path $InvDir 'nodes.json'
    if (-not (Test-Path $DesiredInv)) {
      $Template = Join-Path $InvDir 'nodes.template.json'
      if (Test-Path $Template) { Copy-Item $Template $DesiredInv }
    }

    # Bootstrap missing git nodes on a fresh clone
    Install-DesiredNodes -AppRoot $AppRoot -DesiredPath $DesiredInv -Bootstrap:$true

    # Pre-run snapshot of what's installed right now
    Export-InstalledNodeInventory -AppRoot $AppRoot -Output (Join-Path $InvDir 'installed_nodes.json')
  } else {
    Write-Host "[INV] Tools\NodeInventory.ps1 not found; skipping inventory." -ForegroundColor DarkYellow
  }
} catch {
  Write-Host "[INV] Inventory step failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

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

# Post-run inventory snapshot
try {
  if ($InvDir) {
    Export-InstalledNodeInventory -AppRoot $AppRoot -Output (Join-Path $InvDir 'installed_nodes.json')
  }
} catch {}   