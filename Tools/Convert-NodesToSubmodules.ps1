<# 
  Convert-NodesToSubmodules.ps1
  - Scans .\custom_nodes
  - For each pack:
      * If it's already a git repo with an origin  → leave it (or use -Force to re-submodule)
      * If it's not a git repo                      → ask for origin (uses a known mapping first), add as submodule
  - Moves the existing folder aside, adds submodule, restores non-repo extra files, commits.

  Usage:
    powershell -ExecutionPolicy Bypass -File .\Tools\Convert-NodesToSubmodules.ps1
    # Dry run:
    powershell -ExecutionPolicy Bypass -File .\Tools\Convert-NodesToSubmodules.ps1 -WhatIf
    # Force re-submodule even if a repo exists:
    powershell -ExecutionPolicy Bypass -File .\Tools\Convert-NodesToSubmodules.ps1 -Force
    # One commit for all changes (instead of per-pack):
    powershell -ExecutionPolicy Bypass -File .\Tools\Convert-NodesToSubmodules.ps1 -SingleCommit
#>

[CmdletBinding(SupportsShouldProcess, PositionalBinding=$false)]
param(
  [switch]$Force,         # convert even if the folder is already a git repo
  [switch]$SingleCommit   # stage all, commit once at the end
)

$ErrorActionPreference = 'Stop'

# Resolve repo root (this script sits in Tools/)
$ScriptRoot = Split-Path -Parent $PSCommandPath
$RepoRoot   = (Resolve-Path (Join-Path $ScriptRoot '..')).Path
$NodesRoot  = Join-Path $RepoRoot 'custom_nodes'

if (-not (Test-Path $NodesRoot)) {
  Write-Error "custom_nodes not found at: $NodesRoot"
}

# Known upstreams you’re happy with (extend/edit as you like)
# Names must match the directory names under custom_nodes
$OriginMap = @{
  'ComfyUI-Advanced-ControlNet'   = 'https://github.com/Kosinkadink/ComfyUI-Advanced-ControlNet.git'
  'ComfyUI-Custom-Scripts'        = 'https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git'
  'ComfyUI-Manager'               = 'https://github.com/ltdrdata/ComfyUI-Manager.git'
  'ComfyUI_IPAdapter_plus'        = 'https://github.com/cubiq/ComfyUI_IPAdapter_plus.git'
  'comfy_PoP'                     = 'https://github.com/picturesonpictures/comfy_PoP.git'
  'rgthree-comfy'                 = 'https://github.com/rgthree/rgthree-comfy.git'

  # ✅ set these three correctly:
  'comfyui-easy-use'              = 'https://github.com/cubiq/ComfyUI_Easy_Use.git'
  'comfyui-embedding_picker'      = 'https://github.com/cubiq/ComfyUI_Embedding_Picker.git'
  'comfyui-inpaint-cropandstitch' = 'https://github.com/lquesada/ComfyUI-Inpaint-CropAndStitch.git'
}
if ($OriginMap.Keys.Count -eq 0) {
  Write-Warning "No entries in OriginMap; you will be prompted for each pack."}

function Get-IsGitRepo([string]$Path) {
  $res = & git -C $Path rev-parse --is-inside-work-tree 2>$null
  return ($res -eq 'true')
}
function Get-Origin([string]$Path) {
  & git -C $Path remote get-url origin 2>$null
}

# Gather packs
$packs = Get-ChildItem $NodesRoot -Directory | Sort-Object Name | ForEach-Object {
  $dir = $_.FullName
  $isRepo = Get-IsGitRepo $dir
  $origin = if ($isRepo) { Get-Origin $dir } else { $null }
  [pscustomobject]@{
    Name   = $_.Name
    Path   = $dir
    IsRepo = $isRepo
    Origin = $origin
  }
}

Write-Host "`n== Current node packs ==" -ForegroundColor Cyan
$packs | Format-Table Name, IsRepo, Origin -AutoSize

$didWork = $false
$staged  = @()

foreach ($p in $packs) {
  $name   = $p.Name
  $path   = $p.Path
  $target = "custom_nodes/$name"

  # Decide whether to convert
  $needConvert = (-not $p.IsRepo) -or $Force
  if (-not $needConvert) {
    Write-Host "Skip $name (git repo with origin: $($p.Origin))" -ForegroundColor DarkGray
    continue
  }

  # Resolve origin: existing, mapping, or prompt
  $origin = $p.Origin
  if (-not $origin) {
    if ($OriginMap.ContainsKey($name)) { $origin = $OriginMap[$name] }
    if (-not $origin) {
      Write-Host ""
      $origin = Read-Host "Enter origin URL for '$name' (or leave blank to skip)"
      if ([string]::IsNullOrWhiteSpace($origin)) {
        Write-Host "Skipping $name (no origin provided)" -ForegroundColor DarkYellow
        continue
      }
    }
  }

  Write-Host "`nConverting $name -> submodule ($origin)" -ForegroundColor Green

  $bak = "${path}._bak"
  if ($PSCmdlet.ShouldProcess($name, "Convert to submodule at $target")) {

    # 1) Move current folder aside
    if (Test-Path $bak) { Remove-Item -Recurse -Force $bak }
    Move-Item $path $bak

    # 2) Add submodule
    Push-Location $RepoRoot
    & git submodule add $origin $target
    Pop-Location

    # 3) Restore non-repo extras (avoid clobbering repo files)
    robocopy $bak $path /E /MOV `
      /XF .git .gitattributes .gitmodules .gitignore README* LICENSE*  | Out-Null

    # 4) Stage changes (commit now or later)
    Push-Location $RepoRoot
    & git add .gitmodules $target
    Pop-Location
    $staged += $name

    # 5) Cleanup
    Remove-Item -Recurse -Force $bak

    if (-not $SingleCommit) {
      Push-Location $RepoRoot
      & git commit -m "submodule: add $name"
      Pop-Location
      $staged = @()
    }

    $didWork = $true
  }
}

if ($SingleCommit -and $staged.Count -gt 0) {
  Push-Location $RepoRoot
  & git commit -m ("submodule: add " + ($staged -join ", "))
  Pop-Location
}

Write-Host ""
if ($didWork) {
  Write-Host "Done. Verifying submodules..." -ForegroundColor Cyan
  Push-Location $RepoRoot
  & git submodule status
  & git submodule update --init --recursive
  Pop-Location
  Write-Host "`n✅ Conversion complete." -ForegroundColor Green
} else {
  Write-Host "No changes made." -ForegroundColor Yellow
}
