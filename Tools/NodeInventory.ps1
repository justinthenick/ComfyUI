# Tools\NodeInventory.ps1
# PowerShell 5.1+
# - Export-InstalledNodeInventory: writes inventory/installed_nodes.json (gitignored)
# - Ensure-DesiredNodes: ensures inventory/nodes.json exists (from installed git repos if missing),
#                        and on fresh clones will git-clone desired nodes.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Alias -Name Ensure-DesiredNodes -Value Install-DesiredNodes -Scope Script


function Resolve-CustomNodesDir([string]$AppRoot) {
  $nodes = Join-Path $AppRoot 'custom_nodes'
  if (-not (Test-Path -LiteralPath $nodes)) {
    New-Item -ItemType Directory -Path $nodes | Out-Null
  }
  return (Resolve-Path -LiteralPath $nodes).Path
}

function Set-DesiredFromInstalled([string]$AppRoot, [string]$DesiredPath) {
  $git = Get-InstalledNodes $AppRoot | Where-Object { $_.is_git -and $_.remote }
  $desired = foreach ($n in $git) {
    [pscustomobject]@{
      name   = $n.name
      remote = $n.remote
      ref    = if ($n.branch -and $n.branch -ne 'HEAD') { $n.branch } else { $n.commit }
      path   = "ComfyUI/custom_nodes/$($n.name)"
    }
  }
  Write-DesiredNodes -DesiredPath $DesiredPath -Nodes $desired
}


function Get-GitInfo([string]$Dir) {
  $isGit = Test-Path -LiteralPath (Join-Path $Dir '.git')
  if (-not $isGit) {
    return [pscustomobject]@{ is_git=$false; branch=$null; commit=$null; remote=$null }
  }
  $branch = $null; $commit = $null; $remote = $null
  try { $branch = (git -C $Dir rev-parse --abbrev-ref HEAD 2>$null).Trim() } catch {}
  try { $commit = (git -C $Dir rev-parse HEAD               2>$null).Trim() } catch {}
  try { $remote = (git -C $Dir remote get-url origin        2>$null).Trim() } catch {}
  if (-not $branch) { $branch = 'HEAD' }
  [pscustomobject]@{ is_git=$true; branch=$branch; commit=$commit; remote=$remote }
}

function Get-InstalledNodes([string]$AppRoot) {
  $nodesDir = Resolve-CustomNodesDir $AppRoot
  Get-ChildItem -LiteralPath $nodesDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $gi = Get-GitInfo $_.FullName
    [pscustomobject]@{
      name   = $_.Name
      path   = $_.FullName
      is_git = $gi.is_git
      branch = $gi.branch
      commit = $gi.commit
      remote = $gi.remote
    }
  }
}

function Export-InstalledNodeInventory([string]$AppRoot, [string]$Output) {
  $inv = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    nodes        = @(Get-InstalledNodes $AppRoot)
  }
  $outDir = Split-Path -Parent $Output
  if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
  $inv | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Output -Encoding UTF8
  Write-Host "[INV] Wrote installed inventory -> $Output" -ForegroundColor DarkCyan
}

function Read-DesiredNodes([string]$DesiredPath) {
  if (-not (Test-Path -LiteralPath $DesiredPath)) { return $null }
  try {
    $obj = (Get-Content -LiteralPath $DesiredPath -Raw) | ConvertFrom-Json
    if ($obj -and $obj.nodes) { return $obj.nodes }
    if ($obj -is [array])     { return $obj } # support plain array
  } catch {}
  return $null
}

function Write-DesiredNodes([string]$DesiredPath, $Nodes) {
  $obj = [pscustomobject]@{ version = 1; nodes = @($Nodes) }
  $outDir = Split-Path -Parent $DesiredPath
  if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
  $obj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $DesiredPath -Encoding UTF8
  Write-Host "[INV] Wrote desired inventory -> $DesiredPath" -ForegroundColor DarkCyan
}

function Install-DesiredNodes([string]$AppRoot, [string]$DesiredPath, [switch]$Bootstrap) {
  $desired  = Read-DesiredNodes $DesiredPath

  if (-not $desired) {
    # Seed desired from current git-backed installs
    $cur = Get-InstalledNodes $AppRoot | Where-Object { $_.is_git -and $_.remote }
    $desired = foreach ($n in $cur) {
      [pscustomobject]@{
        name   = $n.name
        remote = $n.remote
        ref    = if ($n.branch -and $n.branch -ne 'HEAD') { $n.branch } else { $n.commit }
        path   = "ComfyUI/custom_nodes/$($n.name)"
      }
    }
    Write-DesiredNodes -DesiredPath $DesiredPath -Nodes $desired
  }

  if ($Bootstrap) {
    foreach ($dn in $desired) {
      $target = if ($dn.path) { $dn.path } else { "ComfyUI/custom_nodes/$($dn.name)" }
      $abs    = Join-Path (Split-Path -Parent $AppRoot) $target
      if (Test-Path -LiteralPath $abs) { continue }
      if (-not $dn.remote) {
        Write-Warning "[INV] Desired node '$($dn.name)' has no 'remote' -> skip (manual install required)"; continue
      }
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $abs) | Out-Null
      Write-Host "[INV] Cloning $($dn.name) -> $abs" -ForegroundColor DarkGreen
      git clone $dn.remote $abs | Out-Null
      if ($LASTEXITCODE -ne 0) { Write-Warning "[INV] git clone failed for $($dn.name)"; continue }
      if ($dn.ref) {
        try { git -C $abs fetch --all --tags | Out-Null } catch {}
        git -C $abs checkout $dn.ref 2>$null | Out-Null
      }
    }
  }
}

function Get-InventoryDelta([string]$AppRoot, [string]$DesiredPath) {
  $installed = @(Get-InstalledNodes $AppRoot)
  $desired   = @(Read-DesiredNodes $DesiredPath)
  [pscustomobject]@{
    installed_only = @($installed | Where-Object { $desired.name -notcontains $_.name })
    desired_only   = @($desired   | Where-Object { $installed.name -notcontains $_.name })
    present_both   = @($desired   | Where-Object { $installed.name -contains $_.name })
  }
}
