[CmdletBinding()]
param(
  [string]$Lock = ".\inventory\stack.lock.json",
  [switch]$PipInstall  # do pip install -r from lock (best-effort)
)
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not (Test-Path $Lock)) { throw "Lock not found: $Lock" }

$lock = Get-Content $Lock -Raw | ConvertFrom-Json

# 1) Ensure all submodules present
git -C $repo submodule update --init --recursive

# 2) Checkout exact SHAs
$all = @($lock.core) + @($lock.nodes)
foreach ($m in $all) {
  $p = Join-Path $repo $m.path
  if (-not (Test-Path $p)) { throw "Missing submodule path: $($m.path)" }
  git -C $p fetch --tags --all --quiet
  git -C $p checkout $m.commit
}

# 3) Python restore
$py = $lock.python.interpreter
if ($PipInstall -and (Test-Path $py)) {
  # Write requirements.lock.txt from freeze list
  $req = Join-Path $repo ".\inventory\requirements.lock.txt"
  $lock.python.freeze | Set-Content $req -Encoding UTF8
  & $py -m pip install -r $req
  Write-Host "Installed python packages from lock."
} else {
  Write-Host "Skip pip install (use -PipInstall to enable)."
}

Write-Host "Restore done."
Write-Host "`nYou may want to run Tools/Checkpoint-Submodules.ps1 to commit any pointer changes." -ForegroundColor Yellow
Write-Host "You can also run Tools/Convert-NodesToSubmodules.ps1 to convert any loose nodes to submodules." -ForegroundColor Yellow 