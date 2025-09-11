@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ===============================================================
REM  backup_and_tag.bat  (robust v2)
REM  - Git snapshot (commit+tag+push)
REM  - Optional data mirror via Robocopy (prompt Y/N)
REM  - Sanitizes the optional note to avoid commit message parsing issues
REM  - Ensures backup_logs are not staged even if not in .gitignore
REM ===============================================================

REM -------- CONFIG (EDIT THESE) --------
set "REPO=E:\ComfyUI_windows_portable"
set "DATA=E:\ComfyUI_data"
set "DEST=F:\ComfyUI_data_backup"
REM -------------------------------------

REM -------- timestamp + logs --------
mkdir "%REPO%\backup_logs" 2>nul
pushd "%REPO%"

for /f "tokens=1-4 delims=/.- " %%a in ("%date%") do set "D=%%d%%b%%c"
for /f "tokens=1-3 delims=:." %%a in ("%time%") do set "T=%%a%%b%%c"
set "ts=%D%_%T%"
set "ts=%ts: =0%"
set "LOG_GIT=backup_logs\git_%ts%.log"
set "LOG_COPY=backup_logs\robocopy_%ts%.log"

REM -------- sanitize optional note (strip quotes) --------
set "NOTE=%*"
set "NOTE=%NOTE:"=%"

echo ===============================================================
echo  ComfyUI backup_and_tag - %DATE% %TIME%
echo  REPO: %REPO%
echo  DATA: %DATA%
echo  DEST: %DEST%
echo  TAG : backup-%ts%
echo  NOTE: %NOTE%
echo ===============================================================

REM -------- sanity checks --------
if not exist ".git" (
  echo [ERROR] This does not look like a Git repo: %REPO%
  pause
  exit /b 1
)
if not exist "%DATA%" (
  echo [WARN] External data folder not found: %DATA%
)

REM -------- GIT SNAPSHOT (commit + tag + push) --------
echo.
echo [GIT] Staging all changes...
git add -A >> "%LOG_GIT" 2>&1

REM Don't accidentally commit our backup logs:
git restore --staged backup_logs\* 2>nul

echo [GIT] Committing (message includes timestamp + optional note)...
git commit -m "Checkpoint: %ts% %NOTE%" >> "%LOG_GIT" 2>&1

echo [GIT] Creating annotated tag backup-%ts% ...
git tag -a "backup-%ts%" -m "Backup snapshot %ts% %NOTE%" >> "%LOG_GIT" 2>&1

echo [GIT] Pushing commits...
git push >> "%LOG_GIT" 2>&1

echo [GIT] Pushing tags...
git push --tags >> "%LOG_GIT" 2>&1

REM -------- ASK USER ABOUT DATA BACKUP --------
echo.
choice /C YN /N /M "Do you want to back up external data (E:\ComfyUI_data -> F:\ComfyUI_data_backup)? [Y/N] "
set "ANS=%ERRORLEVEL%"
if "%ANS%"=="2" goto SKIP_COPY
if "%ANS%"=="1" goto DO_COPY
goto SKIP_COPY

:DO_COPY
echo [COPY] Mirroring external data to DEST (this may take a while)...
echo [COPY] Logging to %LOG_COPY%
robocopy "%DATA%" "%DEST%" /MIR /R:1 /W:1 /XD temp "outputs\temp" /XF *.tmp /LOG+:"%LOG_COPY%"
set "RC=%ERRORLEVEL%"
echo [DONE] Robocopy exit code: %RC%
echo     0-7 are typically OK. See 'robocopy /?' for meanings.
goto AFTER_COPY

:SKIP_COPY
echo [SKIP] Data backup skipped.

:AFTER_COPY
echo.
echo [DONE] Git log:   %LOG_GIT%
echo [DONE] Copy log:  %LOG_COPY%
echo.
pause

popd
exit /b 0
