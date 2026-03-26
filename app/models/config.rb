# frozen_string_literal: true

# Manages user configuration stored in .fed file at the notes root.
# Provides defaults from ENV variables that can be overridden per-folder.
class Config
  CONFIG_FILE = ".fed"
  CONFIG_VERSION = 7  # Increment when adding new settings

  # All configurable options with their defaults and types
  SCHEMA = {
    # UI Settings
    "theme" => { default: nil, type: :string, env: nil },
    "locale" => { default: "en", type: :string, env: "FRANKMD_LOCALE" },
    "editor_font" => { default: "cascadia-code", type: :string, env: nil },
    "editor_font_size" => { default: 14, type: :integer, env: nil },
    "preview_zoom" => { default: 100, type: :integer, env: nil },
    "preview_width" => { default: 40, type: :integer, env: nil },
    "preview_font_family" => { default: "sans", type: :string, env: nil },
    "sidebar_visible" => { default: true, type: :boolean, env: nil },
    "active_mode" => { default: nil, type: :string, env: nil },
    "typewriter_mode" => { default: false, type: :boolean, env: nil },
    "editor_indent" => { default: 2, type: :integer, env: nil },
    "editor_line_numbers" => { default: 0, type: :integer, env: nil },
    "editor_width" => { default: 72, type: :integer, env: nil },

    # Paths (ENV defaults)
    "images_path" => { default: nil, type: :string, env: "IMAGES_PATH" },
    "templates_path" => { default: nil, type: :string, env: nil },

    # Remote share publishing
    "share_backend" => { default: "local", type: :string, env: nil },
    "share_remote_api_scheme" => { default: "https", type: :string, env: nil },
    "share_remote_api_host" => { default: nil, type: :string, env: nil },
    "share_remote_api_port" => { default: 443, type: :integer, env: nil },
    "share_remote_public_base" => { default: nil, type: :string, env: nil },
    "share_remote_timeout_seconds" => { default: 10, type: :integer, env: nil },
    "share_remote_verify_tls" => { default: true, type: :boolean, env: nil },
    "share_remote_upload_assets" => { default: true, type: :boolean, env: nil },
    "share_remote_instance_name" => { default: nil, type: :string, env: nil },
    "share_remote_expiration_days" => { default: 30, type: :integer, env: nil },
    "share_remote_healthchecks_ping_url" => { default: nil, type: :string, env: nil },
    "share_remote_alert_webhook_url" => { default: nil, type: :string, env: nil },
    "share_remote_api_token" => { default: nil, type: :string, env: nil },
    "share_remote_signing_secret" => { default: nil, type: :string, env: nil },
    "share_remote_alert_webhook_secret" => { default: nil, type: :string, env: nil },

    # AWS S3 Settings (ENV defaults)
    "aws_access_key_id" => { default: nil, type: :string, env: "AWS_ACCESS_KEY_ID" },
    "aws_secret_access_key" => { default: nil, type: :string, env: "AWS_SECRET_ACCESS_KEY" },
    "aws_s3_bucket" => { default: nil, type: :string, env: "AWS_S3_BUCKET" },
    "aws_region" => { default: nil, type: :string, env: "AWS_REGION" },

    # YouTube API (ENV default)
    "youtube_api_key" => { default: nil, type: :string, env: "YOUTUBE_API_KEY" },

    # Google Custom Search (ENV defaults)
    "google_api_key" => { default: nil, type: :string, env: "GOOGLE_API_KEY" },
    "google_cse_id" => { default: nil, type: :string, env: "GOOGLE_CSE_ID" },

    # AI/LLM Settings (ENV defaults)
    "ai_provider" => { default: "auto", type: :string, env: "AI_PROVIDER" },
    "ai_model" => { default: nil, type: :string, env: "AI_MODEL" },
    "ollama_api_base" => { default: nil, type: :string, env: "OLLAMA_API_BASE" },
    "ollama_model" => { default: "llama3.2:latest", type: :string, env: "OLLAMA_MODEL" },
    "openrouter_api_key" => { default: nil, type: :string, env: "OPENROUTER_API_KEY" },
    "openrouter_model" => { default: "openai/gpt-4o-mini", type: :string, env: "OPENROUTER_MODEL" },
    "anthropic_api_key" => { default: nil, type: :string, env: "ANTHROPIC_API_KEY" },
    "anthropic_model" => { default: "claude-sonnet-4-20250514", type: :string, env: "ANTHROPIC_MODEL" },
    "gemini_api_key" => { default: nil, type: :string, env: "GEMINI_API_KEY" },
    "gemini_model" => { default: "gemini-2.0-flash", type: :string, env: "GEMINI_MODEL" },
    "openai_api_key" => { default: nil, type: :string, env: "OPENAI_API_KEY" },
    "openai_model" => { default: "gpt-4o-mini", type: :string, env: "OPENAI_MODEL" },
    "ai_grammar_provider" => { default: nil, type: :string, env: nil },
    "ai_grammar_model" => { default: nil, type: :string, env: nil },
    "ai_custom_prompt_provider" => { default: nil, type: :string, env: nil },
    "ai_custom_prompt_model" => { default: nil, type: :string, env: nil },

    # Hugo blog post settings
    "hugo_path_style" => { default: "dated", type: :string, env: "HUGO_PATH_STYLE" },

    # AI Image Generation
    "image_generation_model" => { default: "google/gemini-3.1-flash-image-preview", type: :string, env: "IMAGE_GENERATION_MODEL" }
  }.freeze

  # Keys that should not be exposed to the frontend (sensitive)
  SENSITIVE_KEYS = %w[
    aws_access_key_id
    aws_secret_access_key
    youtube_api_key
    google_api_key
    openai_api_key
    openrouter_api_key
    anthropic_api_key
    gemini_api_key
    share_remote_api_token
    share_remote_signing_secret
    share_remote_alert_webhook_secret
  ].freeze

  # Keys that are UI settings (saved from frontend)
  UI_KEYS = %w[
    theme
    locale
    editor_font
    editor_font_size
    preview_zoom
    preview_width
    preview_font_family
    sidebar_visible
    active_mode
    typewriter_mode
    editor_indent
    editor_line_numbers
    editor_width
  ].freeze

  # AI provider priority (default order when ai_provider = "auto")
  # OpenAI first as most reliable, then cloud providers, then local
  # Gemini is last because its API key is primarily for image generation (Imagen)
  # This allows using Anthropic for text while Gemini handles images
  AI_PROVIDER_PRIORITY = %w[openai anthropic openrouter ollama gemini].freeze
  AI_PROVIDER_METADATA = {
    "openai" => {
      credential_key: "openai_api_key",
      model_key: "openai_model",
      label: "OpenAI"
    },
    "anthropic" => {
      credential_key: "anthropic_api_key",
      model_key: "anthropic_model",
      label: "Anthropic"
    },
    "openrouter" => {
      credential_key: "openrouter_api_key",
      model_key: "openrouter_model",
      label: "OpenRouter"
    },
    "ollama" => {
      credential_key: "ollama_api_base",
      model_key: "ollama_model",
      label: "Ollama"
    },
    "gemini" => {
      credential_key: "gemini_api_key",
      model_key: "gemini_model",
      label: "Google Gemini"
    }
  }.freeze
  AI_FEATURE_SELECTIONS = {
    "grammar" => {
      provider_key: "ai_grammar_provider",
      model_key: "ai_grammar_model"
    },
    "custom_prompt" => {
      provider_key: "ai_custom_prompt_provider",
      model_key: "ai_custom_prompt_model"
    }
  }.freeze

  # AI credential keys - if ANY of these are set in .fed, ignore ALL AI ENV vars
  # This allows users to override their global ENV config per-folder
  # Only includes actual credentials/endpoints, not settings like ai_provider or models
  AI_CREDENTIAL_KEYS = %w[
    ollama_api_base
    openrouter_api_key
    anthropic_api_key
    gemini_api_key
    openai_api_key
  ].freeze

  # Template sections for config file (used for upgrades)
  TEMPLATE_SECTIONS = [
    {
      marker: "# FrankMD Configuration",
      lines: [
        "# FrankMD Configuration",
        "# Uncomment and modify values as needed.",
        "# Environment variables are used as defaults if not specified here."
      ]
    },
    {
      marker: "# UI Settings",
      lines: [
        "",
        "# UI Settings",
        "",
        "# Theme: light, dark, gruvbox, tokyo-night, solarized-dark,",
        "#        solarized-light, nord, cappuccino, osaka, hackerman",
        "# theme = dark",
        "",
        "# Editor font: cascadia-code, jetbrains-mono, fira-code,",
        "#              source-code-pro, ubuntu-mono, roboto-mono, hack",
        "# editor_font = cascadia-code",
        "",
        "# editor_font_size = 14",
        "# preview_zoom = 100",
        "# preview_width = 40",
        "# Preview/reading font family: sans, serif, mono",
        "# preview_font_family = sans",
        "# sidebar_visible = true",
        "# active_mode = raw",
        "# typewriter_mode = false",
        "",
        "# Editor indent: 0 = tab, 1-6 = spaces (default: 2)",
        "# editor_indent = 2",
        "",
        "# Editor width in characters (default: 72, minimum: 72)",
        "# Increase for wider text area, e.g., 100, 120, or 150",
        "# editor_width = 72"
      ]
    },
    {
      marker: "# Local Images",
      lines: [
        "",
        "# Local Images",
        "",
        "# App-managed local images default to .frankmd/images inside notes path.",
        "# images_path = /path/to/images"
      ]
    },
    {
      marker: "# Templates",
      lines: [
        "",
        "# Templates",
        "",
        "# Markdown templates directory (defaults to .frankmd/templates inside notes path)",
        "# templates_path = /path/to/templates"
      ]
    },
    {
      marker: "# Remote Share API",
      lines: [
        "",
        "# Remote Share API",
        "",
        "# Optional: publish shared notes to a hardened VPS-hosted share relay.",
        "# Keep share_backend = local to stay fully local-only.",
        "# share_backend = local",
        "# share_remote_api_scheme = https",
        "# share_remote_api_host = shares.example.com",
        "# share_remote_api_port = 443",
        "# share_remote_public_base = https://shares.example.com",
        "# share_remote_timeout_seconds = 10",
        "# share_remote_verify_tls = true",
        "# share_remote_upload_assets = true",
        "# share_remote_instance_name = my-vps",
        "# Automatically expire remote shares after this many days.",
        "# share_remote_expiration_days = 30",
        "# share_remote_healthchecks_ping_url = https://hc-ping.com/your-uuid",
        "# share_remote_alert_webhook_url = https://hooks.example.com/lewismd",
        "# share_remote_api_token = your-remote-api-token",
        "# share_remote_signing_secret = your-remote-signing-secret",
        "# share_remote_alert_webhook_secret = your-alert-webhook-secret"
      ]
    },
    {
      marker: "# AWS S3",
      lines: [
        "",
        "# AWS S3 (for image uploads)",
        "",
        "# aws_access_key_id = your-access-key",
        "# aws_secret_access_key = your-secret-key",
        "# aws_s3_bucket = your-bucket-name",
        "# aws_region = us-east-1"
      ]
    },
    {
      marker: "# YouTube API",
      lines: [
        "",
        "# YouTube API (for video search)",
        "",
        "# youtube_api_key = your-youtube-api-key"
      ]
    },
    {
      marker: "# Google Custom Search",
      lines: [
        "",
        "# Google Custom Search (for image search)",
        "",
        "# google_api_key = your-google-api-key",
        "# google_cse_id = your-custom-search-engine-id"
      ]
    },
    {
      marker: "# Hugo",
      lines: [
        "",
        "# Hugo Blog Posts",
        "",
        "# Path style: dated = YYYY/MM/DD/slug/index.md (default)",
        "#             flat  = slug.md (in current folder)",
        "# hugo_path_style = dated"
      ]
    },
    {
      marker: "# AI/LLM",
      lines: [
        "",
        "# AI/LLM (for grammar checking)",
        "# Provider priority when ai_provider = auto: openai > anthropic > openrouter > ollama > gemini",
        "# Gemini is lowest priority for text (its key is mainly for image generation)",
        "",
        "# ai_provider = auto",
        "# ai_model = (uses provider-specific default if not set)",
        "# Saved per-feature AI selections (optional)",
        "# ai_grammar_provider = openai",
        "# ai_grammar_model = gpt-4o-mini",
        "# ai_custom_prompt_provider = anthropic",
        "# ai_custom_prompt_model = claude-sonnet-4-20250514",
        "",
        "# OpenAI (recommended)",
        "# openai_api_key = sk-...",
        "# openai_model = gpt-4o-mini",
        "",
        "# Anthropic (Claude models)",
        "# anthropic_api_key = sk-ant-...",
        "# anthropic_model = claude-sonnet-4-20250514",
        "",
        "# Google Gemini",
        "# gemini_api_key = ...",
        "# gemini_model = gemini-2.0-flash",
        "",
        "# OpenRouter (multiple providers, pay-per-use)",
        "# openrouter_api_key = sk-or-...",
        "# openrouter_model = openai/gpt-4o-mini",
        "",
        "# Ollama (local, free) - for privacy, requires local setup",
        "# ollama_api_base = http://localhost:11434",
        "# ollama_model = llama3.2:latest"
      ]
    }
  ].freeze

  attr_reader :base_path, :values

  def initialize(base_path: nil)
    @base_path = Pathname.new(base_path || ENV.fetch("NOTES_PATH", Rails.root.join("notes")))
    Rails.logger.debug("[Config] Initializing with base_path: #{@base_path}")
    @values = {}
    load_config
  end

  # Get a configuration value
  def get(key)
    key = key.to_s
    return nil unless SCHEMA.key?(key)

    # Priority: file value > ENV value > default
    if @values.key?(key)
      @values[key]
    elsif SCHEMA[key][:env] && ENV[SCHEMA[key][:env]].present?
      cast_value(ENV[SCHEMA[key][:env]], SCHEMA[key][:type])
    else
      SCHEMA[key][:default]
    end
  end

  # Set a configuration value and save to file
  def set(key, value)
    key = key.to_s
    return false unless SCHEMA.key?(key)

    casted = cast_value(value, SCHEMA[key][:type])
    @values[key] = casted
    save_single_key(key, casted)
    true
  end

  # Update multiple values at once
  def update(new_values)
    changes = {}
    new_values.each do |key, value|
      key = key.to_s
      next unless SCHEMA.key?(key)
      casted = cast_value(value, SCHEMA[key][:type])
      @values[key] = casted
      changes[key] = casted
    end
    save_keys(changes)
    true
  end

  # Get all UI settings (safe for frontend)
  def ui_settings
    UI_KEYS.each_with_object({}) do |key, hash|
      hash[key] = get(key)
    end
  end

  # Get all settings (for internal use, includes resolved ENV values but masks sensitive data)
  def all_settings(include_sensitive: false)
    SCHEMA.keys.each_with_object({}) do |key, hash|
      if SENSITIVE_KEYS.include?(key)
        if include_sensitive
          hash[key] = get(key)
        else
          # Just indicate if configured (for frontend status display)
          hash["#{key}_configured"] = get(key).present?
        end
      else
        hash[key] = get(key)
      end
    end
  end

  # Check if a feature is available (API key configured)
  def feature_available?(feature)
    case feature.to_s
    when "s3_upload"
      get("aws_access_key_id").present? &&
        get("aws_secret_access_key").present? &&
        get("aws_s3_bucket").present?
    when "youtube_search"
      get("youtube_api_key").present?
    when "google_search"
      get("google_api_key").present? && get("google_cse_id").present?
    when "local_images"
      get("images_path").present?
    when "ai"
      ai_providers_available.any?
    else
      false
    end
  end

  # Check if any AI credential is explicitly set in the .fed file
  # When true, we ignore ALL AI-related ENV vars for credentials
  # This allows per-folder AI config that overrides global ENV settings
  def ai_configured_in_file?
    AI_CREDENTIAL_KEYS.any? { |key| @values.key?(key) }
  end

  # Get an AI-related config value
  # If ANY AI key is in .fed, use ONLY file values (ignore ENV)
  # This allows users to override their ENV-based config per-folder
  def get_ai(key)
    key = key.to_s
    return nil unless SCHEMA.key?(key)

    if ai_configured_in_file?
      # File-only mode: ignore ENV vars for AI
      if @values.key?(key)
        @values[key]
      else
        SCHEMA[key][:default]
      end
    else
      # Normal mode: file > ENV > default
      get(key)
    end
  end

  # Get list of available AI providers (those with credentials configured)
  def ai_providers_available
    AI_PROVIDER_METADATA.each_with_object([]) do |(provider, metadata), available|
      available << provider if get_ai(metadata[:credential_key]).present?
    end
  end

  def ai_provider_options
    AI_PROVIDER_PRIORITY.filter_map do |provider|
      ai_provider_option(provider)
    end
  end

  # Get the effective AI provider based on priority
  def effective_ai_provider
    available = ai_providers_available
    return nil if available.empty?

    configured_provider = get_ai("ai_provider")

    # If a specific provider is configured and available, use it
    if configured_provider.present? && configured_provider != "auto" && available.include?(configured_provider)
      return configured_provider
    end

    # Auto mode: use priority order
    AI_PROVIDER_PRIORITY.find { |p| available.include?(p) }
  end

  # Get the effective model for the current AI provider
  def effective_ai_model
    provider = effective_ai_provider
    return nil unless provider

    # Check for global ai_model override first
    global_model = get_ai("ai_model")
    return global_model if global_model.present?

    # Use provider-specific model
    get_ai("#{provider}_model")
  end

  def effective_ai_option
    provider = effective_ai_provider
    return nil unless provider

    global_model = get_ai("ai_model")
    ai_provider_option(
      provider,
      model: global_model.presence || effective_ai_model,
      model_source: global_model.present? ? "global_override" : "provider_specific",
      selected: true
    )
  end

  def ai_feature_selection_supported?(feature)
    AI_FEATURE_SELECTIONS.key?(feature.to_s)
  end

  def ai_feature_selection(feature)
    feature = feature.to_s
    metadata = AI_FEATURE_SELECTIONS[feature]
    return nil unless metadata

    provider = get(metadata[:provider_key])
    model = get(metadata[:model_key])
    return nil if provider.blank? || model.blank?

    matching_option = ai_provider_options.find do |option|
      option["provider"] == provider && option["model"] == model
    end
    return nil unless matching_option

    matching_option.merge(
      "feature" => feature,
      "model_source" => "saved_preference",
      "saved" => true,
      "selected" => true
    )
  end

  def ai_saved_selections
    AI_FEATURE_SELECTIONS.keys.each_with_object({}) do |feature, selections|
      selections[feature] = ai_feature_selection(feature)
    end
  end

  def save_ai_feature_selection(feature, provider:, model:)
    feature = feature.to_s
    metadata = AI_FEATURE_SELECTIONS[feature]
    return nil unless metadata

    matching_option = ai_provider_options.find do |option|
      option["provider"] == provider.to_s && option["model"] == model.to_s
    end
    return nil unless matching_option

    update(
      metadata[:provider_key] => matching_option["provider"],
      metadata[:model_key] => matching_option["model"]
    )

    ai_feature_selection(feature)
  end

  # Get the effective value for a setting (used by services)
  def effective_value(key)
    get(key)
  end

  # Ensure config file exists and is up to date
  def ensure_config_file
    if config_file_path.exist?
      upgrade_config_file
    else
      Rails.logger.warn("[Config] .fed not found at #{config_file_path}, creating template...")
      create_template_config
    end
  end

  def config_file_path
    @base_path.join(CONFIG_FILE)
  end

  private

  def load_config
    ensure_config_file
    return unless config_file_path.exist?

    content = config_file_path.read
    parse_config(content)
  rescue => e
    Rails.logger.error("Failed to load .fed config: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    @values = {}
  end

  def parse_config(content)
    @values = {}

    content.each_line do |line|
      line = line.strip

      # Skip empty lines and comments
      next if line.empty? || line.start_with?("#")

      # Parse key = value format (keys can contain letters, numbers, and underscores)
      if line =~ /^([a-z0-9_]+)\s*=\s*(.*)$/i
        key = $1.downcase
        value = $2.strip

        # Remove surrounding quotes if present
        value = value[1..-2] if value.start_with?('"') && value.end_with?('"')
        value = value[1..-2] if value.start_with?("'") && value.end_with?("'")

        # Only accept known keys
        if SCHEMA.key?(key)
          @values[key] = cast_value(value, SCHEMA[key][:type])
        end
      end
    end
  end

  def cast_value(value, type)
    return nil if value.nil? || value.to_s.strip.empty?

    case type
    when :integer
      value.to_i
    when :boolean
      %w[true 1 yes on].include?(value.to_s.downcase)
    when :string
      value.to_s
    else
      value
    end
  end

  # Save a single key to the config file (surgical update)
  def save_single_key(key, value)
    save_keys({ key => value })
  end

  # Save multiple keys to the config file (surgical update)
  # Only modifies the specified keys, preserves everything else exactly as-is
  def save_keys(changes)
    return if changes.empty?

    ensure_config_file

    lines = []
    keys_written = Set.new

    config_file_path.read.each_line do |line|
      stripped = line.strip

      if stripped.empty?
        # Preserve empty lines
        lines << ""
      elsif stripped.start_with?("#")
        # Check if this is a commented-out key we're now setting
        if stripped =~ /^#\s*([a-z0-9_]+)\s*=/i
          key = $1.downcase
          if changes.key?(key) && !keys_written.include?(key)
            # Replace commented line with actual value
            lines << format_value(key, changes[key])
            keys_written.add(key)
            next
          end
        end
        # Preserve comment line as-is
        lines << line.chomp
      elsif stripped =~ /^([a-z0-9_]+)\s*=/i
        key = $1.downcase
        if changes.key?(key)
          # Update this key with new value
          lines << format_value(key, changes[key])
          keys_written.add(key)
        else
          # Preserve line exactly as-is (including original formatting)
          lines << line.chomp
        end
      else
        # Preserve any other line (malformed or unknown)
        lines << line.chomp
      end
    end

    # Append any new keys that weren't in the file
    changes.each do |key, value|
      unless keys_written.include?(key)
        lines << format_value(key, value)
      end
    end

    config_file_path.write(lines.join("\n") + "\n")
  rescue => e
    Rails.logger.error("Failed to save .fed config: #{e.message}")
    false
  end

  def format_value(key, value)
    case SCHEMA[key][:type]
    when :string
      if value.to_s.include?(" ") || value.to_s.include?("=")
        "#{key} = \"#{value}\""
      else
        "#{key} = #{value}"
      end
    when :boolean
      "#{key} = #{value ? 'true' : 'false'}"
    else
      "#{key} = #{value}"
    end
  end

  def create_template_config
    target_path = config_file_path
    target_dir = target_path.dirname

    # Ensure parent directory exists
    unless target_dir.exist?
      Rails.logger.warn("[Config] Creating notes directory: #{target_dir}")
      target_dir.mkpath
    end

    lines = generate_template_lines
    Rails.logger.warn("[Config] Writing .fed config to: #{target_path}")
    target_path.write(lines.join("\n") + "\n")
    Rails.logger.warn("[Config] Successfully created .fed config")
  rescue Errno::EACCES => e
    Rails.logger.error("[Config] Permission denied creating .fed at #{config_file_path}: #{e.message}")
  rescue Errno::EROFS => e
    Rails.logger.error("[Config] Read-only filesystem, cannot create .fed at #{config_file_path}: #{e.message}")
  rescue => e
    Rails.logger.error("[Config] Failed to create .fed at #{config_file_path}: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
  end

  # Upgrade existing config file by adding NEW sections only
  # This is conservative: only adds sections for new features (like AI/LLM)
  # It does NOT re-add sections the user may have intentionally removed
  def upgrade_config_file
    return unless config_file_path.exist?

    content = config_file_path.read
    existing_lines = content.lines.map(&:chomp)

    ai_keys = %w[ai_provider ai_model ai_grammar_provider ai_grammar_model ai_custom_prompt_provider ai_custom_prompt_model ollama_api_base ollama_model
                 openrouter_api_key openrouter_model anthropic_api_key anthropic_model
                 gemini_api_key gemini_model openai_api_key openai_model]
    remote_share_keys = %w[
      share_backend
      share_remote_api_scheme
      share_remote_api_host
      share_remote_api_port
      share_remote_public_base
      share_remote_timeout_seconds
      share_remote_verify_tls
      share_remote_upload_assets
      share_remote_instance_name
      share_remote_expiration_days
      share_remote_healthchecks_ping_url
      share_remote_alert_webhook_url
      share_remote_api_token
      share_remote_signing_secret
      share_remote_alert_webhook_secret
    ]
    new_lines = existing_lines.dup
    changed = false

    unless section_present?(existing_lines, "# Templates", %w[templates_path])
      new_lines << "" if new_lines.last&.strip&.present?
      new_lines.concat(section_lines("# Templates"))
      changed = true
    end

    unless section_present?(existing_lines, "# Remote Share API", remote_share_keys)
      new_lines << "" if new_lines.last&.strip&.present?
      new_lines.concat(section_lines("# Remote Share API"))
      changed = true
    else
      changed = ensure_setting_lines_present!(
        existing_lines: existing_lines,
        new_lines: new_lines,
        marker: "# Remote Share API",
        key: "share_remote_expiration_days",
        lines_to_insert: [
          "# Automatically expire remote shares after this many days.",
          "# share_remote_expiration_days = 30"
        ],
        after_key: "share_remote_instance_name"
      ) || changed
    end

    unless section_present?(existing_lines, "# AI/LLM", ai_keys)
      new_lines << "" if new_lines.last&.strip&.present?
      new_lines.concat(section_lines("# AI/LLM"))
      changed = true
    else
      changed = ensure_setting_lines_present!(
        existing_lines: existing_lines,
        new_lines: new_lines,
        marker: "# AI/LLM",
        key: "ai_grammar_provider",
        lines_to_insert: [
          "# Saved per-feature AI selections (optional)",
          "# ai_grammar_provider = openai",
          "# ai_grammar_model = gpt-4o-mini",
          "# ai_custom_prompt_provider = anthropic",
          "# ai_custom_prompt_model = claude-sonnet-4-20250514"
        ],
        after_key: "ai_model"
      ) || changed
    end

    return unless changed

    config_file_path.write(new_lines.join("\n") + "\n")
    Rails.logger.info("Upgraded .fed config with new sections")
  rescue => e
    Rails.logger.warn("Failed to upgrade .fed config: #{e.message}")
  end

  def section_present?(lines, marker, keys)
    lines.any? do |line|
      line.include?(marker) || keys.any? { |key| line =~ /^#?\s*#{Regexp.escape(key)}\s*=/i }
    end
  end

  def section_lines(marker)
    TEMPLATE_SECTIONS.find { |section| section[:marker] == marker }&.fetch(:lines, []) || []
  end

  def ensure_setting_lines_present!(existing_lines:, new_lines:, marker:, key:, lines_to_insert:, after_key: nil)
    return false if setting_present?(existing_lines, key)

    marker_index = new_lines.index { |line| line.include?(marker) }
    return false unless marker_index

    section_end_index = next_section_index(new_lines, marker_index)
    insertion_index = insertion_index_for_setting(new_lines, marker_index, section_end_index, after_key)
    new_lines.insert(insertion_index, *lines_to_insert)
    true
  end

  def setting_present?(lines, key)
    lines.any? { |line| line =~ /^#?\s*#{Regexp.escape(key)}\s*=/i }
  end

  def next_section_index(lines, marker_index)
    next_marker_index = lines[(marker_index + 1)..]&.find_index do |line|
      TEMPLATE_SECTIONS.any? { |section| line.include?(section[:marker]) }
    end

    next_marker_index ? marker_index + 1 + next_marker_index : lines.length
  end

  def insertion_index_for_setting(lines, marker_index, section_end_index, after_key)
    return section_end_index unless after_key.present?

    anchor_relative_index = lines[(marker_index + 1)...section_end_index]&.find_index do |line|
      line =~ /^#?\s*#{Regexp.escape(after_key)}\s*=/i
    end

    anchor_relative_index ? marker_index + 2 + anchor_relative_index : section_end_index
  end

  def generate_template_lines
    TEMPLATE_SECTIONS.flat_map { |section| section[:lines] }
  end

  def generate_config_lines
    lines = generate_template_lines

    # Replace commented lines with actual values where we have them
    @values.each do |key, value|
      pattern = /^# #{key} = /
      index = lines.find_index { |l| l =~ pattern }
      if index
        lines[index] = format_value(key, value)
      else
        lines << format_value(key, value)
      end
    end

    lines
  end

  def ai_provider_option(provider, model: nil, model_source: "provider_specific", selected: false)
    provider = provider.to_s
    metadata = AI_PROVIDER_METADATA[provider]
    return nil unless metadata && ai_providers_available.include?(provider)

    resolved_model = model.presence || get_ai(metadata[:model_key])
    return nil if resolved_model.blank?

    {
      "provider" => provider,
      "provider_label" => metadata[:label],
      "model" => resolved_model,
      "label" => "#{metadata[:label]} · #{resolved_model}",
      "model_source" => model_source,
      "selected" => selected
    }
  end
end
