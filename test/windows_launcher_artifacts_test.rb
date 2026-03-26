# frozen_string_literal: true

require "test_helper"

class WindowsLauncherArtifactsTest < ActiveSupport::TestCase
  test "launcher defaults expose a splash-readable progress file" do
    defaults = Rails.root.join("script", "windows", "launcher.defaults.psd1").read

    assert_includes defaults, 'ProgressFile = "tmp/windows-launcher/launcher-progress.json"'
  end

  test "windows splash helper reads launcher progress and validates without launching" do
    splash_script = Rails.root.join("script", "windows", "show_lewismd_splash.ps1").read

    assert_includes splash_script, "PresentationFramework"
    assert_includes splash_script, "Read-ProgressPayload"
    assert_includes splash_script, "ProgressFile"
    assert_includes splash_script, "public\\icon.png"
    assert_includes splash_script, "[switch]$ValidateOnly"
    assert_includes splash_script, "LewisMD couldn't finish starting"
  end

  test "windows launcher readme documents the splash helper contract" do
    readme = Rails.root.join("script", "windows", "README.md").read

    assert_includes readme, "show_lewismd_splash.ps1"
    assert_includes readme, "launcher-progress.json"
    assert_includes readme, "-ValidateOnly"
  end
end
