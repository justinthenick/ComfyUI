param([string]$Out = ".\inventory\nodes.json")
$Root = Split-Path -Parent $PSCommandPath
$CN = Join-Path $Root "..\custom_nodes"
$items = @()

Get-ChildItem $CN -Directory | ForEach-Object {
  $dir = $_.FullName
  $git = Test-Path (Join-Path $dir ".git")
  $o = [ordered]@{
    name   = $_.Name
    path   = $dir
    isGit  = $git
    remote = $null
    branch = $null
    commit = $null
    reqs   = @()
  }
  if ($git) {
    $o.remote = (git -C $dir remote get-url origin 2>$null)
    $o.branch = (git -C $dir rev-parse --abbrev-ref HEAD 2>$null)
    $o.commit = (git -C $dir rev-parse --short HEAD 2>$null)
  }
  Get-ChildItem $dir -Filter requirements.txt -Recurse -ErrorAction SilentlyContinue |
    ForEach-Object { $o.reqs += (Get-Content $_.FullName) }
  $items += $o
}

New-Item -ItemType Directory -Force -Path (Split-Path $Out) | Out-Null
$items | ConvertTo-Json -Depth 5 | Set-Content $Out -Encoding UTF8
Write-Host "Wrote $Out"