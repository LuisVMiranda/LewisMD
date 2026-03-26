# Windows launcher runtime contract for LewisMD.
#
# This file is intentionally small and data-only so later launcher scripts can
# load one source of truth instead of duplicating paths and assumptions.
#
# All paths are repo-relative unless explicitly overridden by environment vars.

@{
  # Match the project's checked-in Ruby line from .ruby-version.
  RubyVersion = "ruby-3.4.8"

  # The optional Windows launcher is meant for local personal use, not
  # production hosting, so development mode is the simplest supported target.
  RailsEnvironment = "development"

  # Launcher defaults. Users can override selected values with environment vars
  # listed below without modifying the scripts themselves.
  DefaultPort = 7777
  PortableRubyDir = "portable_ruby"
  PortableRubyInstallerUrl = "https://github.com/oneclick/rubyinstaller2/releases/download/RubyInstaller-3.4.8-1/rubyinstaller-devkit-3.4.8-1-x64.exe"
  BundlePath = "vendor/bundle/windows"
  DefaultNotesPath = "notes"

  # Runtime state for PID tracking, logs, and the dedicated browser app profile.
  StateDirectory = "tmp/windows-launcher"
  RailsLogFile = "tmp/windows-launcher/rails.log"
  LauncherLogFile = "tmp/windows-launcher/launcher.log"
  StateFile = "tmp/windows-launcher/launcher-state.json"
  BrowserProfileDir = "tmp/windows-launcher/browser-profile"

  # The Rails health endpoint is preferred over blind startup sleeps.
  HealthEndpointPath = "/up"

  # Preferred browsers for native app-mode launching.
  BrowserCommands = @(
    "msedge",
    "chrome"
  )

  # Browser startup/shutdown smoothing for the dedicated LewisMD profile.
  BrowserStartupTimeoutSeconds = 12
  BrowserSessionStabilitySeconds = 2
  BrowserShutdownStabilitySeconds = 2
  BrowserLaunchRetryCount = 2
  BrowserLaunchRetryDelaySeconds = 2

  # Supported environment variable overrides for personal local use.
  EnvironmentOverrides = @(
    "LEWISMD_PORT",
    "LEWISMD_BROWSER",
    "LEWISMD_NOTES_PATH"
  )
}
