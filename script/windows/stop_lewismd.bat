@echo off
setlocal EnableExtensions

rem ============================================================================
rem LewisMD Windows stop helper
rem ----------------------------------------------------------------------------
rem This script is the manual recovery path for the optional Windows launcher.
rem
rem Its job is intentionally small:
rem   1. ask the PowerShell orchestrator to enter stop-only mode
rem   2. stop only the launcher-managed Rails process, never every ruby.exe
rem   3. clean stale launcher state if the process has already exited
rem
rem Keeping the real shutdown logic in launch_lewismd.ps1 prevents drift between
rem the normal launcher flow and this manual recovery helper.
rem ============================================================================

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "REPO_ROOT=%%~fI"
set "ORCHESTRATOR_SCRIPT=%SCRIPT_DIR%launch_lewismd.ps1"

if /I "%~1"=="--help" goto usage
if /I "%~1"=="/?" goto usage

echo [stop] LewisMD Windows stop helper
echo [stop] Repo root: %REPO_ROOT%

if not exist "%ORCHESTRATOR_SCRIPT%" (
  echo [stop] The PowerShell orchestrator is missing:
  echo [stop]   %ORCHESTRATOR_SCRIPT%
  echo [stop] Restore the Windows launcher files before trying again.
  exit /b 1
)

echo [stop] Asking the launcher orchestrator to stop any managed Rails process...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ORCHESTRATOR_SCRIPT%" -StopOnly
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  echo [stop] The stop helper exited with code %EXIT_CODE%.
  echo [stop] Review tmp\windows-launcher\launcher.log for more details.
)

exit /b %EXIT_CODE%

:usage
echo LewisMD Windows stop helper
echo.
echo Usage:
echo   script\windows\stop_lewismd.bat
echo.
echo This command stops only the Rails process launched by the Windows launcher.
echo It also removes stale launcher state if the managed process is already gone.
exit /b 0
