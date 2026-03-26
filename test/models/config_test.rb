# frozen_string_literal: true

require "test_helper"

class ConfigTest < ActiveSupport::TestCase
  def setup
    @test_dir = Rails.root.join("tmp", "test_config_#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@test_dir)
    @original_notes_path = ENV["NOTES_PATH"]
    ENV["NOTES_PATH"] = @test_dir.to_s

    # Save and clear all AI-related env vars
    @original_ai_env = {}
    ai_env_keys.each do |key|
      @original_ai_env[key] = ENV[key]
      ENV.delete(key)
    end

    # Save and clear feature-related env vars (S3, YouTube, Google)
    @original_feature_env = {}
    feature_env_keys.each do |key|
      @original_feature_env[key] = ENV[key]
      ENV.delete(key)
    end
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir&.exist?
    ENV["NOTES_PATH"] = @original_notes_path

    # Restore AI env vars
    ai_env_keys.each do |key|
      if @original_ai_env[key]
        ENV[key] = @original_ai_env[key]
      else
        ENV.delete(key)
      end
    end

    # Restore feature env vars
    feature_env_keys.each do |key|
      if @original_feature_env[key]
        ENV[key] = @original_feature_env[key]
      else
        ENV.delete(key)
      end
    end
  end

  def ai_env_keys
    %w[
      OPENAI_API_KEY OPENROUTER_API_KEY ANTHROPIC_API_KEY
      GEMINI_API_KEY OLLAMA_API_BASE AI_PROVIDER AI_MODEL
      OPENAI_MODEL OPENROUTER_MODEL ANTHROPIC_MODEL GEMINI_MODEL OLLAMA_MODEL
    ]
  end

  def feature_env_keys
    %w[
      AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_S3_BUCKET
      YOUTUBE_API_KEY GOOGLE_API_KEY GOOGLE_CSE_ID
    ]
  end

  # === Initialization ===

  test "creates config file on initialization if it does not exist" do
    config = Config.new(base_path: @test_dir)

    assert @test_dir.join(".fed").exist?
  end

  test "creates config file and parent directory when neither exist" do
    # Use a nested path that doesn't exist
    nested_dir = @test_dir.join("nested", "deeply", "path")
    FileUtils.rm_rf(nested_dir) # Make sure it doesn't exist

    config = Config.new(base_path: nested_dir)

    assert nested_dir.exist?, "Parent directory should be created"
    assert nested_dir.join(".fed").exist?, ".fed file should be created"
  end

  test "config file template contains all sections" do
    config = Config.new(base_path: @test_dir)
    content = @test_dir.join(".fed").read

    assert_includes content, "# UI Settings"
    assert_includes content, "# theme ="
    assert_includes content, "# editor_font ="
    assert_includes content, "# preview_font_family = sans"
    assert_includes content, "# preview_width = 40"
    assert_includes content, "# active_mode = raw"
    assert_includes content, "# App-managed local images default to .frankmd/images inside notes path."
    assert_includes content, "# Templates"
    assert_includes content, "# templates_path = /path/to/templates"
    assert_includes content, "# Remote Share API"
    assert_includes content, "# share_backend = local"
    assert_includes content, "# share_remote_api_host = shares.example.com"
    assert_includes content, "# share_remote_expiration_days = 30"
    assert_includes content, "# share_remote_api_token = your-remote-api-token"
    assert_includes content, "# AWS S3"
    assert_includes content, "# YouTube API"
    assert_includes content, "# Google Custom Search"
    assert_includes content, "# AI/LLM"
    assert_includes content, "# ai_grammar_provider = openai"
    assert_includes content, "# ai_custom_prompt_model = claude-sonnet-4-20250514"
    assert_includes content, "# ollama_api_base"
    assert_includes content, "# anthropic_api_key"
    assert_includes content, "# gemini_api_key"
  end

  # === Default Values ===

  test "returns default values when nothing is configured" do
    config = Config.new(base_path: @test_dir)

    assert_equal "cascadia-code", config.get(:editor_font)
    assert_equal 14, config.get(:editor_font_size)
    assert_equal 100, config.get(:preview_zoom)
    assert_equal 40, config.get(:preview_width)
    assert_equal "sans", config.get(:preview_font_family)
    assert_equal true, config.get(:sidebar_visible)
    assert_nil config.get(:active_mode)
    assert_equal false, config.get(:typewriter_mode)
    assert_nil config.get(:templates_path)
    assert_equal "local", config.get(:share_backend)
    assert_equal "https", config.get(:share_remote_api_scheme)
    assert_equal 443, config.get(:share_remote_api_port)
    assert_equal 10, config.get(:share_remote_timeout_seconds)
    assert_equal true, config.get(:share_remote_verify_tls)
    assert_equal true, config.get(:share_remote_upload_assets)
    assert_equal 30, config.get(:share_remote_expiration_days)
    assert_nil config.get(:theme)
  end

  # === Reading from File ===

  test "reads values from config file" do
    @test_dir.join(".fed").write(<<~CONFIG)
      theme = gruvbox
      editor_font = fira-code
      editor_font_size = 16
      preview_width = 52
      preview_font_family = serif
      active_mode = preview
      templates_path = /tmp/templates
      share_backend = remote
      share_remote_api_host = shares.example.com
      share_remote_api_port = 8443
      share_remote_timeout_seconds = 30
      share_remote_verify_tls = false
      share_remote_upload_assets = false
      share_remote_expiration_days = 14
    CONFIG

    config = Config.new(base_path: @test_dir)

    assert_equal "gruvbox", config.get(:theme)
    assert_equal "fira-code", config.get(:editor_font)
    assert_equal 16, config.get(:editor_font_size)
    assert_equal 52, config.get(:preview_width)
    assert_equal "serif", config.get(:preview_font_family)
    assert_equal "preview", config.get(:active_mode)
    assert_equal "/tmp/templates", config.get(:templates_path)
    assert_equal "remote", config.get(:share_backend)
    assert_equal "shares.example.com", config.get(:share_remote_api_host)
    assert_equal 8443, config.get(:share_remote_api_port)
    assert_equal 30, config.get(:share_remote_timeout_seconds)
    assert_equal false, config.get(:share_remote_verify_tls)
    assert_equal false, config.get(:share_remote_upload_assets)
    assert_equal 14, config.get(:share_remote_expiration_days)
  end

  test "reads boolean values correctly" do
    @test_dir.join(".fed").write(<<~CONFIG)
      typewriter_mode = true
      sidebar_visible = false
    CONFIG

    config = Config.new(base_path: @test_dir)

    assert_equal true, config.get(:typewriter_mode)
    assert_equal false, config.get(:sidebar_visible)
  end

  test "handles quoted string values" do
    @test_dir.join(".fed").write(<<~CONFIG)
      theme = "tokyo-night"
      editor_font = 'jetbrains-mono'
    CONFIG

    config = Config.new(base_path: @test_dir)

    assert_equal "tokyo-night", config.get(:theme)
    assert_equal "jetbrains-mono", config.get(:editor_font)
  end

  test "ignores comments" do
    @test_dir.join(".fed").write(<<~CONFIG)
      # This is a comment
      theme = dark
      # editor_font = should-be-ignored
    CONFIG

    config = Config.new(base_path: @test_dir)

    assert_equal "dark", config.get(:theme)
    assert_equal "cascadia-code", config.get(:editor_font) # default
  end

  test "ignores unknown keys" do
    @test_dir.join(".fed").write(<<~CONFIG)
      unknown_key = some_value
      theme = light
    CONFIG

    config = Config.new(base_path: @test_dir)

    assert_nil config.get(:unknown_key)
    assert_equal "light", config.get(:theme)
  end

  # === ENV Fallback ===

  test "falls back to ENV for keys with ENV mapping" do
    ENV["YOUTUBE_API_KEY"] = "test-youtube-key"

    config = Config.new(base_path: @test_dir)

    assert_equal "test-youtube-key", config.get(:youtube_api_key)
  ensure
    ENV.delete("YOUTUBE_API_KEY")
  end

  test "file value overrides ENV value" do
    ENV["YOUTUBE_API_KEY"] = "env-key"
    @test_dir.join(".fed").write(<<~CONFIG)
      youtube_api_key = file-key
    CONFIG

    config = Config.new(base_path: @test_dir)

    assert_equal "file-key", config.get(:youtube_api_key)
  ensure
    ENV.delete("YOUTUBE_API_KEY")
  end

  # === Writing Values ===

  test "set saves a single value" do
    config = Config.new(base_path: @test_dir)

    config.set(:theme, "gruvbox")

    # Re-read config to verify persistence
    config2 = Config.new(base_path: @test_dir)
    assert_equal "gruvbox", config2.get(:theme)
  end

  test "update saves multiple values" do
    config = Config.new(base_path: @test_dir)

    config.update(
      theme: "dark",
      editor_font_size: 18,
      preview_font_family: "mono",
      preview_width: 58,
      active_mode: "reading",
      share_remote_expiration_days: 21
    )

    config2 = Config.new(base_path: @test_dir)
    assert_equal "dark", config2.get(:theme)
    assert_equal 18, config2.get(:editor_font_size)
    assert_equal "mono", config2.get(:preview_font_family)
    assert_equal 58, config2.get(:preview_width)
    assert_equal "reading", config2.get(:active_mode)
    assert_equal 21, config2.get(:share_remote_expiration_days)
  end

  test "update replaces commented line with actual value" do
    config = Config.new(base_path: @test_dir)
    original_content = @test_dir.join(".fed").read
    assert_includes original_content, "# theme ="

    config.set(:theme, "nord")

    new_content = @test_dir.join(".fed").read
    assert_includes new_content, "theme = nord"
    refute_includes new_content, "# theme = nord"
  end

  test "update does not duplicate keys" do
    config = Config.new(base_path: @test_dir)
    config.set(:theme, "dark")
    config.set(:theme, "light")
    config.set(:theme, "gruvbox")

    content = @test_dir.join(".fed").read
    matches = content.scan(/^theme = /)
    assert_equal 1, matches.length
  end

  test "preserves user-customized file structure when updating" do
    # User has stripped all comments and reordered settings
    # Include placeholders to prevent upgrade from adding new sections
    @test_dir.join(".fed").write(<<~CONFIG)
      editor_font = hack
      theme = dark
      editor_font_size = 16
      # templates_path = placeholder
      # share_backend = placeholder
      # ai_model = placeholder
    CONFIG

    config = Config.new(base_path: @test_dir)
    config.set(:theme, "gruvbox")

    content = @test_dir.join(".fed").read
    lines = content.lines.map(&:strip).reject(&:empty?)

    # Should preserve user's ordering (placeholders are preserved as comments)
    assert_equal 6, lines.length
    assert_equal "editor_font = hack", lines[0]
    assert_equal "theme = gruvbox", lines[1]
    assert_equal "editor_font_size = 16", lines[2]
    assert_equal "# templates_path = placeholder", lines[3]
    assert_equal "# share_backend = placeholder", lines[4]
    assert_equal "# ai_model = placeholder", lines[5]
  end

  test "does not re-add values user manually removed" do
    # Start with full config (include placeholders to prevent upgrade)
    @test_dir.join(".fed").write(<<~CONFIG)
      theme = dark
      editor_font = hack
      editor_font_size = 18
      # templates_path = placeholder
      # share_backend = placeholder
      # ai_model = placeholder
    CONFIG

    # Load config (all values are in @values)
    config = Config.new(base_path: @test_dir)
    assert_equal "dark", config.get(:theme)
    assert_equal "hack", config.get(:editor_font)
    assert_equal 18, config.get(:editor_font_size)

    # User manually removes editor_font from file
    @test_dir.join(".fed").write(<<~CONFIG)
      theme = dark
      editor_font_size = 18
      # templates_path = placeholder
      # share_backend = placeholder
      # ai_model = placeholder
    CONFIG

    # Create new config and change theme
    config2 = Config.new(base_path: @test_dir)
    config2.set(:theme, "nord")

    # editor_font should NOT be re-added (but editor_font_size should remain)
    content = @test_dir.join(".fed").read
    refute_includes content, "editor_font = hack"
    refute_includes content, "editor_font = cascadia"
    assert_includes content, "theme = nord"
    assert_includes content, "editor_font_size = 18"
  end

  test "only modifies the specific key being changed" do
    original_content = <<~CONFIG
      # My custom comment
      theme = dark

      # Another section
      editor_font = fira-code
      editor_font_size = 20
    CONFIG
    @test_dir.join(".fed").write(original_content)

    config = Config.new(base_path: @test_dir)
    config.set(:editor_font_size, 22)

    content = @test_dir.join(".fed").read

    # Comments and structure preserved
    assert_includes content, "# My custom comment"
    assert_includes content, "# Another section"
    # Other values unchanged
    assert_includes content, "theme = dark"
    assert_includes content, "editor_font = fira-code"
    # Only the target key changed
    assert_includes content, "editor_font_size = 22"
    refute_includes content, "editor_font_size = 20"
  end

  test "appends new key at end if not present in file" do
    # Include placeholders to prevent upgrade from adding new sections
    @test_dir.join(".fed").write(<<~CONFIG)
      theme = dark
      # templates_path = placeholder
      # share_backend = placeholder
      # ai_model = placeholder
    CONFIG

    config = Config.new(base_path: @test_dir)
    config.set(:editor_font, "hack")

    content = @test_dir.join(".fed").read
    lines = content.lines.map(&:strip).reject(&:empty?)

    assert_equal "theme = dark", lines[0]
    assert_equal "# templates_path = placeholder", lines[1]
    assert_equal "# share_backend = placeholder", lines[2]
    assert_equal "# ai_model = placeholder", lines[3]
    assert_equal "editor_font = hack", lines[4]
  end

  # === UI Settings ===

  test "ui_settings returns only UI keys" do
    @test_dir.join(".fed").write(<<~CONFIG)
      theme = dark
      editor_font = hack
      preview_width = 55
      preview_font_family = serif
      active_mode = preview
      youtube_api_key = secret
    CONFIG

    config = Config.new(base_path: @test_dir)
    settings = config.ui_settings

    assert_equal "dark", settings["theme"]
    assert_equal "hack", settings["editor_font"]
    assert_equal 55, settings["preview_width"]
    assert_equal "serif", settings["preview_font_family"]
    assert_equal "preview", settings["active_mode"]
    refute settings.key?("youtube_api_key")
    refute settings.key?("templates_path")
  end

  test "all_settings masks remote share secrets unless explicitly requested" do
    @test_dir.join(".fed").write(<<~CONFIG)
      share_remote_api_token = token-123
      share_remote_signing_secret = signing-secret
      share_remote_alert_webhook_secret = alert-secret
    CONFIG

    config = Config.new(base_path: @test_dir)
    masked_settings = config.all_settings
    sensitive_settings = config.all_settings(include_sensitive: true)

    assert_equal true, masked_settings["share_remote_api_token_configured"]
    assert_equal true, masked_settings["share_remote_signing_secret_configured"]
    assert_equal true, masked_settings["share_remote_alert_webhook_secret_configured"]
    refute masked_settings.key?("share_remote_api_token")
    refute masked_settings.key?("share_remote_signing_secret")
    refute masked_settings.key?("share_remote_alert_webhook_secret")

    assert_equal "token-123", sensitive_settings["share_remote_api_token"]
    assert_equal "signing-secret", sensitive_settings["share_remote_signing_secret"]
    assert_equal "alert-secret", sensitive_settings["share_remote_alert_webhook_secret"]
  end

  # === Feature Detection ===

  test "feature_available? detects S3 configuration" do
    config = Config.new(base_path: @test_dir)
    refute config.feature_available?(:s3_upload)

    @test_dir.join(".fed").write(<<~CONFIG)
      aws_access_key_id = key
      aws_secret_access_key = secret
      aws_s3_bucket = bucket
    CONFIG

    config2 = Config.new(base_path: @test_dir)
    assert config2.feature_available?(:s3_upload)
  end

  test "feature_available? detects YouTube configuration" do
    config = Config.new(base_path: @test_dir)
    refute config.feature_available?(:youtube_search)

    @test_dir.join(".fed").write(<<~CONFIG)
      youtube_api_key = test-key
    CONFIG

    config2 = Config.new(base_path: @test_dir)
    assert config2.feature_available?(:youtube_search)
  end

  test "feature_available? detects Google search configuration" do
    config = Config.new(base_path: @test_dir)
    refute config.feature_available?(:google_search)

    @test_dir.join(".fed").write(<<~CONFIG)
      google_api_key = api-key
      google_cse_id = cse-id
    CONFIG

    config2 = Config.new(base_path: @test_dir)
    assert config2.feature_available?(:google_search)
  end

  # === Corrupted File Handling ===

  test "handles empty config file gracefully" do
    @test_dir.join(".fed").write("")

    config = Config.new(base_path: @test_dir)

    assert_equal "cascadia-code", config.get(:editor_font)
  end

  test "handles malformed lines gracefully" do
    @test_dir.join(".fed").write(<<~CONFIG)
      this is not valid
      = no key
      theme = dark
      editor_font_size not an int
    CONFIG

    config = Config.new(base_path: @test_dir)

    # Should still parse valid lines
    assert_equal "dark", config.get(:theme)
    # Invalid lines are ignored, default is used
    assert_equal 14, config.get(:editor_font_size)
  end

  test "handles binary garbage in file" do
    @test_dir.join(".fed").binwrite("\x00\xFF\xFE\x00theme = dark\n")

    # Should not crash
    config = Config.new(base_path: @test_dir)

    # May or may not parse correctly, but should not crash
    assert_nothing_raised { config.get(:theme) }
  end

  test "handles file read errors gracefully" do
    # Create directory instead of file to cause read error
    FileUtils.rm_f(@test_dir.join(".fed"))
    FileUtils.mkdir_p(@test_dir.join(".fed"))

    # Should not crash, should use defaults
    config = Config.new(base_path: @test_dir)
    assert_equal "cascadia-code", config.get(:editor_font)
  ensure
    FileUtils.rm_rf(@test_dir.join(".fed"))
  end

  # === Type Casting ===

  test "casts integer values" do
    @test_dir.join(".fed").write("editor_font_size = 20")

    config = Config.new(base_path: @test_dir)

    assert_equal 20, config.get(:editor_font_size)
    assert_kind_of Integer, config.get(:editor_font_size)
  end

  test "casts boolean true values" do
    [ "true", "1", "yes", "on", "TRUE", "Yes" ].each do |value|
      @test_dir.join(".fed").write("typewriter_mode = #{value}")
      config = Config.new(base_path: @test_dir)
      assert_equal true, config.get(:typewriter_mode), "Expected '#{value}' to be true"
    end
  end

  test "casts boolean false values" do
    [ "false", "0", "no", "off", "FALSE", "anything" ].each do |value|
      @test_dir.join(".fed").write("typewriter_mode = #{value}")
      config = Config.new(base_path: @test_dir)
      assert_equal false, config.get(:typewriter_mode), "Expected '#{value}' to be false"
    end
  end

  # === AI Provider Tests ===

  test "ai_providers_available returns empty when nothing configured" do
    config = Config.new(base_path: @test_dir)
    assert_empty config.ai_providers_available
  end

  test "ai_providers_available returns configured providers" do
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

    config = Config.new(base_path: @test_dir)
    providers = config.ai_providers_available

    assert_includes providers, "openai"
    assert_includes providers, "anthropic"
    assert_not_includes providers, "ollama"
    assert_not_includes providers, "gemini"
  end

  test "effective_ai_provider follows priority order" do
    ENV["OLLAMA_API_BASE"] = "http://localhost:11434"
    ENV["OPENROUTER_API_KEY"] = "sk-or-test"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"
    ENV["OPENAI_API_KEY"] = "sk-test"

    config = Config.new(base_path: @test_dir)

    # OpenAI has highest priority
    assert_equal "openai", config.effective_ai_provider
  end

  test "effective_ai_provider respects explicit provider setting" do
    ENV["OLLAMA_API_BASE"] = "http://localhost:11434"
    ENV["OPENAI_API_KEY"] = "sk-test"

    @test_dir.join(".fed").write("ai_provider = openai")
    config = Config.new(base_path: @test_dir)

    assert_equal "openai", config.effective_ai_provider
  end

  test "effective_ai_provider ignores unavailable provider" do
    ENV["OLLAMA_API_BASE"] = "http://localhost:11434"

    @test_dir.join(".fed").write("ai_provider = openai") # OpenAI not configured
    config = Config.new(base_path: @test_dir)

    assert_equal "ollama", config.effective_ai_provider
  end

  test "effective_ai_model returns provider-specific default" do
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

    config = Config.new(base_path: @test_dir)
    assert_equal "claude-sonnet-4-20250514", config.effective_ai_model
  end

  test "effective_ai_model respects global ai_model override" do
    ENV["OPENAI_API_KEY"] = "sk-test"

    @test_dir.join(".fed").write("ai_model = gpt-4-turbo")
    config = Config.new(base_path: @test_dir)

    assert_equal "gpt-4-turbo", config.effective_ai_model
  end

  test "effective_ai_model respects provider-specific model" do
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

    @test_dir.join(".fed").write("anthropic_model = claude-3-opus-20240229")
    config = Config.new(base_path: @test_dir)

    assert_equal "claude-3-opus-20240229", config.effective_ai_model
  end

  test "ai_provider_options returns normalized provider and model pairs in priority order" do
    ENV["OPENROUTER_API_KEY"] = "sk-or-test"
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

    config = Config.new(base_path: @test_dir)
    options = config.ai_provider_options

    assert_equal %w[openai anthropic openrouter], options.map { |option| option["provider"] }
    assert_equal(
      [
        "OpenAI · gpt-4o-mini",
        "Anthropic · claude-sonnet-4-20250514",
        "OpenRouter · openai/gpt-4o-mini"
      ],
      options.map { |option| option["label"] }
    )
    assert_equal [ "provider_specific" ], options.map { |option| option["model_source"] }.uniq
    assert_equal [ false ], options.map { |option| option["selected"] }.uniq
  end

  test "effective_ai_option keeps global ai_model override separate from provider options" do
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

    @test_dir.join(".fed").write("ai_model = gpt-4-turbo")
    config = Config.new(base_path: @test_dir)

    assert_equal "gpt-4-turbo", config.effective_ai_option["model"]
    assert_equal "global_override", config.effective_ai_option["model_source"]
    assert_equal true, config.effective_ai_option["selected"]
    assert_equal "OpenAI · gpt-4-turbo", config.effective_ai_option["label"]

    options = config.ai_provider_options
    assert_equal "gpt-4o-mini", options.find { |option| option["provider"] == "openai" }["model"]
    assert_equal "claude-sonnet-4-20250514", options.find { |option| option["provider"] == "anthropic" }["model"]
  end

  test "save_ai_feature_selection persists a valid feature-specific provider choice" do
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

    config = Config.new(base_path: @test_dir)
    selection = config.save_ai_feature_selection("grammar", provider: "anthropic", model: "claude-sonnet-4-20250514")

    assert_equal "anthropic", selection["provider"]
    assert_equal "grammar", selection["feature"]
    assert_equal "saved_preference", selection["model_source"]
    assert_equal true, selection["saved"]

    reloaded = Config.new(base_path: @test_dir)
    assert_equal "anthropic", reloaded.get("ai_grammar_provider")
    assert_equal "claude-sonnet-4-20250514", reloaded.get("ai_grammar_model")
    assert_equal "anthropic", reloaded.ai_feature_selection("grammar")["provider"]
  end

  test "ai_feature_selection returns nil when a saved choice is no longer available" do
    @test_dir.join(".fed").write(<<~CONFIG)
      ai_grammar_provider = openai
      ai_grammar_model = gpt-4o-mini
    CONFIG

    config = Config.new(base_path: @test_dir)

    assert_nil config.ai_feature_selection("grammar")
    assert_nil config.ai_saved_selections["grammar"]
  end

  test "ai_feature_selection_state marks stale saved choices as invalid" do
    @test_dir.join(".fed").write(<<~CONFIG)
      ai_grammar_provider = openai
      ai_grammar_model = gpt-4o-mini
    CONFIG

    config = Config.new(base_path: @test_dir)
    state = config.ai_feature_selection_state("grammar")

    assert_equal "grammar", state["feature"]
    assert_equal true, state["configured"]
    assert_equal false, state["valid"]
    assert_equal true, state["invalid"]
    assert_equal "openai", state["provider"]
    assert_equal "gpt-4o-mini", state["model"]
    assert_equal true, config.ai_saved_selection_states["grammar"]["invalid"]
  end

  test "save_ai_feature_selection rejects unsupported features and invalid option pairs" do
    ENV["OPENAI_API_KEY"] = "sk-test"

    config = Config.new(base_path: @test_dir)

    assert_nil config.save_ai_feature_selection("summaries", provider: "openai", model: "gpt-4o-mini")
    assert_nil config.save_ai_feature_selection("grammar", provider: "openai", model: "gpt-4-turbo")
  end

  test "feature_available? returns true for ai when any provider configured" do
    ENV["GEMINI_API_KEY"] = "gemini-test"

    config = Config.new(base_path: @test_dir)
    assert config.feature_available?("ai")
  end

  test "feature_available? returns false for ai when no provider configured" do
    config = Config.new(base_path: @test_dir)
    assert_not config.feature_available?("ai")
  end

  test "ai_configured_in_file? returns true when AI credential in file" do
    @test_dir.join(".fed").write("anthropic_api_key = sk-ant-test")
    config = Config.new(base_path: @test_dir)

    assert config.ai_configured_in_file?
  end

  test "ai_configured_in_file? returns false when only ai_provider in file" do
    @test_dir.join(".fed").write("ai_provider = anthropic")
    config = Config.new(base_path: @test_dir)

    assert_not config.ai_configured_in_file?
  end

  test "get_ai ignores ENV when AI credential set in file" do
    # Set ENV vars that would normally be used
    ENV["OPENAI_API_KEY"] = "sk-env-openai"
    ENV["OPENROUTER_API_KEY"] = "sk-env-openrouter"

    # Set only anthropic in file - this should trigger file-only mode
    @test_dir.join(".fed").write("anthropic_api_key = sk-file-anthropic")
    config = Config.new(base_path: @test_dir)

    # File key should be returned
    assert_equal "sk-file-anthropic", config.get_ai("anthropic_api_key")
    # ENV keys should be ignored (returns nil, not ENV value)
    assert_nil config.get_ai("openai_api_key")
    assert_nil config.get_ai("openrouter_api_key")
  end

  test "get_ai uses ENV when no AI credential in file" do
    ENV["OPENAI_API_KEY"] = "sk-env-openai"

    # No AI credentials in file, just settings
    @test_dir.join(".fed").write("theme = dark")
    config = Config.new(base_path: @test_dir)

    # Should use ENV since no AI credentials in file
    assert_equal "sk-env-openai", config.get_ai("openai_api_key")
  end

  test "effective_ai_provider uses file credentials over ENV" do
    # Set multiple ENV providers
    ENV["OPENAI_API_KEY"] = "sk-env-openai"
    ENV["OPENROUTER_API_KEY"] = "sk-env-openrouter"

    # Set only anthropic in file
    @test_dir.join(".fed").write("anthropic_api_key = sk-file-anthropic")
    config = Config.new(base_path: @test_dir)

    # Should select anthropic (from file) not openai (from ENV)
    assert_equal "anthropic", config.effective_ai_provider
    assert_equal [ "anthropic" ], config.ai_providers_available
  end

  # === Config File Upgrade Tests ===

  test "upgrade adds missing templates, remote share, and AI sections to existing config" do
    # Create old-style config without Templates, Remote Share API, or AI sections
    old_config = <<~CONFIG
      # FrankMD Configuration
      theme = gruvbox
      editor_font_size = 16

      # Local Images
      # images_path = /path/to/images
    CONFIG

    @test_dir.join(".fed").write(old_config)

    # Loading config should trigger upgrade
    config = Config.new(base_path: @test_dir)

    # Verify existing values preserved
    assert_equal "gruvbox", config.get("theme")
    assert_equal 16, config.get("editor_font_size")

    # Verify new sections were added
    content = @test_dir.join(".fed").read
    assert_includes content, "# Templates"
    assert_includes content, "templates_path"
    assert_includes content, "# Remote Share API"
    assert_includes content, "share_backend"
    assert_includes content, "share_remote_api_host"
    assert_includes content, "share_remote_expiration_days"
    assert_includes content, "# AI/LLM"
    assert_includes content, "ollama_api_base"
    assert_includes content, "anthropic_api_key"
    assert_includes content, "gemini_api_key"
  end

  test "upgrade preserves existing values and comments" do
    old_config = <<~CONFIG
      # My custom header comment
      theme = tokyo-night

      # My custom comment about images
      images_path = /my/images
    CONFIG

    @test_dir.join(".fed").write(old_config)
    Config.new(base_path: @test_dir)

    content = @test_dir.join(".fed").read

    # Custom content preserved
    assert_includes content, "# My custom header comment"
    assert_includes content, "theme = tokyo-night"
    assert_includes content, "# My custom comment about images"
    assert_includes content, "images_path = /my/images"
  end

  test "upgrade adds remote share expiration line to an existing remote share section" do
    config_with_remote_share_section = <<~CONFIG
      # FrankMD Configuration
      theme = dark

      # Remote Share API
      share_backend = remote
      share_remote_api_host = shares.example.com
      share_remote_instance_name = home-vps
      share_remote_api_token = token-123
    CONFIG

    @test_dir.join(".fed").write(config_with_remote_share_section)

    config = Config.new(base_path: @test_dir)
    content = @test_dir.join(".fed").read

    assert_equal "remote", config.get(:share_backend)
    assert_equal "shares.example.com", config.get(:share_remote_api_host)
    assert_equal "home-vps", config.get(:share_remote_instance_name)
    assert_equal 30, config.get(:share_remote_expiration_days)
    assert_includes content, "# share_remote_expiration_days = 30"
    assert_equal 1, content.scan(/share_remote_expiration_days/).length
  end

  test "upgrade does not duplicate existing AI section" do
    # Create config with AI section already present
    config_with_ai = <<~CONFIG
      # FrankMD Configuration
      theme = dark

      # AI/LLM (for grammar checking)
      openai_api_key = sk-existing
    CONFIG

    @test_dir.join(".fed").write(config_with_ai)

    # Loading should not add another AI section
    config = Config.new(base_path: @test_dir)

    content = @test_dir.join(".fed").read

    # Should only have one AI section marker
    ai_section_count = content.scan(/# AI\/LLM/).count
    assert_equal 1, ai_section_count

    # Existing value preserved
    assert_equal "sk-existing", config.get("openai_api_key")
  end

  test "upgrade adds ai feature selection lines to an existing ai section" do
    config_with_ai_section = <<~CONFIG
      # FrankMD Configuration
      theme = dark

      # AI/LLM (for grammar checking)
      ai_provider = auto
      ai_model = gpt-4o-mini
      openai_api_key = sk-existing
    CONFIG

    @test_dir.join(".fed").write(config_with_ai_section)

    Config.new(base_path: @test_dir)
    content = @test_dir.join(".fed").read

    assert_includes content, "# ai_grammar_provider = openai"
    assert_includes content, "# ai_grammar_model = gpt-4o-mini"
    assert_includes content, "# ai_custom_prompt_provider = anthropic"
    assert_includes content, "# ai_custom_prompt_model = claude-sonnet-4-20250514"
    assert_equal 1, content.scan(/ai_grammar_provider/).length
  end
end
