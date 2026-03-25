@echo off
setlocal EnableExtensions

rem ============================================================================
rem LewisMD Windows bootstrap
rem ----------------------------------------------------------------------------
rem This script prepares the optional Windows launcher runtime one time:
rem   1. verifies that portable Ruby exists
rem   2. verifies that the launcher defaults still match .ruby-version
rem   3. installs Bundler into the portable Ruby if needed
rem   4. configures a repo-local bundle path for Windows
rem   5. installs the gems needed for local launcher use
rem
rem The actual day-to-day app launch will live in later scripts. Keeping setup
rem separate means normal launches stay fast and predictable.
rem ============================================================================

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "REPO_ROOT=%%~fI"
set "DEFAULTS_FILE=%SCRIPT_DIR%launcher.defaults.psd1"
set "INSTALLER_SCRIPT=%SCRIPT_DIR%install_ruby_runtime.ps1"

set "CHECK_ONLY="
set "INSTALL_ALL_GROUPS="
set "BUNDLE_WITHOUT_GROUPS=test"

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="--help" goto usage
if /I "%~1"=="/?" goto usage
if /I "%~1"=="--check-only" (
  set "CHECK_ONLY=1"
  shift
  goto parse_args
)
if /I "%~1"=="--all-groups" (
  set "INSTALL_ALL_GROUPS=1"
  set "BUNDLE_WITHOUT_GROUPS="
  shift
  goto parse_args
)

echo [bootstrap] Unknown option: %~1
echo.
goto usage_error

:args_done
if not exist "%DEFAULTS_FILE%" (
  echo [bootstrap] Launcher defaults file not found:
  echo [bootstrap]   %DEFAULTS_FILE%
  exit /b 1
)

pushd "%REPO_ROOT%" >nul || (
  echo [bootstrap] Failed to enter repo root:
  echo [bootstrap]   %REPO_ROOT%
  exit /b 1
)

call :load_defaults
if errorlevel 1 goto fail
set "PROJECT_RUBY_VERSION="
for /f "usebackq delims=" %%A in ("%REPO_ROOT%\.ruby-version") do (
  set "PROJECT_RUBY_VERSION=%%A"
)
if not defined PROJECT_RUBY_VERSION (
  echo [bootstrap] Failed to read .ruby-version from the repo root.
  goto fail
)

if /I not "%PROJECT_RUBY_VERSION%"=="%RubyVersion%" (
  echo [bootstrap] launcher.defaults.psd1 is out of sync with .ruby-version.
  echo [bootstrap]   launcher.defaults.psd1: %RubyVersion%
  echo [bootstrap]   .ruby-version:          %PROJECT_RUBY_VERSION%
  echo [bootstrap] Update the launcher defaults before continuing.
  goto fail
)

set "RUBY_EXE=%REPO_ROOT%\%PortableRubyDir%\bin\ruby.exe"
set "GEM_CMD=%REPO_ROOT%\%PortableRubyDir%\bin\gem.cmd"
set "BUNDLE_CMD=%REPO_ROOT%\%PortableRubyDir%\bin\bundle.bat"
set "RIDK_CMD=%REPO_ROOT%\%PortableRubyDir%\bin\ridk.cmd"
set "NOTES_DIR=%REPO_ROOT%\%DefaultNotesPath%"
set "STATE_DIR=%REPO_ROOT%\%StateDirectory%"
set "BUNDLE_PATH_ABS=%REPO_ROOT%\%BundlePath%"

if not exist "%STATE_DIR%" mkdir "%STATE_DIR%" >nul 2>&1
set "LAUNCHER_LOG=%STATE_DIR%\launcher.log"
call :log "Bootstrap started."

echo [bootstrap] Repo root:          %REPO_ROOT%
echo [bootstrap] Portable Ruby dir:  %PortableRubyDir%
echo [bootstrap] Ruby version:       %RubyVersion%
echo [bootstrap] Rails environment:  %RailsEnvironment%
echo [bootstrap] Bundle path:        %BundlePath%
echo [bootstrap] Notes path:         %DefaultNotesPath%

if not exist "%RUBY_EXE%" (
  if defined CHECK_ONLY (
    call :log "Portable Ruby was not found at %RUBY_EXE%."
    echo [bootstrap] portable Ruby was not found.
    echo [bootstrap] Expected:
    echo [bootstrap]   %RUBY_EXE%
    echo [bootstrap] Run this script without --check-only to download and install
    echo [bootstrap] the repo-local Windows runtime automatically.
    echo [bootstrap] You can still install it manually if you prefer:
    echo [bootstrap]   %REPO_ROOT%\%PortableRubyDir%
    goto fail
  )

  if not exist "%INSTALLER_SCRIPT%" (
    call :log "Runtime installer helper is missing."
    echo [bootstrap] Runtime installer helper is missing:
    echo [bootstrap]   %INSTALLER_SCRIPT%
    goto fail
  )

  echo [bootstrap] Repo-local Ruby runtime is missing.
  echo [bootstrap] Downloading and installing it automatically...
  call :log "Portable Ruby was not found at %RUBY_EXE%. Starting automatic runtime install."
  powershell -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER_SCRIPT%" -RepoRoot "%REPO_ROOT%" -InstallDir "%REPO_ROOT%\%PortableRubyDir%" -RubyExePath "%RUBY_EXE%" -LauncherLogFile "%LAUNCHER_LOG%" -InstallerUrl "%PortableRubyInstallerUrl%"
  if errorlevel 1 goto fail
  if not exist "%RUBY_EXE%" (
    call :log "Automatic runtime install completed without creating ruby.exe."
    echo [bootstrap] Runtime installation completed, but ruby.exe is still missing:
    echo [bootstrap]   %RUBY_EXE%
    goto fail
  )
)

if not exist "%NOTES_DIR%" (
  echo [bootstrap] Creating notes directory...
  mkdir "%NOTES_DIR%" || goto fail
)

if not exist "%STATE_DIR%" (
  echo [bootstrap] Creating launcher state directory...
  mkdir "%STATE_DIR%" || goto fail
)

echo [bootstrap] Checking portable Ruby...
"%RUBY_EXE%" --version || goto fail

echo [bootstrap] Checking Bundler...
call "%BUNDLE_CMD%" --version >nul 2>&1
if errorlevel 1 (
  echo [bootstrap] Bundler not found in portable Ruby. Installing...
  call :log "Bundler not found in the portable runtime. Installing it now."
  call "%GEM_CMD%" install bundler --no-document || goto fail
) else (
  echo [bootstrap] Bundler is already available.
  call :log "Bundler is already available."
)

if exist "%RIDK_CMD%" (
  echo [bootstrap] Initializing the RubyInstaller Devkit...
  call :log "Ensuring the RubyInstaller Devkit is initialized."
  call "%RIDK_CMD%" install 1 || goto fail

  echo [bootstrap] Ensuring libyaml headers are installed...
  call :log "Ensuring the UCRT libyaml package is installed."
  call "%RIDK_CMD%" exec pacman -S --noconfirm --needed mingw-w64-ucrt-x86_64-libyaml || goto fail
)

echo [bootstrap] Configuring local bundle path...
call "%BUNDLE_CMD%" config set --local path "%BundlePath%" || goto fail

if defined INSTALL_ALL_GROUPS (
  echo [bootstrap] Installing all Bundler groups for this repo-local runtime.
  call "%BUNDLE_CMD%" config unset --local without >nul 2>&1
) else (
  echo [bootstrap] Excluding the test group for the personal launcher runtime.
  call "%BUNDLE_CMD%" config set --local without "%BUNDLE_WITHOUT_GROUPS%" || goto fail
)

if defined CHECK_ONLY (
  echo [bootstrap] Checking whether required gems are already installed...
  call "%BUNDLE_CMD%" check >nul 2>&1
  if errorlevel 1 (
    call :log "Check-only mode detected missing Bundler dependencies."
    echo [bootstrap] Required gems are not installed yet for the Windows launcher.
    echo [bootstrap] Re-run this script without --check-only to install them.
    goto fail
  )

  call :log "Check-only mode completed successfully."
  echo [bootstrap] Check-only mode complete. The Windows runtime is ready.
  goto success
)

echo [bootstrap] Checking whether required gems are already installed...
call "%BUNDLE_CMD%" check >nul 2>&1
if not errorlevel 1 (
  call :log "Bundler dependencies are already satisfied."
  echo [bootstrap] Gems are already satisfied for the Windows launcher runtime.
  goto success
)

echo [bootstrap] Installing gems into %BUNDLE_PATH_ABS% ...
call :log "Installing Bundler dependencies into %BUNDLE_PATH_ABS%."
call "%BUNDLE_CMD%" install || goto fail

:success
call :log "Bootstrap completed successfully."
echo.
echo [bootstrap] LewisMD Windows launcher bootstrap is ready.
echo [bootstrap] Next step:
echo [bootstrap]   script\windows\start_lewismd.bat
popd >nul
exit /b 0

:fail
if defined LAUNCHER_LOG call :log "Bootstrap failed."
echo.
echo [bootstrap] Bootstrap did not complete successfully.
echo [bootstrap] Re-run with the visible script so any setup issues stay visible.
popd >nul
exit /b 1

:load_defaults
for /f "usebackq tokens=1,* delims==" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$d = Import-PowerShellDataFile '%DEFAULTS_FILE%'; foreach ($key in 'RubyVersion','RailsEnvironment','PortableRubyDir','PortableRubyInstallerUrl','BundlePath','DefaultNotesPath','StateDirectory') { Write-Output ($key + '=' + $d[$key]) }"`) do (
  set "%%A=%%B"
)
exit /b 0

:usage
echo LewisMD Windows bootstrap
echo.
echo Usage:
echo   script\windows\bootstrap_lewismd.bat [--check-only] [--all-groups]
echo.
echo Options:
echo   --check-only   Validate paths, Ruby, and Bundler config without installing gems
echo   --all-groups   Install all Bundler groups instead of excluding the test group
echo   --help         Show this help message
exit /b 0

:usage_error
echo Usage:
echo   script\windows\bootstrap_lewismd.bat [--check-only] [--all-groups]
exit /b 1

:log
>> "%LAUNCHER_LOG%" echo [%DATE% %TIME%] [bootstrap] %~1
exit /b 0
