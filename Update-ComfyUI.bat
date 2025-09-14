@echo off
setlocal

set "ROOT=%~dp0"
set "PORTABLE=%ROOT%"
set "APP=%PORTABLE%ComfyUI"

REM If Git complains about “dubious ownership”, whitelist this folder:
git -C "%PORTABLE%" config --global --add safe.directory "%PORTABLE%"

REM Update core + submodules
git -C "%APP%" fetch --all
git -C "%APP%" reset --hard origin/master
git -C "%APP%" submodule update --init --recursive

echo.
echo [OK] ComfyUI updated. If custom nodes have their own repos, update them individually.
pause
