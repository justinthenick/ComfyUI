<#
Migrate current repo to "wrapper + submodule" structure.
- Adds official ComfyUI as submodule at .\ComfyUI
- Preserves your custom files at repo root (YAML, BATs, custom_nodes)
- Moves legacy core ComfyUI files/dirs to a timestamped backup folder
- Sets up COMFYUI_USER_PATH
Run from: E:\ComfyUI_windows_portable
#>

param(
    [switch]$Force
)

function Require-CleanTree {
    $status = (git status --porcelain)
    if ($status -and -not $Force) {
        Write-Error "Working tree is not clean. Commit or stash your changes, or re-run with -Force."
        exit 1
    }
}

function New-BackupFolder {
    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $backup = Join-Path (Split-Path -Parent (Get-Location)) ("_backup_ComfyUI_root_" + $stamp)
    if (-not (Test-Path $backup)) {
        New-Item -ItemType Directory -Path $backup | Out-Null
    }
    return $backup
}

# 0) Preconditions
git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "This directory is not a git repo. Aborting."
    exit 1
}

Require-CleanTree

# 1) Save state tag (optional)
git tag -l pre-wrapper *> $null
if (-not (git tag -l pre-wrapper)) {
    git tag -a pre-wrapper -m "Snapshot before switching to wrapper+submodule structure"
}

# 2) New branch for the migration
git checkout -B repo-migrate/wrapper

# 3) Identify legacy core files/dirs to move out of the way
$legacyDirs = @(
    ".ci", ".github", "alembic_db", "api_server", "app",
    "comfy", "comfy_api", "comfy_api_nodes", "comfy_config",
    "comfy_execution", "comfy_extras", "middleware",
    "models", "output", "script_examples", "tests", "tests-unit", "utils", "input"
)
$legacyFiles = @(
    "alembic.ini", "CODEOWNERS", "comfyui_version.py", "CONTRIBUTING.md",
    "cuda_malloc.py", "execution.py", "extra_model_paths.yaml.example",
    "folder_paths.py", "hook_breaker_ac10a0.py", "latent_preview.py",
    "LICENSE", "main.py", "new_updater.py", "nodes.py", "node_helpers.py",
    "protocol.py", "pyproject.toml", "pytest.ini", "README.md", "requirements.txt", "server.py"
)

$backup = New-BackupFolder
Write-Host "Backup folder: $backup"

# 4) Move legacy core content to backup
foreach ($d in $legacyDirs) {
    if (Test-Path $d) {
        Write-Host "Moving directory $d -> $backup"
        Move-Item $d -Destination $backup -Force
    }
}
foreach ($f in $legacyFiles) {
    if (Test-Path $f) {
        Write-Host "Moving file $f -> $backup"
        Move-Item $f -Destination $backup -Force
    }
}

# 5) Add official ComfyUI as submodule
if (Test-Path .\ComfyUI) { 
    Write-Error ".\ComfyUI already exists. Aborting to avoid clobber."
    exit 1
}
git submodule add https://github.com/comfyanonymous/ComfyUI.git ComfyUI
git submodule update --init --recursive

Push-Location .\ComfyUI
git fetch --tags --prune --all
# Prefer master; fall back to main if needed
$defaultBranch = "master"
$branches = (git branch -r)
if ($branches -notmatch "origin/$defaultBranch") { $defaultBranch = "main" }
git checkout -B $defaultBranch origin/$defaultBranch
Pop-Location

# 6) Track branch in .gitmodules for easy updates
git config -f .gitmodules submodule.ComfyUI.branch $defaultBranch
git submodule sync --recursive
git add .gitmodules ComfyUI

# 7) Ensure .gitignore keeps submodule's user dir out of repo
$giLine = "ComfyUI/user/"
$giPath = ".gitignore"
$giText = if (Test-Path $giPath) { Get-Content $giPath -Raw } else { "" }
if ($giText -notmatch [regex]::Escape($giLine)) {
    Add-Content $giPath "`n# keep ComfyUI submodule user data out of repo`n$giLine"
    git add $giPath
}

# 8) Set COMFYUI_USER_PATH to external location
$externalUser = "E:\ComfyUI_data\user"
$env:COMFYUI_USER_PATH = $externalUser
[System.Environment]::SetEnvironmentVariable("COMFYUI_USER_PATH", $externalUser, "User")

# 9) Commit migration
git commit -m "Migrate to wrapper+submodule: add ComfyUI submodule; move legacy core to backup; set branch tracking"

Write-Host "Done. Launch with:"
Write-Host '  py310 -u -s .\ComfyUI\main.py --cpu --windows-standalone-build'
Write-Host "Manager & nodes can live at: .\custom_nodes\... (submodules welcome)"
