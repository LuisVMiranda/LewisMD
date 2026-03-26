# frozen_string_literal: true

require "test_helper"

class AiServiceTest < ActiveSupport::TestCase
  def setup
    setup_test_notes_dir
    # Save and clear all AI-related env vars
    @original_env = {}
    %w[
      OPENAI_API_KEY OPENROUTER_API_KEY ANTHROPIC_API_KEY
      GEMINI_API_KEY OLLAMA_API_BASE AI_PROVIDER AI_MODEL
      OPENAI_MODEL OPENROUTER_MODEL ANTHROPIC_MODEL GEMINI_MODEL OLLAMA_MODEL
      IMAGE_GENERATION_MODEL
    ].each do |key|
      @original_env[key] = ENV[key]
      ENV.delete(key)
    end
  end

  def teardown
    teardown_test_notes_dir
    # Restore original env vars
    @original_env.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end

  # Provider detection tests
  test "enabled? returns false when no providers configured" do
    assert_not AiService.enabled?
  end

  test "enabled? returns true when OpenAI key is set" do
    ENV["OPENAI_API_KEY"] = "sk-test-key"
    assert AiService.enabled?
  end

  test "enabled? returns true when OpenRouter key is set" do
    ENV["OPENROUTER_API_KEY"] = "sk-or-test-key"
    assert AiService.enabled?
  end

  test "enabled? returns true when Anthropic key is set" do
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test-key"
    assert AiService.enabled?
  end

  test "enabled? returns true when Gemini key is set" do
    ENV["GEMINI_API_KEY"] = "gemini-test-key"
    assert AiService.enabled?
  end

  test "enabled? returns true when Ollama base is set" do
    ENV["OLLAMA_API_BASE"] = "http://localhost:11434"
    assert AiService.enabled?
  end

  # Provider priority tests (auto mode)
  # Priority: openai > anthropic > openrouter > ollama > gemini
  # Gemini is lowest because its key is primarily for image generation (Imagen)
  test "current_provider returns openai when multiple providers available" do
    ENV["OLLAMA_API_BASE"] = "http://localhost:11434"
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

    assert_equal "openai", AiService.current_provider
  end

  test "current_provider returns anthropic when openai not available" do
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"
    ENV["GEMINI_API_KEY"] = "gemini-test"

    assert_equal "anthropic", AiService.current_provider
  end

  test "current_provider returns openrouter when higher priority not available" do
    ENV["OPENROUTER_API_KEY"] = "sk-or-test"
    ENV["OLLAMA_API_BASE"] = "http://localhost:11434"
    ENV["GEMINI_API_KEY"] = "gemini-test"

    assert_equal "openrouter", AiService.current_provider
  end

  test "current_provider returns ollama over gemini" do
    ENV["OLLAMA_API_BASE"] = "http://localhost:11434"
    ENV["GEMINI_API_KEY"] = "gemini-test"

    assert_equal "ollama", AiService.current_provider
  end

  test "current_provider returns gemini when only gemini available" do
    ENV["GEMINI_API_KEY"] = "gemini-test"

    assert_equal "gemini", AiService.current_provider
  end

  # Provider override tests
  test "current_provider respects ai_provider override" do
    ENV["OLLAMA_API_BASE"] = "http://localhost:11434"
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["AI_PROVIDER"] = "openai"

    assert_equal "openai", AiService.current_provider
  end

  test "current_provider falls back to priority when override not available" do
    ENV["OLLAMA_API_BASE"] = "http://localhost:11434"
    ENV["AI_PROVIDER"] = "openai"  # OpenAI not configured

    assert_equal "ollama", AiService.current_provider
  end

  # Model selection tests
  test "current_model returns provider-specific default" do
    ENV["OPENAI_API_KEY"] = "sk-test"
    assert_equal "gpt-4o-mini", AiService.current_model
  end

  test "current_model returns ollama default model" do
    ENV["OLLAMA_API_BASE"] = "http://localhost:11434"
    assert_equal "llama3.2:latest", AiService.current_model
  end

  test "current_model returns anthropic default model" do
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"
    assert_equal "claude-sonnet-4-20250514", AiService.current_model
  end

  test "current_model returns gemini default model" do
    ENV["GEMINI_API_KEY"] = "gemini-test"
    assert_equal "gemini-2.0-flash", AiService.current_model
  end

  test "current_model returns openrouter default model" do
    ENV["OPENROUTER_API_KEY"] = "sk-or-test"
    assert_equal "openai/gpt-4o-mini", AiService.current_model
  end

  test "current_model respects ai_model global override" do
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["AI_MODEL"] = "gpt-4-turbo"

    assert_equal "gpt-4-turbo", AiService.current_model
  end

  test "current_model respects provider-specific model override" do
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"
    ENV["ANTHROPIC_MODEL"] = "claude-3-opus-20240229"

    assert_equal "claude-3-opus-20240229", AiService.current_model
  end

  # Error handling tests
  test "fix_grammar returns error when not configured" do
    result = AiService.fix_grammar("Hello world")
    assert_equal "AI not configured", result[:error]
  end

  test "fix_grammar returns error when text is blank" do
    ENV["OPENAI_API_KEY"] = "sk-test-key"
    result = AiService.fix_grammar("")
    assert_equal "No text provided", result[:error]
  end

  test "fix_grammar returns error when text is nil" do
    ENV["OPENAI_API_KEY"] = "sk-test-key"
    result = AiService.fix_grammar(nil)
    assert_equal "No text provided", result[:error]
  end

  test "generate_custom_prompt returns error when prompt is blank" do
    ENV["OPENAI_API_KEY"] = "sk-test-key"
    result = AiService.generate_custom_prompt("Hello world", "")
    assert_equal "No prompt provided", result[:error]
  end

  test "generate_custom_prompt allows empty note content" do
    ENV["OPENAI_API_KEY"] = "sk-test-key"

    mock_response = stub(content: "# Fresh Start\n\nGenerated from instructions.")
    mock_chat = mock
    mock_chat.expects(:with_instructions).returns(mock_chat)
    mock_chat.expects(:ask).with(includes("The current note is empty.")).returns(mock_response)

    RubyLLM.stubs(:chat).returns(mock_chat)

    result = AiService.generate_custom_prompt("", "Write an opening section")

    assert_equal "# Fresh Start\n\nGenerated from instructions.", result[:corrected]
    assert_equal "openai", result[:provider]
    assert_equal "gpt-4o-mini", result[:model]
  end

  test "clean_custom_prompt_output strips intro, fences, and trailing call to action" do
    raw = <<~TEXT
      Here's the rewritten version:

      ```markdown
      # Clean Note

      Body paragraph.
      ```

      Let me know if you'd like a shorter version too.
    TEXT

    assert_equal "# Clean Note\n\nBody paragraph.", AiService.send(:clean_custom_prompt_output, raw)
  end

  test "clean_custom_prompt_output keeps direct note content unchanged" do
    text = "# Heading\n\nBody line."
    assert_equal text, AiService.send(:clean_custom_prompt_output, text)
  end

  # Provider info tests
  test "provider_info returns correct structure" do
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

    info = AiService.provider_info

    assert_includes info.keys, :enabled
    assert_includes info.keys, :provider
    assert_includes info.keys, :model
    assert_includes info.keys, :available_providers
    assert_includes info.keys, :available_options
    assert_includes info.keys, :default_option
    assert_includes info.keys, :current_selection
    assert_includes info.keys, :selection_states

    assert info[:enabled]
    assert_equal "openai", info[:provider]  # openai has highest priority
    assert_includes info[:available_providers], "openai"
    assert_includes info[:available_providers], "anthropic"
    assert_equal %w[openai anthropic], info[:available_options].map { |option| option["provider"] }
    assert_equal "openai", info[:default_option]["provider"]
    assert_equal "gpt-4o-mini", info[:default_option]["model"]
    assert_equal "openai", info[:current_selection]["provider"]
    assert_equal "gpt-4o-mini", info[:current_selection]["model"]
    assert_equal({ "grammar" => nil, "custom_prompt" => nil }, info[:saved_selections])
    assert_equal false, info[:selection_states]["grammar"]["invalid"]
    assert_equal false, info[:selection_states]["custom_prompt"]["invalid"]
  end

  test "provider_info does not expose api credentials" do
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

    info = AiService.provider_info

    assert_not_includes info.keys, :openai_api_key
    assert_not_includes info.keys, :anthropic_api_key
    refute_includes info.to_json, "sk-test"
    refute_includes info.to_json, "sk-ant-test"
  end

  test "provider_info exposes invalid saved selection states when configured choices disappear" do
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"
    notes_path = Pathname.new(ENV.fetch("NOTES_PATH"))
    notes_path.join(".fed").write(<<~CONFIG)
      ai_grammar_provider = openai
      ai_grammar_model = gpt-4-turbo
    CONFIG

    info = AiService.provider_info

    assert_nil info[:saved_selections]["grammar"]
    assert_equal true, info[:selection_states]["grammar"]["configured"]
    assert_equal true, info[:selection_states]["grammar"]["invalid"]
    assert_equal "openai", info[:selection_states]["grammar"]["provider"]
    assert_equal "gpt-4-turbo", info[:selection_states]["grammar"]["model"]
  end

  test "available_providers returns all configured providers" do
    ENV["OLLAMA_API_BASE"] = "http://localhost:11434"
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

    providers = AiService.available_providers

    assert_includes providers, "ollama"
    assert_includes providers, "openai"
    assert_includes providers, "anthropic"
    assert_not_includes providers, "gemini"
    assert_not_includes providers, "openrouter"
  end

  test "available_options uses provider-specific models even when ai_model is globally overridden" do
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"
    ENV["AI_MODEL"] = "gpt-4-turbo"

    options = AiService.available_options

    assert_equal "gpt-4o-mini", options.find { |option| option["provider"] == "openai" }["model"]
    assert_equal "claude-sonnet-4-20250514", options.find { |option| option["provider"] == "anthropic" }["model"]

    selection = AiService.current_selection
    assert_equal "openai", selection["provider"]
    assert_equal "gpt-4-turbo", selection["model"]
    assert_equal "global_override", selection["model_source"]
  end

  test "save_selection persists a feature-specific choice and returns all saved selections" do
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

    result = AiService.save_selection(
      feature: "grammar",
      provider: "anthropic",
      model: "claude-sonnet-4-20250514"
    )

    assert_nil result[:error]
    assert_equal "anthropic", result[:selection]["provider"]
    assert_equal "saved_preference", result[:selection]["model_source"]
    assert_equal "anthropic", result[:saved_selections]["grammar"]["provider"]
    assert_nil result[:saved_selections]["custom_prompt"]
    assert_equal false, result[:selection_states]["grammar"]["invalid"]
  end

  test "save_selection rejects unsupported features" do
    ENV["OPENAI_API_KEY"] = "sk-test"

    result = AiService.save_selection(
      feature: "summaries",
      provider: "openai",
      model: "gpt-4o-mini"
    )

    assert_equal "Unsupported AI feature.", result[:error]
  end

  test "save_selection rejects stale provider model pairs" do
    ENV["OPENAI_API_KEY"] = "sk-test"

    result = AiService.save_selection(
      feature: "grammar",
      provider: "openai",
      model: "gpt-4-turbo"
    )

    assert_equal "That AI option is no longer available.", result[:error]
  end

  test "save_selection returns a gentle error when config persistence fails" do
    config = mock
    config.expects(:ai_feature_selection_supported?).with("grammar").returns(true)
    config.expects(:save_ai_feature_selection).with("grammar", provider: "openai", model: "gpt-4o-mini").returns(false)
    Config.stubs(:new).returns(config)

    result = AiService.save_selection(
      feature: "grammar",
      provider: "openai",
      model: "gpt-4o-mini"
    )

    assert_equal "We couldn't save your AI choice right now.", result[:error]
  end

  # Image generation tests
  test "image_generation_enabled? returns false when no OpenRouter key" do
    assert_not AiService.image_generation_enabled?
  end

  test "image_generation_enabled? returns true when OpenRouter key is set" do
    ENV["OPENROUTER_API_KEY"] = "sk-or-test-key"
    assert AiService.image_generation_enabled?
  end

  test "image_generation_model returns default model" do
    assert_equal "google/gemini-3.1-flash-image-preview", AiService.image_generation_model
  end

  test "image_generation_info returns correct structure" do
    info = AiService.image_generation_info
    assert_includes info.keys, :enabled
    assert_includes info.keys, :model
    assert_equal false, info[:enabled]
    assert_equal "google/gemini-3.1-flash-image-preview", info[:model]
  end

  test "image_generation_info returns enabled when OpenRouter key set" do
    ENV["OPENROUTER_API_KEY"] = "sk-or-test-key"
    info = AiService.image_generation_info
    assert_equal true, info[:enabled]
  end

  test "generate_image returns error when not configured" do
    result = AiService.generate_image("A sunset over mountains")
    assert_includes result[:error], "not configured"
  end

  test "generate_image returns error when prompt is blank" do
    ENV["OPENROUTER_API_KEY"] = "sk-or-test-key"
    result = AiService.generate_image("")
    assert_equal "No prompt provided", result[:error]
  end

  test "generate_image returns error when prompt is nil" do
    ENV["OPENROUTER_API_KEY"] = "sk-or-test-key"
    result = AiService.generate_image(nil)
    assert_equal "No prompt provided", result[:error]
  end

  test "generate_image accepts reference_image_path parameter" do
    ENV["OPENROUTER_API_KEY"] = "sk-or-test-key"
    # This will fail at the API call since we don't have a real key,
    # but it verifies the method accepts the parameter
    result = AiService.generate_image("A sunset", reference_image_path: "nonexistent.jpg")
    # Should not error on the parameter itself - will fail later at API call
    # Reference image doesn't exist, so it falls back to text-only which hits OpenRouter
    assert result[:error].present?
  end

  # === fix_grammar success path (mocked) ===

  test "fix_grammar returns corrected text on success" do
    ENV["OPENAI_API_KEY"] = "sk-test-key"

    # Create mock response and chat objects using mocha
    mock_response = stub(content: "This is corrected text.")
    mock_chat = stub
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.stubs(:ask).returns(mock_response)

    RubyLLM.stubs(:chat).returns(mock_chat)

    result = AiService.fix_grammar("This is uncorrected text")

    assert_equal "This is corrected text.", result[:corrected]
    assert_equal "openai", result[:provider]
    assert_equal "gpt-4o-mini", result[:model]
  end

  test "fix_grammar logs selection details without credential prefixes" do
    ENV["OPENAI_API_KEY"] = "sk-test-key"

    mock_response = stub(content: "This is corrected text.")
    mock_chat = stub
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.stubs(:ask).returns(mock_response)

    RubyLLM.stubs(:chat).returns(mock_chat)
    Rails.logger.expects(:info).with do |message|
      message.include?("feature=grammar") &&
        message.include?("provider=openai") &&
        !message.include?("key_prefix") &&
        !message.include?("sk-test-key")
    end

    result = AiService.fix_grammar("This is uncorrected text")

    assert_equal "This is corrected text.", result[:corrected]
  end

  test "fix_grammar uses an explicit validated provider selection when supplied" do
    ENV["OPENAI_API_KEY"] = "sk-test-key"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

    mock_response = stub(content: "Fixed by explicit Claude selection.")
    mock_chat = stub
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.stubs(:ask).returns(mock_response)

    RubyLLM.expects(:chat).with(
      model: "claude-sonnet-4-20250514",
      provider: :anthropic,
      assume_model_exists: false
    ).returns(mock_chat)

    result = AiService.fix_grammar(
      "This is uncorrected text",
      provider: "anthropic",
      model: "claude-sonnet-4-20250514"
    )

    assert_equal "Fixed by explicit Claude selection.", result[:corrected]
    assert_equal "anthropic", result[:provider]
    assert_equal "claude-sonnet-4-20250514", result[:model]
  end

  test "fix_grammar rejects partial provider selections" do
    ENV["OPENAI_API_KEY"] = "sk-test-key"

    result = AiService.fix_grammar("Some text", provider: "openai")

    assert_equal "Provider and model must be supplied together.", result[:error]
  end

  test "fix_grammar rejects unavailable provider model pairs" do
    ENV["OPENAI_API_KEY"] = "sk-test-key"

    result = AiService.fix_grammar("Some text", provider: "openai", model: "gpt-4-turbo")

    assert_equal "That AI option is no longer available.", result[:error]
  end

  test "fix_grammar returns error on API failure" do
    ENV["OPENAI_API_KEY"] = "sk-test-key"

    mock_chat = stub
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.stubs(:ask).raises(StandardError.new("API connection failed"))

    RubyLLM.stubs(:chat).returns(mock_chat)

    result = AiService.fix_grammar("Some text")

    assert result[:error].present?
    assert_includes result[:error], "API connection failed"
  end

  test "fix_grammar redacts credential values from provider failures" do
    ENV["OPENAI_API_KEY"] = "sk-test-key"

    mock_chat = stub
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.stubs(:ask).raises(StandardError.new("OpenAI rejected sk-test-key during authentication"))

    RubyLLM.stubs(:chat).returns(mock_chat)

    result = AiService.fix_grammar("Some text")

    assert_includes result[:error], "[redacted]"
    refute_includes result[:error], "sk-test-key"
  end

  test "fix_grammar works with anthropic provider" do
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

    mock_response = stub(content: "Fixed by Claude")
    mock_chat = stub
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.stubs(:ask).returns(mock_response)

    RubyLLM.stubs(:chat).returns(mock_chat)

    result = AiService.fix_grammar("Input text")

    assert_equal "Fixed by Claude", result[:corrected]
    assert_equal "anthropic", result[:provider]
  end

  test "generate_custom_prompt uses strict instructions and returns cleaned text" do
    ENV["OPENAI_API_KEY"] = "sk-test-key"

    mock_response = stub(content: "Here is the revised version:\n\nBetter text.\n\nLet me know if you'd like more changes.")
    mock_chat = mock
    mock_chat.expects(:with_instructions).with(includes("Return ONLY the transformed text")).returns(mock_chat)
    mock_chat.expects(:ask).with("Original draft").returns(mock_response)

    RubyLLM.stubs(:chat).returns(mock_chat)

    result = AiService.generate_custom_prompt("Original draft", "Rewrite this professionally")

    assert_equal "Better text.", result[:corrected]
    assert_equal "openai", result[:provider]
    assert_equal "gpt-4o-mini", result[:model]
  end

  test "generate_custom_prompt uses an explicit validated provider selection when supplied" do
    ENV["OPENAI_API_KEY"] = "sk-test-key"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

    mock_response = stub(content: "Updated by Claude.")
    mock_chat = mock
    mock_chat.expects(:with_instructions).with(includes("Rewrite this professionally")).returns(mock_chat)
    mock_chat.expects(:ask).with("Original draft").returns(mock_response)

    RubyLLM.expects(:chat).with(
      model: "claude-sonnet-4-20250514",
      provider: :anthropic,
      assume_model_exists: false
    ).returns(mock_chat)

    result = AiService.generate_custom_prompt(
      "Original draft",
      "Rewrite this professionally",
      provider: "anthropic",
      model: "claude-sonnet-4-20250514"
    )

    assert_equal "Updated by Claude.", result[:corrected]
    assert_equal "anthropic", result[:provider]
    assert_equal "claude-sonnet-4-20250514", result[:model]
  end

  # === Image generation response parsing ===

  test "extract_image_from_response extracts base64 from RubyLLM Content with attachments" do
    mock_attachment = stub(content: "binary_image_data", mime_type: "image/png")
    mock_content = stub(attachments: [ mock_attachment ], text: "Image generated")
    mock_content.stubs(:is_a?).returns(false)
    mock_content.stubs(:is_a?).with(RubyLLM::Content).returns(true)
    mock_response = stub(content: mock_content)

    result = AiService.extract_image_from_response(mock_response, "google/gemini-3.1-flash-image-preview")

    assert_nil result[:error]
    assert_equal Base64.strict_encode64("binary_image_data"), result[:data]
    assert_equal "image/png", result[:mime_type]
    assert_equal "google/gemini-3.1-flash-image-preview", result[:model]
  end

  test "extract_image_from_response returns error when no attachments" do
    mock_content = stub(attachments: [], text: "I cannot generate that image")
    mock_content.stubs(:is_a?).returns(false)
    mock_content.stubs(:is_a?).with(RubyLLM::Content).returns(true)
    mock_response = stub(content: mock_content)

    result = AiService.extract_image_from_response(mock_response, "model")

    assert_equal "No image data in response", result[:error]
  end

  test "extract_image_from_response handles plain string content" do
    mock_response = stub(content: "Some text response")

    result = AiService.extract_image_from_response(mock_response, "model")

    assert_equal "No image data in response", result[:error]
  end
end

# === Image generation with mocked RubyLLM ===

class AiServiceImageGenerationTest < ActiveSupport::TestCase
  def setup
    setup_test_notes_dir
    @original_env = {}
    %w[OPENROUTER_API_KEY].each do |key|
      @original_env[key] = ENV[key]
      ENV.delete(key)
    end
    ENV["OPENROUTER_API_KEY"] = "sk-or-test-key"

    # Stub images path so ImagesService.find_image works
    @config_stub = stub("config")
    @config_stub.stubs(:get).returns(nil)
    @config_stub.stubs(:get).with("images_path").returns(@test_notes_dir.to_s)
    @config_stub.stubs(:get).with("image_generation_model").returns(nil)
    @config_stub.stubs(:feature_available?).returns(false)
    @config_stub.stubs(:feature_available?).with("ai").returns(true)
    @config_stub.stubs(:ai_providers_available).returns([ "openrouter" ])
    @config_stub.stubs(:effective_ai_provider).returns("openrouter")
    @config_stub.stubs(:effective_ai_model).returns("openai/gpt-4o-mini")
    @config_stub.stubs(:get_ai).returns(nil)
    @config_stub.stubs(:get_ai).with("openrouter_api_key").returns("sk-or-test-key")
    @config_stub.stubs(:ai_configured_in_file?).returns(false)
    # Allow openrouter_key_for_images to find the key via instance_variable_get
    @config_stub.stubs(:instance_variable_get).with(:@values).returns({ "openrouter_api_key" => "sk-or-test-key" })
    Config.stubs(:new).returns(@config_stub)
  end

  def teardown
    teardown_test_notes_dir
    @original_env.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end

  test "generate_image text-only returns image data on success" do
    mock_attachment = stub(content: "png_binary_data", mime_type: "image/png")
    mock_content = stub(attachments: [ mock_attachment ], text: "Image generated")
    mock_content.stubs(:is_a?).returns(false)
    mock_content.stubs(:is_a?).with(RubyLLM::Content).returns(true)
    mock_response = stub(content: mock_content)

    mock_chat = stub
    mock_chat.stubs(:with_params).returns(mock_chat)
    mock_chat.stubs(:ask).with("A sunset over mountains").returns(mock_response)
    RubyLLM.stubs(:chat).returns(mock_chat)

    result = AiService.generate_image("A sunset over mountains")

    assert_nil result[:error]
    assert_equal Base64.strict_encode64("png_binary_data"), result[:data]
    assert_equal "image/png", result[:mime_type]
    assert_equal "google/gemini-3.1-flash-image-preview", result[:model]
  end

  test "generate_image handles API error" do
    mock_chat = stub
    mock_chat.stubs(:with_params).returns(mock_chat)
    mock_chat.stubs(:ask).raises(StandardError.new("OpenRouter API error: Invalid prompt"))
    RubyLLM.stubs(:chat).returns(mock_chat)

    result = AiService.generate_image("bad prompt")

    assert result[:error].present?
    assert_includes result[:error], "Invalid prompt"
  end

  test "generate_image with reference passes content with attachment" do
    # Create a reference image file
    ref_path = create_test_note("ref_image.png")
    png_data = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
      0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
      0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xE7, 0x00, 0x00,
      0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ].pack("C*")
    File.binwrite(ref_path, png_data)

    mock_attachment = stub(content: "edited_binary_data", mime_type: "image/jpeg")
    mock_content = stub(attachments: [ mock_attachment ], text: "Edited image")
    mock_content.stubs(:is_a?).returns(false)
    mock_content.stubs(:is_a?).with(RubyLLM::Content).returns(true)
    mock_response = stub(content: mock_content)

    mock_chat = stub
    mock_chat.stubs(:with_params).returns(mock_chat)
    mock_chat.stubs(:ask).with(instance_of(RubyLLM::Content)).returns(mock_response)
    RubyLLM.stubs(:chat).returns(mock_chat)

    result = AiService.generate_image("Make it brighter", reference_image_path: "ref_image.png")

    assert_nil result[:error]
    assert_equal Base64.strict_encode64("edited_binary_data"), result[:data]
    assert_equal "image/jpeg", result[:mime_type]
    assert_equal "google/gemini-3.1-flash-image-preview", result[:model]
  end

  test "generate_image handles text-only response (no image generated)" do
    mock_content = stub(attachments: [], text: "I cannot generate that image")
    mock_content.stubs(:is_a?).returns(false)
    mock_content.stubs(:is_a?).with(RubyLLM::Content).returns(true)
    mock_response = stub(content: mock_content)

    mock_chat = stub
    mock_chat.stubs(:with_params).returns(mock_chat)
    mock_chat.stubs(:ask).returns(mock_response)
    RubyLLM.stubs(:chat).returns(mock_chat)

    result = AiService.generate_image("Generate something impossible")

    assert_equal "No image data in response", result[:error]
  end

  test "generate_image falls back to text-only when reference image not found" do
    mock_attachment = stub(content: "fallback_data", mime_type: "image/png")
    mock_content = stub(attachments: [ mock_attachment ], text: "Generated")
    mock_content.stubs(:is_a?).returns(false)
    mock_content.stubs(:is_a?).with(RubyLLM::Content).returns(true)
    mock_response = stub(content: mock_content)

    mock_chat = stub
    mock_chat.stubs(:with_params).returns(mock_chat)
    # When ref image not found, prompt is passed as string (not Content)
    mock_chat.stubs(:ask).with("A cat").returns(mock_response)
    RubyLLM.stubs(:chat).returns(mock_chat)

    result = AiService.generate_image("A cat", reference_image_path: "nonexistent.png")

    assert_nil result[:error]
    assert_equal Base64.strict_encode64("fallback_data"), result[:data]
  end
end
