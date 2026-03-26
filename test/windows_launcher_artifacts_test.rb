# frozen_string_literal: true

require "test_helper"

class WindowsLauncherArtifactsTest < ActiveSupport::TestCase
  test "launcher defaults expose a splash-readable progress file" do
    defaults = Rails.root.join("script", "windows", "launcher.defaults.psd1").read

    assert_includes defaults, 'ProgressFile = "tmp/windows-launcher/launcher-progress.json"'
  end

  test "windows splash helper uses a native borderless form with launcher progress polling" do
    splash_script = Rails.root.join("script", "windows", "show_lewismd_splash.cs").read

    assert_includes splash_script, "FormBorderStyle = FormBorderStyle.None"
    assert_includes splash_script, "ShowInTaskbar = false"
    assert_includes splash_script, "TopMost = true"
    assert_includes splash_script, "DataContractJsonSerializer"
    assert_includes splash_script, "FileShare.ReadWrite"
    assert_includes splash_script, "DateTimeOffset.TryParse"
    assert_includes splash_script, "spinner.StopAnimation();"
    assert_includes splash_script, "SetForegroundWindow"
    assert_includes splash_script, "Application.Run(new SplashForm("
    assert_includes splash_script, "LewisMD couldn't finish starting"
    assert_includes splash_script, "Open the visible launcher for details:"
  end

  test "hidden launcher starts the splash helper before launching the app" do
    hidden_launcher = Rails.root.join("script", "windows", "Launch_LewisMD.vbs").read

    assert_includes hidden_launcher, "show_lewismd_splash.cs"
    assert_includes hidden_launcher, "LewisMDSplash.exe"
    assert_includes hidden_launcher, "launcher-progress.json"
    assert_includes hidden_launcher, "splashCommand"
    assert_includes hidden_launcher, "ResolveCscPath()"
    assert_includes hidden_launcher, "EnsureSplashExecutable()"
    assert_includes hidden_launcher, "/target:winexe"
    assert_includes hidden_launcher, "splashWindowStyle = 1"
    assert_includes hidden_launcher, "shell.Run splashCommand, splashWindowStyle, False"
    assert_includes hidden_launcher, "WriteProgressErrorPayload"
    assert_includes hidden_launcher, "IsoTimestamp"
    assert_includes hidden_launcher, "WScript.Sleep 150"
  end

  test "windows launcher readme documents the splash helper contract" do
    readme = Rails.root.join("script", "windows", "README.md").read

    assert_includes readme, "show_lewismd_splash.cs"
    assert_includes readme, "launcher-progress.json"
    assert_includes readme, "csc.exe"
    assert_includes readme, "LewisMDSplash.exe"
  end
end
