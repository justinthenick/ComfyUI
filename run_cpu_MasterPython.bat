mkdir logs 2>nul
set "ts=%date:~10,4%%date:~4,2%%date:~7,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
set "ts=%ts: =0%"
set PYTHONUTF8=1
set COMFYUI_USER_PATH=E:\ComfyUI_data\user
REM ComfyUI auto-loads extra_model_paths.yaml in repo root; if you ever move it, pass:
REM   --extra-model-paths "%~dp0extra_model_paths.yaml"

py310.bat -u -s .\main.py --cpu --windows-standalone-build --output-directory "E:\ComfyUI_data\outputs" --temp-directory "E:\ComfyUI_data\outputs\temp">> "logs\comfyui_%ts%.log" 2>&1

pause