# frozen_string_literal: true

require "test_helper"

class AiControllerTest < ActionDispatch::IntegrationTest
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

  # Config endpoint tests
  test "config returns enabled false when no API keys" do
    get "/ai/config", as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal false, data["enabled"]
    assert_nil data["provider"]
    assert_nil data["model"]
    assert_empty data["available_providers"]
  end

  test "config returns enabled true when OpenAI key is set" do
    ENV["OPENAI_API_KEY"] = "sk-test-key"

    get "/ai/config", as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal true, data["enabled"]
    assert_equal "openai", data["provider"]
    assert_equal "gpt-4o-mini", data["model"]
    assert_includes data["available_providers"], "openai"
  end

  test "config does not expose api credentials" do
    ENV["OPENAI_API_KEY"] = "sk-test-key"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test-key"

    get "/ai/config", as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_not data.key?("openai_api_key")
    assert_not data.key?("anthropic_api_key")
    refute_includes response.body, "sk-test-key"
    refute_includes response.body, "sk-ant-test-key"
  end

  test "config returns enabled true when OpenRouter key is set" do
    ENV["OPENROUTER_API_KEY"] = "sk-or-test-key"

    get "/ai/config", as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal true, data["enabled"]
    assert_equal "openrouter", data["provider"]
    assert_equal "openai/gpt-4o-mini", data["model"]
  end

  test "config returns enabled true when Anthropic key is set" do
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test-key"

    get "/ai/config", as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal true, data["enabled"]
    assert_equal "anthropic", data["provider"]
    assert_equal "claude-sonnet-4-20250514", data["model"]
  end

  test "config returns enabled true when Gemini key is set" do
    ENV["GEMINI_API_KEY"] = "gemini-test-key"

    get "/ai/config", as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal true, data["enabled"]
    assert_equal "gemini", data["provider"]
    assert_equal "gemini-2.0-flash", data["model"]
  end

  test "config returns enabled true when Ollama base is set" do
    ENV["OLLAMA_API_BASE"] = "http://localhost:11434"

    get "/ai/config", as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal true, data["enabled"]
    assert_equal "ollama", data["provider"]
    assert_equal "llama3.2:latest", data["model"]
  end

  test "config returns correct priority with multiple providers" do
    ENV["OLLAMA_API_BASE"] = "http://localhost:11434"
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

    get "/ai/config", as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "openai", data["provider"]  # Highest priority
    assert_equal 3, data["available_providers"].size
    assert_includes data["available_providers"], "ollama"
    assert_includes data["available_providers"], "openai"
    assert_includes data["available_providers"], "anthropic"
  end

  test "config respects ai_provider override" do
    ENV["OLLAMA_API_BASE"] = "http://localhost:11434"
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["AI_PROVIDER"] = "openai"

    get "/ai/config", as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "openai", data["provider"]
  end

  test "config respects ai_model override" do
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["AI_MODEL"] = "gpt-4-turbo"

    get "/ai/config", as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "gpt-4-turbo", data["model"]
  end

  test "config returns normalized provider options and current selection" do
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"
    ENV["AI_MODEL"] = "gpt-4-turbo"

    get "/ai/config", as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal %w[openai anthropic], data["available_options"].map { |option| option["provider"] }
    assert_equal "gpt-4o-mini", data["available_options"].find { |option| option["provider"] == "openai" }["model"]
    assert_equal "claude-sonnet-4-20250514", data["available_options"].find { |option| option["provider"] == "anthropic" }["model"]
    assert_equal "openai", data["default_option"]["provider"]
    assert_equal "gpt-4-turbo", data["default_option"]["model"]
    assert_equal "openai", data["current_selection"]["provider"]
    assert_equal "gpt-4-turbo", data["current_selection"]["model"]
    assert_equal "global_override", data["current_selection"]["model_source"]
    assert_equal({ "grammar" => nil, "custom_prompt" => nil }, data["saved_selections"])
    assert_equal false, data["selection_states"]["grammar"]["invalid"]
    assert_equal false, data["selection_states"]["custom_prompt"]["invalid"]
  end

  test "config returns saved ai selections when present" do
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

    config = Config.new
    config.save_ai_feature_selection("grammar", provider: "anthropic", model: "claude-sonnet-4-20250514")
    config.save_ai_feature_selection("custom_prompt", provider: "openai", model: "gpt-4o-mini")

    get "/ai/config", as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "anthropic", data["saved_selections"]["grammar"]["provider"]
    assert_equal "claude-sonnet-4-20250514", data["saved_selections"]["grammar"]["model"]
    assert_equal "openai", data["saved_selections"]["custom_prompt"]["provider"]
    assert_equal "gpt-4o-mini", data["saved_selections"]["custom_prompt"]["model"]
  end

  test "config reports invalid saved ai selections that no longer match the available options" do
    ENV["OPENAI_API_KEY"] = "sk-test"
    notes_path = Pathname.new(ENV.fetch("NOTES_PATH"))
    notes_path.join(".fed").write(<<~CONFIG)
      ai_custom_prompt_provider = openai
      ai_custom_prompt_model = gpt-4-turbo
    CONFIG

    get "/ai/config", as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_nil data["saved_selections"]["custom_prompt"]
    assert_equal true, data["selection_states"]["custom_prompt"]["configured"]
    assert_equal true, data["selection_states"]["custom_prompt"]["invalid"]
    assert_equal "openai", data["selection_states"]["custom_prompt"]["provider"]
    assert_equal "gpt-4-turbo", data["selection_states"]["custom_prompt"]["model"]
  end

  # Fix grammar endpoint tests
  test "fix_grammar returns error when path is blank" do
    post "/ai/fix_grammar", params: { path: "" }, as: :json
    assert_response :bad_request

    data = JSON.parse(response.body)
    assert_includes data["error"], "No file path"
  end

  test "fix_grammar returns error when note not found" do
    post "/ai/fix_grammar", params: { path: "nonexistent.md" }, as: :json
    assert_response :not_found

    data = JSON.parse(response.body)
    assert_includes data["error"], "not found"
  end

  test "fix_grammar returns error when note is empty" do
    # Create an empty note
    note = Note.new(path: "empty.md", content: "")
    note.save

    post "/ai/fix_grammar", params: { path: "empty.md" }, as: :json
    assert_response :bad_request

    data = JSON.parse(response.body)
    assert_includes data["error"], "empty"
  end

  test "fix_grammar returns error when AI not configured" do
    # Create a note with content
    note = Note.new(path: "test.md", content: "Hello world")
    note.save

    post "/ai/fix_grammar", params: { path: "test.md" }, as: :json
    assert_response :unprocessable_entity

    data = JSON.parse(response.body)
    assert_includes data["error"], "not configured"
  end

  test "fix_grammar passes an explicit ai selection through to the service" do
    note = Note.new(path: "test.md", content: "Hello world")
    note.save

    AiService.expects(:fix_grammar).with(
      "Hello world",
      provider: "anthropic",
      model: "claude-sonnet-4-20250514"
    ).returns({
      corrected: "Hello, world.",
      provider: "anthropic",
      model: "claude-sonnet-4-20250514"
    })

    post "/ai/fix_grammar", params: {
      path: "test.md",
      provider: "anthropic",
      model: "claude-sonnet-4-20250514"
    }, as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "anthropic", data["provider"]
    assert_equal "claude-sonnet-4-20250514", data["model"]
  end

  test "fix_grammar returns bad request when provider selection is partial" do
    note = Note.new(path: "test.md", content: "Hello world")
    note.save

    post "/ai/fix_grammar", params: {
      path: "test.md",
      provider: "openai"
    }, as: :json
    assert_response :bad_request

    data = JSON.parse(response.body)
    assert_equal "Provider and model must be supplied together.", data["error"]
  end

  test "generate_custom allows blank selected text" do
    ENV["OPENAI_API_KEY"] = "sk-test-key"
    AiService.stubs(:generate_custom_prompt).with("", "Write an introduction").returns({
      corrected: "# Intro\n\nFresh start.",
      provider: "openai",
      model: "gpt-4o-mini"
    })

    post "/ai/generate_custom", params: { selected_text: "", prompt: "Write an introduction" }, as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "", data["original"]
    assert_equal "# Intro\n\nFresh start.", data["corrected"]
  end

  test "generate_custom returns error when prompt is blank" do
    post "/ai/generate_custom", params: { selected_text: "Hello", prompt: "" }, as: :json
    assert_response :bad_request

    data = JSON.parse(response.body)
    assert_includes data["error"], "No prompt provided"
  end

  test "generate_custom returns cleaned text on success" do
    ENV["OPENAI_API_KEY"] = "sk-test-key"
    AiService.stubs(:generate_custom_prompt).returns({
      corrected: "# Clean Heading\n\nBody paragraph.",
      provider: "openai",
      model: "gpt-4o-mini"
    })

    post "/ai/generate_custom", params: { selected_text: "Draft", prompt: "Rewrite this cleanly" }, as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "Draft", data["original"]
    assert_equal "# Clean Heading\n\nBody paragraph.", data["corrected"]
    assert_equal "openai", data["provider"]
    assert_equal "gpt-4o-mini", data["model"]
  end

  test "generate_custom passes an explicit ai selection through to the service" do
    AiService.expects(:generate_custom_prompt).with(
      "Draft",
      "Rewrite this cleanly",
      provider: "anthropic",
      model: "claude-sonnet-4-20250514"
    ).returns({
      corrected: "Cleaned by Claude.",
      provider: "anthropic",
      model: "claude-sonnet-4-20250514"
    })

    post "/ai/generate_custom", params: {
      selected_text: "Draft",
      prompt: "Rewrite this cleanly",
      provider: "anthropic",
      model: "claude-sonnet-4-20250514"
    }, as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "anthropic", data["provider"]
    assert_equal "claude-sonnet-4-20250514", data["model"]
  end

  test "generate_custom returns bad request when provider selection is partial" do
    post "/ai/generate_custom", params: {
      selected_text: "Draft",
      prompt: "Rewrite this cleanly",
      provider: "openai"
    }, as: :json
    assert_response :bad_request

    data = JSON.parse(response.body)
    assert_equal "Provider and model must be supplied together.", data["error"]
  end

  test "update_preference saves a valid feature-specific ai selection" do
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

    patch "/ai/preferences", params: {
      feature: "grammar",
      provider: "anthropic",
      model: "claude-sonnet-4-20250514"
    }, as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "grammar", data["feature"]
    assert_equal "anthropic", data["selection"]["provider"]
    assert_equal "saved_preference", data["selection"]["model_source"]
    assert_equal "anthropic", data["saved_selections"]["grammar"]["provider"]
    assert_equal false, data["selection_states"]["grammar"]["invalid"]
    assert data["message"].present?

    reloaded = Config.new
    assert_equal "anthropic", reloaded.get("ai_grammar_provider")
    assert_equal "claude-sonnet-4-20250514", reloaded.get("ai_grammar_model")
  end

  test "update_preference returns bad request when feature is missing" do
    patch "/ai/preferences", params: {
      feature: "",
      provider: "openai",
      model: "gpt-4o-mini"
    }, as: :json
    assert_response :bad_request

    data = JSON.parse(response.body)
    assert_equal "AI preference feature is required.", data["error"]
  end

  test "update_preference returns bad request when provider or model is missing" do
    patch "/ai/preferences", params: {
      feature: "grammar",
      provider: "openai",
      model: ""
    }, as: :json
    assert_response :bad_request

    data = JSON.parse(response.body)
    assert_equal "Provider and model are required.", data["error"]
  end

  test "update_preference returns unprocessable entity for unsupported features" do
    ENV["OPENAI_API_KEY"] = "sk-test"

    patch "/ai/preferences", params: {
      feature: "summaries",
      provider: "openai",
      model: "gpt-4o-mini"
    }, as: :json
    assert_response :unprocessable_entity

    data = JSON.parse(response.body)
    assert_equal "Unsupported AI feature.", data["error"]
  end

  test "update_preference returns unprocessable entity for invalid provider model pairs" do
    ENV["OPENAI_API_KEY"] = "sk-test"

    patch "/ai/preferences", params: {
      feature: "grammar",
      provider: "openai",
      model: "gpt-4-turbo"
    }, as: :json
    assert_response :unprocessable_entity

    data = JSON.parse(response.body)
    assert_equal "That AI option is no longer available.", data["error"]
  end

  # Image config endpoint tests
  test "image_config returns enabled false when no OpenRouter key" do
    get "/ai/image_config", as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal false, data["enabled"]
    assert_equal "google/gemini-3.1-flash-image-preview", data["model"]
  end

  test "image_config returns enabled true when OpenRouter key is set" do
    ENV["OPENROUTER_API_KEY"] = "sk-or-test-key"

    get "/ai/image_config", as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal true, data["enabled"]
    assert_equal "google/gemini-3.1-flash-image-preview", data["model"]
  end

  # Generate image endpoint tests
  test "generate_image returns error when prompt is blank" do
    post "/ai/generate_image", params: { prompt: "" }, as: :json
    assert_response :bad_request

    data = JSON.parse(response.body)
    assert_includes data["error"], "No prompt"
  end

  test "generate_image returns error when not configured" do
    post "/ai/generate_image", params: { prompt: "A sunset" }, as: :json
    assert_response :unprocessable_entity

    data = JSON.parse(response.body)
    assert_includes data["error"], "not configured"
  end
end
