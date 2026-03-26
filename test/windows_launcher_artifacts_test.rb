# frozen_string_literal: true

require "test_helper"

class WindowsLauncherArtifactsTest < ActiveSupport::TestCase
  test "launcher defaults keep the launcher state contract small and data-only" do
    defaults = Rails.root.join("script", "windows", "launcher.defaults.psd1").read

    assert_includes defaults, 'StateFile = "tmp/windows-launcher/launcher-state.json"'
    assert_includes defaults, 'BrowserProfileDir = "tmp/windows-launcher/browser-profile"'
    refute_includes defaults, "ProgressFile"
  end

  test "hidden launcher delegates directly to the visible launcher without splash helpers" do
    hidden_launcher = Rails.root.join("script", "windows", "Launch_LewisMD.vbs").read

    assert_includes hidden_launcher, "start_lewismd.bat"
    assert_includes hidden_launcher, "--skip-bootstrap-check --no-auto-bootstrap --no-pause-on-error"
    assert_includes hidden_launcher, "shell.Run(command, hiddenWindowStyle, True)"
    assert_includes hidden_launcher, "CreateDesktopShortcut"
    refute_includes hidden_launcher, "show_lewismd_splash"
    refute_includes hidden_launcher, "launcher-progress.json"
    refute_includes hidden_launcher, "LewisMDSplash.exe"
  end

  test "windows launcher readme documents the lean hidden launcher flow" do
    readme = Rails.root.join("script", "windows", "README.md").read

    assert_includes readme, "Launch_LewisMD.vbs"
    assert_includes readme, "start_lewismd.bat"
    assert_includes readme, "launch_lewismd.ps1"
    refute_includes readme, "show_lewismd_splash"
    refute_includes readme, "launcher-progress.json"
  end
end
