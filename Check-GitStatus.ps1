param([string]$Root = "E:\ComfyUI_windows_portable")

Write-Host "=== Branch & Tracking ===" -ForegroundColor Cyan
git -C $Root status -sb   # shows branch, upstream, ahead/behind

Write-Host "`n=== Wrapper Remote ===" -ForegroundColor Cyan
git -C $Root remote -v

Write-Host "`n=== Submodule (ComfyUI) ===" -ForegroundColor Cyan
git -C (Join-Path $Root "ComfyUI") rev-parse --short HEAD
git -C (Join-Path $Root "ComfyUI") remote -v

Write-Host "`n=== Manager ===" -ForegroundColor Cyan
$mgr = Join-Path $Root "ComfyUI\custom_nodes\ComfyUI-Manager"
if (Test-Path $mgr) {
    git -C $mgr rev-parse --short HEAD
    git -C $mgr remote -v
} else {
    Write-Host "ComfyUI-Manager not found at $mgr" -ForegroundColor Yellow
}
