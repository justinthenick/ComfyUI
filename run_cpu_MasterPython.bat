@echo off
setlocal EnableExtensions

REM ===== logging =====
mkdir logs 2>nul
set "ts=%date:~10,4%%date:~4,2%%date:~7,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
set "ts=%ts: =0%"
set "LOG=logs\comfyui_%ts%.log"

REM ===== python (system) =====
set "PYEXE=C:\Users\justi\AppData\Local\Programs\Python\Python310\python.exe"
set PYTHONUTF8=1

REM ===== external user & output dirs =====
set "COMFYUI_USER_PATH=E:\ComfyUI_data\user"
set "OUTDIR=E:\ComfyUI_data\outputs"
set "TEMPDIR=E:\ComfyUI_data\outputs\temp"

echo ========================================================= > "%LOG%"
echo Launching ComfyUI: %DATE% %TIME% >> "%LOG%"
echo PY:   %PYEXE% >> "%LOG%"
echo USER: %COMFYUI_USER_PATH% >> "%LOG%"
echo OUT:  %OUTDIR% >> "%LOG%"
echo TMP:  %TEMPDIR% >> "%LOG%"
echo --------------------------------------------------------- >> "%LOG%"

REM ===== run comfyui =====
"%PYEXE%" -u -s .\ComfyUI\main.py ^
  --cpu --windows-standalone-build ^
  --extra-model-paths "%~dp0extra_model_paths.yaml" ^
  --user-directory "%COMFYUI_USER_PATH%" ^
  --output-directory "%OUTDIR%" ^
  --temp-directory "%TEMPDIR%" ^
  >> "%LOG%" 2>&1

echo.>> "%LOG%"
echo Run finished: %DATE% %TIME% >> "%LOG%"
echo ========================================================= >> "%LOG%"
echo Log written to: %LOG%
echo.
echo Done. Press any key to close...
pause >nul

endlocal
