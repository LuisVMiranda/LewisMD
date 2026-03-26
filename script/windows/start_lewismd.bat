@echo off
setlocal EnableExtensions

rem ============================================================================
rem LewisMD Windows visible launcher
rem ----------------------------------------------------------------------------
rem This is the user-facing debug launcher for the optional Windows runtime.
rem
rem Its job is intentionally narrow:
rem   1. keep launch output visible in a terminal window
rem   2. verify that the one-time bootstrap has succeeded
rem   3. hand off to the PowerShell orchestrator once that script exists
rem
rem The real server/browser lifecycle lives in launch_lewismd.ps1.
rem ============================================================================

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "REPO_ROOT=%%~fI"
set "BOOTSTRAP_SCRIPT=%SCRIPT_DIR%bootstrap_lewismd.bat"
set "ORCHESTRATOR_SCRIPT=%SCRIPT_DIR%launch_lewismd.ps1"
set "STATE_DIR=%REPO_ROOT%\tmp\windows-launcher"
set "LAUNCHER_LOG=%STATE_DIR%\launcher.log"
set "SKIP_BOOTSTRAP_CHECK="
set "NO_AUTO_BOOTSTRAP="
set "NO_PAUSE_ON_ERROR="
set "ORCHESTRATOR_ATTEMPTS=0"
set "MAX_ORCHESTRATOR_ATTEMPTS=2"
set "TRANSIENT_ORCHESTRATOR_EXIT_CODE=2"
set "ORCHESTRATOR_RETRY_DELAY_SECONDS=2"
set "FORWARDED_ARGS=%*"

echo(%FORWARDED_ARGS% | findstr /I /C:"--help" /C:"/?" >nul
if not errorlevel 1 goto usage

echo(%FORWARDED_ARGS% | findstr /I /C:"--skip-bootstrap-check" >nul
if not errorlevel 1 (
  set "SKIP_BOOTSTRAP_CHECK=1"
  set "FORWARDED_ARGS=%FORWARDED_ARGS:--skip-bootstrap-check=%"
)

echo(%FORWARDED_ARGS% | findstr /I /C:"--no-auto-bootstrap" >nul
if not errorlevel 1 (
  set "NO_AUTO_BOOTSTRAP=1"
  set "FORWARDED_ARGS=%FORWARDED_ARGS:--no-auto-bootstrap=%"
)

echo(%FORWARDED_ARGS% | findstr /I /C:"--no-pause-on-error" >nul
if not errorlevel 1 (
  set "NO_PAUSE_ON_ERROR=1"
  set "FORWARDED_ARGS=%FORWARDED_ARGS:--no-pause-on-error=%"
)

if not exist "%STATE_DIR%" mkdir "%STATE_DIR%" >nul 2>&1
call :log "Visible launcher wrapper started."

echo [start] LewisMD Windows launcher
echo [start] Repo root: %REPO_ROOT%
echo [start] Visible mode is enabled so startup and failure details remain readable.

if not exist "%BOOTSTRAP_SCRIPT%" (
  call :log "Bootstrap script is missing."
  echo [start] Bootstrap script is missing:
  echo [start]   %BOOTSTRAP_SCRIPT%
  echo [start] Restore the Windows launcher files before launching again.
  call :pause_on_error
  exit /b 1
)

if not defined SKIP_BOOTSTRAP_CHECK (
  echo [start] Verifying the Windows runtime with bootstrap --check-only...
  call :log "Running bootstrap --check-only before launch."
  call "%BOOTSTRAP_SCRIPT%" --check-only
  if errorlevel 1 (
    call :log "Bootstrap validation failed."
    if defined NO_AUTO_BOOTSTRAP (
      echo.
      echo [start] Runtime validation failed.
      echo [start] Fix the issue above or run the full bootstrap first:
      echo [start]   script\windows\bootstrap_lewismd.bat
      echo [start] Launcher log: %LAUNCHER_LOG%
      call :pause_on_error
      exit /b 1
    )

    echo.
    echo [start] The quick runtime check failed.
    echo [start] Running the full bootstrap now so LewisMD can repair or install
    echo [start] the local Windows runtime before launch...
    call :log "Running the full bootstrap after validation failure."
    call "%BOOTSTRAP_SCRIPT%"
    if errorlevel 1 (
      call :log "Full bootstrap failed after validation failure."
      echo.
      echo [start] Automatic bootstrap failed.
      echo [start] Fix the issue above or rerun the bootstrap manually:
      echo [start]   script\windows\bootstrap_lewismd.bat
      echo [start] Launcher log: %LAUNCHER_LOG%
      call :pause_on_error
      exit /b 1
    )

    call :log "Full bootstrap completed successfully after validation failure."
    echo [start] Bootstrap completed successfully. Continuing launch...
  ) else (
    call :log "Bootstrap validation completed successfully."
  )
) else (
  echo [start] Skipping bootstrap validation because --skip-bootstrap-check was requested.
  call :log "Bootstrap validation skipped by request."
)

if not exist "%ORCHESTRATOR_SCRIPT%" (
  call :log "PowerShell orchestrator script is missing."
  echo.
  echo [start] The main PowerShell orchestrator is not available yet:
  echo [start]   %ORCHESTRATOR_SCRIPT%
  echo [start] This is expected until Windows launcher Phase 4 is implemented.
  echo [start] The visible launcher wrapper itself is ready, but the actual
  echo [start] server/browser startup flow has not been added yet.
  call :pause_on_error
  exit /b 1
)

echo [start] Handing off to the PowerShell orchestrator...
call :log "Delegating to launch_lewismd.ps1."
call :run_orchestrator

if not "%EXIT_CODE%"=="0" (
  echo.
  echo [start] LewisMD exited with code %EXIT_CODE%.
  echo [start] Review the messages above for the failing step.
  echo [start] Launcher log: %LAUNCHER_LOG%
  call :pause_on_error
)

exit /b %EXIT_CODE%

:run_orchestrator
set /a ORCHESTRATOR_ATTEMPTS+=1
powershell -NoProfile -ExecutionPolicy Bypass -File "%ORCHESTRATOR_SCRIPT%" %FORWARDED_ARGS%
set "EXIT_CODE=%ERRORLEVEL%"
call :log "PowerShell orchestrator exited with code %EXIT_CODE% on attempt %ORCHESTRATOR_ATTEMPTS%."

if "%EXIT_CODE%"=="%TRANSIENT_ORCHESTRATOR_EXIT_CODE%" if %ORCHESTRATOR_ATTEMPTS% lss %MAX_ORCHESTRATOR_ATTEMPTS% (
  echo [start] LewisMD hit a brief browser handoff delay while closing.
  echo [start] Retrying the launch once automatically...
  call :log "Retrying the PowerShell orchestrator after transient exit code %EXIT_CODE%."
  timeout /t %ORCHESTRATOR_RETRY_DELAY_SECONDS% /nobreak >nul
  goto run_orchestrator
)

exit /b 0

:usage
echo LewisMD Windows launcher
echo.
echo Usage:
echo   script\windows\start_lewismd.bat [launcher-options]
echo.
echo Options:
echo   --skip-bootstrap-check   Skip the bootstrap validation step
echo   --no-auto-bootstrap      Do not run the full bootstrap automatically after a failed quick check
echo   --no-pause-on-error      Exit immediately instead of waiting on failure
echo   --help                   Show this help message
echo.
echo Any unknown options are forwarded to the future PowerShell orchestrator.
exit /b 0

:log
>> "%LAUNCHER_LOG%" echo [%DATE% %TIME%] [start] %~1
exit /b 0

:pause_on_error
if defined NO_PAUSE_ON_ERROR exit /b 0
echo.
echo [start] Press any key to close this window...
pause >nul
exit /b 0
