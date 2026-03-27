# frozen_string_literal: true

require "test_helper"

class ConfigControllerTest < ActionDispatch::IntegrationTest
  def setup
    setup_test_notes_dir
  end

  def teardown
    teardown_test_notes_dir
  end

  # === show ===

  test "show returns UI settings and features" do
    get config_url, as: :json
    assert_response :success

    data = JSON.parse(response.body)

    # Should include settings
    assert data.key?("settings")
    settings = data["settings"]
    assert settings.key?("theme")
    assert settings.key?("editor_font")
    assert settings.key?("editor_font_size")
    assert settings.key?("preview_zoom")
    assert settings.key?("preview_width")
    assert settings.key?("preview_font_family")
    assert settings.key?("sidebar_visible")
    assert settings.key?("active_mode")
    assert settings.key?("last_open_note")
    assert settings.key?("explorer_expanded_folders")
    assert settings.key?("typewriter_mode")

    # Should include features
    assert data.key?("features")
    features = data["features"]
    assert features.key?("s3_upload")
    assert features.key?("youtube_search")
    assert features.key?("google_search")
    assert features.key?("local_images")
  end

  test "show returns default values" do
    get config_url, as: :json
    assert_response :success

    data = JSON.parse(response.body)
    settings = data["settings"]

    assert_equal "cascadia-code", settings["editor_font"]
    assert_equal 14, settings["editor_font_size"]
    assert_equal 100, settings["preview_zoom"]
    assert_equal 40, settings["preview_width"]
    assert_equal "sans", settings["preview_font_family"]
    assert_equal true, settings["sidebar_visible"]
    assert_nil settings["active_mode"]
    assert_nil settings["last_open_note"]
    assert_nil settings["explorer_expanded_folders"]
    assert_equal false, settings["typewriter_mode"]
  end

  test "show returns configured values from file" do
    @test_notes_dir.join(".fed").write(<<~CONFIG)
      theme = gruvbox
      editor_font = hack
      preview_width = 55
      preview_font_family = serif
      active_mode = preview
      last_open_note = "Writing/Current Draft.md"
      explorer_expanded_folders = Writing,Writing%2FDrafts
      typewriter_mode = true
    CONFIG

    get config_url, as: :json
    assert_response :success

    data = JSON.parse(response.body)
    settings = data["settings"]

    assert_equal "gruvbox", settings["theme"]
    assert_equal "hack", settings["editor_font"]
    assert_equal 55, settings["preview_width"]
    assert_equal "serif", settings["preview_font_family"]
    assert_equal "preview", settings["active_mode"]
    assert_equal "Writing/Current Draft.md", settings["last_open_note"]
    assert_equal "Writing,Writing%2FDrafts", settings["explorer_expanded_folders"]
    assert_equal true, settings["typewriter_mode"]
  end

  # === update ===

  test "update saves UI settings" do
    patch config_url, params: { theme: "dark", editor_font_size: 18, preview_font_family: "serif", preview_width: 58, active_mode: "reading", last_open_note: "Writing/Current Draft.md", explorer_expanded_folders: "Writing,Writing%2FDrafts" }, as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "dark", data["settings"]["theme"]
    assert_equal 18, data["settings"]["editor_font_size"]
    assert_equal "serif", data["settings"]["preview_font_family"]
    assert_equal 58, data["settings"]["preview_width"]
    assert_equal "reading", data["settings"]["active_mode"]
    assert_equal "Writing/Current Draft.md", data["settings"]["last_open_note"]
    assert_equal "Writing,Writing%2FDrafts", data["settings"]["explorer_expanded_folders"]

    # Verify persistence
    get config_url, as: :json
    data = JSON.parse(response.body)
    assert_equal "dark", data["settings"]["theme"]
    assert_equal 18, data["settings"]["editor_font_size"]
    assert_equal "serif", data["settings"]["preview_font_family"]
    assert_equal 58, data["settings"]["preview_width"]
    assert_equal "reading", data["settings"]["active_mode"]
    assert_equal "Writing/Current Draft.md", data["settings"]["last_open_note"]
    assert_equal "Writing,Writing%2FDrafts", data["settings"]["explorer_expanded_folders"]
  end

  test "update rejects non-UI settings" do
    patch config_url, params: { aws_access_key_id: "hack-attempt" }, as: :json
    assert_response :unprocessable_entity

    # Verify not saved
    content = @test_notes_dir.join(".fed").read
    refute_includes content, "hack-attempt"
  end

  test "update handles partial updates" do
    # First set theme
    patch config_url, params: { theme: "dark" }, as: :json
    assert_response :success

    # Then set font without affecting theme
    patch config_url, params: { editor_font: "hack" }, as: :json
    assert_response :success

    get config_url, as: :json
    data = JSON.parse(response.body)
    assert_equal "dark", data["settings"]["theme"]
    assert_equal "hack", data["settings"]["editor_font"]
  end

  test "update saves locale setting and returns updated settings" do
    patch config_url, params: { locale: "pt-BR" }, as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "pt-BR", data["settings"]["locale"]

    # Verify persistence - subsequent GET should return the saved locale
    get config_url, as: :json
    data = JSON.parse(response.body)
    assert_equal "pt-BR", data["settings"]["locale"]
  end

  test "update returns error for empty params" do
    patch config_url, params: {}, as: :json
    assert_response :unprocessable_entity

    data = JSON.parse(response.body)
    assert_includes data["error"], "No valid settings"
  end

  test "update handles boolean values" do
    patch config_url, params: { typewriter_mode: true, sidebar_visible: false }, as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal true, data["settings"]["typewriter_mode"]
    assert_equal false, data["settings"]["sidebar_visible"]
  end

  test "update writes font settings to file" do
    patch config_url, params: { editor_font: "hack", editor_font_size: 20, preview_font_family: "serif" }, as: :json
    assert_response :success

    # Verify the file actually contains the new values
    content = @test_notes_dir.join(".fed").read
    assert_includes content, "editor_font = hack"
    assert_includes content, "editor_font_size = 20"
    assert_includes content, "preview_font_family = serif"
  end

  test "update preserves existing file content when adding new settings" do
    # Start with just theme
    @test_notes_dir.join(".fed").write("theme = tokyo-night\n")

    # Add font settings
    patch config_url, params: { editor_font: "fira-code" }, as: :json
    assert_response :success

    content = @test_notes_dir.join(".fed").read
    # Original theme preserved
    assert_includes content, "theme = tokyo-night"
    # New font added
    assert_includes content, "editor_font = fira-code"
  end

  # === editor partial ===

  test "editor returns HTML partial with config data attributes" do
    get "/config/editor"
    assert_response :success

    assert_includes response.body, 'id="editor-config"'
    assert_includes response.body, 'data-controller="editor-config"'
    assert_includes response.body, "data-editor-config-font-value"
    assert_includes response.body, "data-editor-config-font-size-value"
    assert_includes response.body, "data-editor-config-editor-width-value"
    assert_includes response.body, "data-editor-config-preview-zoom-value"
    assert_includes response.body, "data-editor-config-preview-width-value"
    assert_includes response.body, "data-editor-config-preview-font-family-value"
    assert_includes response.body, "data-editor-config-active-mode-value"
    assert_includes response.body, "data-editor-config-theme-value"
  end

  test "editor partial reflects configured values" do
    @test_notes_dir.join(".fed").write(<<~CONFIG)
      editor_font = hack
      editor_font_size = 20
      preview_width = 52
      preview_font_family = mono
      active_mode = preview
      theme = gruvbox
    CONFIG

    get "/config/editor"
    assert_response :success

    assert_includes response.body, 'data-editor-config-font-value="hack"'
    assert_includes response.body, 'data-editor-config-font-size-value="20"'
    assert_includes response.body, 'data-editor-config-preview-width-value="52"'
    assert_includes response.body, 'data-editor-config-preview-font-family-value="mono"'
    assert_includes response.body, 'data-editor-config-active-mode-value="preview"'
    assert_includes response.body, 'data-editor-config-theme-value="gruvbox"'
  end

  test "editor partial uses defaults when no config file" do
    get "/config/editor"
    assert_response :success

    assert_includes response.body, 'data-editor-config-font-value="cascadia-code"'
    assert_includes response.body, 'data-editor-config-font-size-value="14"'
    assert_includes response.body, 'data-editor-config-editor-width-value="72"'
    assert_includes response.body, 'data-editor-config-preview-zoom-value="100"'
    assert_includes response.body, 'data-editor-config-preview-width-value="40"'
    assert_includes response.body, 'data-editor-config-preview-font-family-value="sans"'
    assert_includes response.body, 'data-editor-config-active-mode-value=""'
  end
end
