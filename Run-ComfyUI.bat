@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-ComfyUI.ps1" %*
endlocal
