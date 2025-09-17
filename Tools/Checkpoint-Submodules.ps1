[CmdletBinding()]
param([string]$Message = "chore: checkpoint submodule pointers after updates")

$repo = Split-Path -Parent $PSCommandPath | Join-Path -ChildPath ".."
$repo = (Resolve-Path $repo).Path

# Stage only submodule pointer changes (no dirty content inside)
$changed = git -C $repo submodule summary
if ([string]::IsNullOrWhiteSpace($changed)) {
  Write-Host "No submodule pointer changes." -ForegroundColor Yellow
  exit 0
}

# Add any submodule paths that changed pointers
$paths = (git -C $repo submodule foreach --quiet 'echo $path')
foreach ($p in $paths) {
  git -C $repo add $p 2>$null
}

git -C $repo commit -m $Message
Write-Host "Committed new pointers." -ForegroundColor Green
