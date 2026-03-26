# frozen_string_literal: true

require "test_helper"

class WindowsLauncherArtifactsTest < ActiveSupport::TestCase
  test "launcher defaults expose a splash-readable progress file" do
    defaults = Rails.root.join("script", "windows", "launcher.defaults.psd1").read

    assert_includes defaults, 'ProgressFile = "tmp/windows-launcher/launcher-progress.json"'
  end

  test "windows splash helper uses an hta shell with launcher progress polling" do
    splash_script = Rails.root.join("script", "windows", "show_lewismd_splash.hta").read

    assert_includes splash_script, "<hta:application"
    assert_includes splash_script, 'applicationname="LewisMDSplash"'
    assert_includes splash_script, 'showintaskbar="no"'
    assert_includes splash_script, "Scripting.FileSystemObject"
    assert_includes splash_script, "launcher-progress.json"
    assert_includes splash_script, "window.resizeTo"
    assert_includes splash_script, "window.moveTo"
    assert_includes splash_script, "shell.AppActivate(document.title)"
    assert_includes splash_script, "window.setInterval(pollProgress, 250)"
    assert_includes splash_script, "LewisMD couldn't finish starting"
    assert_includes splash_script, "Open the visible launcher for details:"
    assert_includes splash_script, "<title>LewisMD Launching</title>"
  end

  test "hidden launcher starts the splash helper before launching the app" do
    hidden_launcher = Rails.root.join("script", "windows", "Launch_LewisMD.vbs").read

    assert_includes hidden_launcher, "show_lewismd_splash.hta"
    assert_includes hidden_launcher, "launcher-progress.json"
    assert_includes hidden_launcher, "splashCommand"
    assert_includes hidden_launcher, "mshta.exe"
    assert_includes hidden_launcher, "splashWindowStyle = 1"
    assert_includes hidden_launcher, "shell.Run splashCommand, splashWindowStyle, False"
    assert_includes hidden_launcher, "WriteProgressErrorPayload"
    assert_includes hidden_launcher, "IsoTimestamp"
    assert_includes hidden_launcher, "WScript.Sleep 150"
  end

  test "windows launcher readme documents the splash helper contract" do
    readme = Rails.root.join("script", "windows", "README.md").read

    assert_includes readme, "show_lewismd_splash.hta"
    assert_includes readme, "launcher-progress.json"
    assert_includes readme, "mshta.exe"
  end
end
