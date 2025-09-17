# Tools\Write-Lock.ps1
[CmdletBinding()]
param(
  [string]$Out   = ".\inventory\stack.lock.json",
  [string]$VenvPy = ".\.venv\Scripts\python.exe"
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Get-SubmoduleList {
  # IMPORTANT: foreach runs in a POSIX shell; keep quoting strictly POSIX.
  # - We print: name|path|commit|origin|describe
  $cmd = 'printf "%s|%s|%s|%s|%s\n" "$name" "$path" "$(git rev-parse HEAD)" "$(git remote get-url origin 2>/dev/null)" "$(git describe --tags --always 2>/dev/null)"'
  & git -C $repo submodule foreach --quiet -- $cmd 2>$null
}

$items = @()
$lines = Get-SubmoduleList
foreach ($ln in $lines) {
  if (-not $ln) { continue }
  $parts = $ln -split '\|',5
  if ($parts.Count -lt 5) { continue }
  $items += [pscustomobject]@{
    name   = $parts[0]
    path   = $parts[1]
    commit = $parts[2]
    url    = $parts[3]
    tag    = $parts[4]
  }
}

$core  = $items | Where-Object { $_.path -eq 'ComfyUI' } | Select-Object -First 1
$nodes = $items | Where-Object { $_.path -like 'custom_nodes/*' } | Sort-Object path

# Pip freeze (best effort)
$freeze = @()
if (Test-Path $VenvPy) {
  $freeze = & $VenvPy -m pip freeze 2>$null
}

$lock = [ordered]@{
    generated_at = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    repo_branch  = (& git -C $repo rev-parse --abbrev-ref HEAD)
    repo_commit  = (& git -C $repo rev-parse --short HEAD)

    core = if ($core) {
        @{
            path   = $core.path
            url    = $core.url
            commit = $core.commit
            tag    = $core.tag
        }
    }
    else {
        $null
    }

    nodes = $nodes | ForEach-Object {
        @{
            name   = $_.name
            path   = $_.path
            url    = $_.url
            commit = $_.commit
            tag    = $_.tag
        }
    }

    python = @{
        interpreter = if (Test-Path $VenvPy) { (Resolve-Path $VenvPy).Path } else { $null }
        freeze      = $freeze
    }
}

$dest = Join-Path $repo $Out
New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
$lock | ConvertTo-Json -Depth 6 | Set-Content $dest -Encoding UTF8
Write-Host "Wrote $dest"
Write-Host "`nYou can now run Tools/Restore-FromLock.ps1 to restore this state." -ForegroundColor Yellow 