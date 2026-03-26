# frozen_string_literal: true

require "test_helper"

class TranslationsControllerTest < ActionDispatch::IntegrationTest
  def setup
    setup_test_notes_dir
    @original_locale_env = ENV["FRANKMD_LOCALE"]
  end

  def teardown
    teardown_test_notes_dir
    # Reset locale and ENV to English after each test
    ENV["FRANKMD_LOCALE"] = @original_locale_env
    I18n.locale = :en
  end

  # === Basic Translation Endpoint ===

  test "show returns translations for default locale (en)" do
    get translations_url, as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "en", data["locale"]
    assert data.key?("translations")

    translations = data["translations"]
    # Verify structure
    assert translations.key?("common")
    assert translations.key?("dialogs")
    assert translations.key?("status")
    assert translations.key?("errors")
    assert translations.key?("success")
    assert translations.key?("editor")
    assert translations.key?("sidebar")
    assert translations.key?("export_menu")
    assert translations.key?("status_strip")
    assert translations.key?("header")
    assert translations.key?("share_view")
    assert translations.key?("confirm")
  end

  test "show returns correct English translations" do
    get translations_url, as: :json
    assert_response :success

    data = JSON.parse(response.body)
    translations = data["translations"]

    assert_equal "Cancel", translations["common"]["cancel"]
    assert_equal "Save", translations["common"]["save"]
    assert_equal "Saved", translations["status"]["saved"]
    assert_equal "Note not found", translations["errors"]["note_not_found"]
  end

  # === Locale Switching via ENV ===

  test "show returns Portuguese translations when ENV locale is pt-BR" do
    ENV["FRANKMD_LOCALE"] = "pt-BR"

    get translations_url, as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "pt-BR", data["locale"]

    translations = data["translations"]
    assert_equal "Cancelar", translations["common"]["cancel"]
    assert_equal "Salvar", translations["common"]["save"]
    assert_equal "Salvo", translations["status"]["saved"]
  end

  test "show returns Spanish translations when ENV locale is es" do
    ENV["FRANKMD_LOCALE"] = "es"

    get translations_url, as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "es", data["locale"]

    translations = data["translations"]
    assert_equal "Cancelar", translations["common"]["cancel"]
    assert_equal "Guardar", translations["common"]["save"]
    assert_equal "Guardado", translations["status"]["saved"]
  end

  test "show returns Japanese translations when ENV locale is ja" do
    ENV["FRANKMD_LOCALE"] = "ja"

    get translations_url, as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "ja", data["locale"]

    translations = data["translations"]
    assert_equal "キャンセル", translations["common"]["cancel"]
    assert_equal "保存", translations["common"]["save"]
    assert_equal "保存済み", translations["status"]["saved"]
  end

  test "show returns requested locale when locale param is provided" do
    get translations_url(locale: "es"), as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "es", data["locale"]
    assert_equal "Cancelar", data["translations"]["common"]["cancel"]
  end

  test "invalid locale param falls back to active locale" do
    get translations_url(locale: "invalid"), as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "en", data["locale"]
  end

  # === Locale Configuration via Config File ===

  test "locale can be set via config file when ENV not set" do
    ENV.delete("FRANKMD_LOCALE")
    @test_notes_dir.join(".fed").write("locale = es\n")

    get translations_url, as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "es", data["locale"]
  end

  test "locale can be saved via config endpoint" do
    ENV.delete("FRANKMD_LOCALE")

    patch config_url, params: { locale: "ja" }, as: :json
    assert_response :success

    # Verify it's saved to the config file
    content = @test_notes_dir.join(".fed").read
    assert_includes content, "locale = ja"

    get translations_url, as: :json
    data = JSON.parse(response.body)
    assert_equal "ja", data["locale"]
  end

  test "locale persists across requests after config save" do
    ENV.delete("FRANKMD_LOCALE")

    patch config_url, params: { locale: "pt-BR" }, as: :json
    assert_response :success

    # Verify it's saved to the config file
    content = @test_notes_dir.join(".fed").read
    assert_includes content, "locale = pt-BR"

    # Make multiple requests to verify persistence
    get translations_url, as: :json
    data = JSON.parse(response.body)
    assert_equal "pt-BR", data["locale"]

    get translations_url, as: :json
    data = JSON.parse(response.body)
    assert_equal "pt-BR", data["locale"]
  end

  # === All Locales Have Required Keys ===

  test "all locales have complete common translations" do
    required_keys = %w[cancel apply save create delete rename close search insert edit ok]

    %w[en pt-BR pt-PT es he ja ko].each do |locale|
      ENV["FRANKMD_LOCALE"] = locale
      get translations_url, as: :json
      data = JSON.parse(response.body)

      required_keys.each do |key|
        assert data["translations"]["common"].key?(key),
               "Locale #{locale} is missing common.#{key}"
        assert_not_empty data["translations"]["common"][key],
                        "Locale #{locale} has empty common.#{key}"
      end
    end
  end

  test "all locales have complete status translations" do
    required_keys = %w[saved unsaved error_saving error_loading searching no_matches]

    %w[en pt-BR pt-PT es he ja ko].each do |locale|
      ENV["FRANKMD_LOCALE"] = locale
      get translations_url, as: :json
      data = JSON.parse(response.body)

      required_keys.each do |key|
        assert data["translations"]["status"].key?(key),
               "Locale #{locale} is missing status.#{key}"
        assert_not_empty data["translations"]["status"][key],
                        "Locale #{locale} has empty status.#{key}"
      end
    end
  end

  test "all locales have complete error translations" do
    required_keys = %w[note_not_found folder_not_found file_not_found]

    %w[en pt-BR pt-PT es he ja ko].each do |locale|
      ENV["FRANKMD_LOCALE"] = locale
      get translations_url, as: :json
      data = JSON.parse(response.body)

      required_keys.each do |key|
        assert data["translations"]["errors"].key?(key),
               "Locale #{locale} is missing errors.#{key}"
        assert_not_empty data["translations"]["errors"][key],
                        "Locale #{locale} has empty errors.#{key}"
      end
    end
  end

  test "all locales include recent export share and reader translations" do
    checks = [
      [ "status_strip", "mode_prefix" ],
      [ "export_menu", "copy_formatted_html" ],
      [ "share_view", "label" ],
      [ "share_view", "open_exports" ],
      [ "status", "share_link_created" ],
      [ "header", "toggle_reading" ],
      [ "preview", "decrease_text_width" ],
      [ "preview", "increase_text_width" ]
    ]

    %w[en pt-BR pt-PT es he ja ko].each do |locale|
      get translations_url(locale: locale), as: :json
      data = JSON.parse(response.body)

      checks.each do |section, key|
        value = data.dig("translations", section, key)
        assert value.present?, "Locale #{locale} is missing #{section}.#{key}"
      end
    end
  end

  test "all locales include custom ai prompt translations and ai-specific errors" do
    checks = [
      [ "dialogs", "custom_ai", "hint_document" ],
      [ "dialogs", "custom_ai", "hint_selection" ],
      [ "dialogs", "custom_ai", "processing_provider" ],
      [ "errors", "no_text_selected" ],
      [ "errors", "ai_markdown_only" ],
      [ "errors", "connection_lost" ]
    ]

    %w[en pt-BR pt-PT es he ja ko].each do |locale|
      get translations_url(locale: locale), as: :json
      data = JSON.parse(response.body)

      checks.each do |path|
        value = data.dig("translations", *path)
        assert value.present?, "Locale #{locale} is missing #{path.join('.')}"
      end
    end
  end

  test "all locales include complete template UI translations" do
    checks = [
      [ "header", "save_as_template" ],
      [ "context_menu", "save_as_template" ],
      [ "context_menu", "delete_template" ],
      [ "dialogs", "note_type", "template" ],
      [ "dialogs", "note_type", "template_description" ],
      [ "dialogs", "templates", "title" ],
      [ "dialogs", "templates", "subtitle" ],
      [ "dialogs", "templates", "manage_action" ],
      [ "dialogs", "templates", "manage_title" ],
      [ "dialogs", "templates", "manage_subtitle" ],
      [ "dialogs", "templates", "loading" ],
      [ "dialogs", "templates", "empty" ],
      [ "dialogs", "templates", "new_button" ],
      [ "dialogs", "templates", "refresh_button" ],
      [ "dialogs", "templates", "new_title" ],
      [ "dialogs", "templates", "edit_title" ],
      [ "dialogs", "templates", "save_from_note_title" ],
      [ "dialogs", "templates", "save_from_note_update_title" ],
      [ "dialogs", "templates", "path_label" ],
      [ "dialogs", "templates", "path_placeholder" ],
      [ "dialogs", "templates", "content_label" ],
      [ "dialogs", "templates", "content_placeholder" ],
      [ "dialogs", "templates", "delete_confirm" ],
      [ "dialogs", "templates", "delete_linked_confirm" ],
      [ "dialogs", "templates", "built_ins", "daily_note", "name" ],
      [ "dialogs", "templates", "built_ins", "daily_note", "description" ],
      [ "dialogs", "templates", "built_ins", "meeting_note", "name" ],
      [ "dialogs", "templates", "built_ins", "meeting_note", "description" ],
      [ "dialogs", "templates", "built_ins", "article_draft", "name" ],
      [ "dialogs", "templates", "built_ins", "article_draft", "description" ],
      [ "dialogs", "templates", "built_ins", "journal_entry", "name" ],
      [ "dialogs", "templates", "built_ins", "journal_entry", "description" ],
      [ "dialogs", "templates", "built_ins", "changelog", "name" ],
      [ "dialogs", "templates", "built_ins", "changelog", "description" ],
      [ "errors", "failed_to_load_templates" ],
      [ "errors", "templates_markdown_only" ],
      [ "success", "template_saved" ],
      [ "success", "template_deleted" ]
    ]

    %w[en pt-BR pt-PT es he ja ko].each do |locale|
      get translations_url(locale: locale), as: :json
      data = JSON.parse(response.body)

      checks.each do |path|
        value = data.dig("translations", *path)
        assert value.present?, "Locale #{locale} is missing #{path.join('.')}"
      end
    end
  end

  test "all locales include editor extra shortcut help translations" do
    checks = [
      [ "dialogs", "help", "tab_editor_extras" ],
      [ "dialogs", "help", "editor_extras", "editing" ],
      [ "dialogs", "help", "editor_extras", "selection" ],
      [ "dialogs", "help", "editor_extras", "duplicate_line_down" ],
      [ "dialogs", "help", "editor_extras", "duplicate_line_up" ],
      [ "dialogs", "help", "editor_extras", "move_line_down" ],
      [ "dialogs", "help", "editor_extras", "move_line_up" ],
      [ "dialogs", "help", "editor_extras", "delete_line" ],
      [ "dialogs", "help", "editor_extras", "insert_blank_line" ],
      [ "dialogs", "help", "editor_extras", "toggle_line_comment" ],
      [ "dialogs", "help", "editor_extras", "toggle_block_comment" ],
      [ "dialogs", "help", "editor_extras", "select_next_occurrence" ],
      [ "dialogs", "help", "editor_extras", "select_all_occurrences" ]
    ]

    %w[en pt-BR pt-PT es he ja ko].each do |locale|
      get translations_url(locale: locale), as: :json
      data = JSON.parse(response.body)

      checks.each do |path|
        value = data.dig("translations", *path)
        assert value.present?, "Locale #{locale} is missing #{path.join('.')}"
      end
    end
  end

  test "all locales include complete confirmation dialog translations" do
    checks = [
      [ "confirm", "delete_note" ],
      [ "confirm", "delete_folder" ],
      [ "dialogs", "templates", "delete_confirm" ],
      [ "dialogs", "templates", "delete_linked_confirm" ],
      [ "dialogs", "code", "unrecognized_language" ]
    ]

    %w[en pt-BR pt-PT es he ja ko].each do |locale|
      get translations_url(locale: locale), as: :json
      data = JSON.parse(response.body)

      checks.each do |path|
        value = data.dig("translations", *path)
        assert value.present?, "Locale #{locale} is missing #{path.join('.')}"
      end
    end
  end

  test "all locales include backup menu and status translations" do
    checks = [
      [ "context_menu", "backup_note" ],
      [ "context_menu", "backup_folder" ],
      [ "status", "backup_preparing" ],
      [ "status", "backup_started" ],
      [ "status", "backup_failed" ]
    ]

    %w[en pt-BR pt-PT es he ja ko].each do |locale|
      get translations_url(locale: locale), as: :json
      data = JSON.parse(response.body)

      checks.each do |path|
        value = data.dig("translations", *path)
        assert value.present?, "Locale #{locale} is missing #{path.join('.')}"
      end
    end
  end

  # === Invalid Locale Handling ===

  test "invalid locale falls back to default" do
    ENV["FRANKMD_LOCALE"] = "invalid_locale"

    get translations_url, as: :json
    data = JSON.parse(response.body)

    # Should fall back to English
    assert_equal "en", data["locale"]
  end

  # === Priority: .fed file > ENV > default ===

  test "config file takes precedence over ENV variable" do
    # Set locale in config file
    @test_notes_dir.join(".fed").write("locale = ja\n")

    # Set ENV to a different locale
    ENV["FRANKMD_LOCALE"] = "es"

    get translations_url, as: :json
    data = JSON.parse(response.body)

    # Should use config file value (ja), not ENV value (es)
    # User's explicit choice in .fed overrides deployment default in ENV
    assert_equal "ja", data["locale"]
  end

  test "ENV variable is used as fallback when config file has no locale" do
    # No locale in .fed file
    @test_notes_dir.join(".fed").write("theme = gruvbox\n")

    ENV["FRANKMD_LOCALE"] = "es"

    get translations_url, as: :json
    data = JSON.parse(response.body)

    # Should use ENV value since .fed has no locale
    assert_equal "es", data["locale"]
  end

  test "empty ENV FRANKMD_LOCALE does not override config file locale" do
    # This was the production bug: docker-compose sets FRANKMD_LOCALE=""
    # Empty string is truthy in Ruby || chains but not a valid locale
    @test_notes_dir.join(".fed").write("locale = pt-BR\n")

    ENV["FRANKMD_LOCALE"] = ""

    get translations_url, as: :json
    data = JSON.parse(response.body)

    # Should use config file value, not get stuck on empty ENV string
    assert_equal "pt-BR", data["locale"]
  end

  # === Locale Picker Updates Config ===

  test "updating locale via config endpoint updates config file" do
    ENV.delete("FRANKMD_LOCALE")

    # First set to English
    patch config_url, params: { locale: "en" }, as: :json
    assert_response :success

    # Then change to Japanese
    patch config_url, params: { locale: "ja" }, as: :json
    assert_response :success

    content = @test_notes_dir.join(".fed").read
    assert_includes content, "locale = ja"
    refute_includes content, "locale = en"
  end

  # === Translations Include All Required Sections ===

  test "translations include all sections needed by JavaScript" do
    expected_sections = %w[common dialogs status status_strip errors success editor sidebar preview context_menu connection export_menu header share_view confirm]

    get translations_url, as: :json
    data = JSON.parse(response.body)

    expected_sections.each do |section|
      assert data["translations"].key?(section),
             "Missing translation section: #{section}"
    end
  end
end
