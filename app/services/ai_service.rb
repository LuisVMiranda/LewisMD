# frozen_string_literal: true

require "ruby_llm"

class AiService
  GRAMMAR_PROMPT = <<~PROMPT
    You are a grammar and spelling corrector. Fix ONLY:
    - Grammar errors
    - Spelling mistakes
    - Typos
    - Punctuation errors

    DO NOT change:
    - Facts, opinions, or meaning
    - Writing style or tone
    - Markdown formatting (headers, links, code blocks, lists, etc.)
    - Technical terms or proper nouns
    - Code blocks or inline code

    Return ONLY the corrected text with no explanations or commentary.
  PROMPT

  CUSTOM_PROMPT_INSTRUCTIONS = <<~PROMPT
    You are a writing assistant transforming note content according to the user's instructions.

    Apply the user's instructions to the provided text.

    Rules:
    - Return ONLY the transformed text.
    - Do not add introductions, commentary, labels, summaries, or calls to action.
    - Do not wrap the output in code fences unless the user explicitly requests code fences.
    - Preserve markdown structure, frontmatter, links, lists, tables, inline code, and code blocks unless the user explicitly asks to change them.
    - Keep the result ready to paste directly into a markdown note.
  PROMPT

  class << self
    def enabled?
      config_instance.feature_available?("ai")
    end

    def available_providers
      config_instance.ai_providers_available
    end

    def current_provider
      config_instance.effective_ai_provider
    end

    def current_model
      config_instance.effective_ai_model
    end

    def available_options
      config_instance.ai_provider_options
    end

    def current_selection
      config_instance.effective_ai_option
    end

    def saved_selection(feature)
      config_instance.ai_feature_selection(feature)
    end

    def saved_selections
      config_instance.ai_saved_selections
    end

    def selection_states
      config_instance.ai_saved_selection_states
    end

    def save_selection(feature:, provider:, model:)
      cfg = config_instance
      return { error: "Unsupported AI feature." } unless cfg.ai_feature_selection_supported?(feature)

      selection = cfg.save_ai_feature_selection(feature, provider: provider, model: model)
      return { error: "We couldn't save your AI choice right now." } if selection == false
      return { error: "That AI option is no longer available." } unless selection

      {
        selection: selection,
        saved_selections: cfg.ai_saved_selections,
        selection_states: cfg.ai_saved_selection_states
      }
    rescue StandardError => e
      Rails.logger.error "AI preference save error (#{feature}): #{e.class} - #{sanitize_ai_error_text(e.message)}"
      { error: "We couldn't save your AI choice right now." }
    end

    def fix_grammar(text, provider: nil, model: nil)
      return { error: "AI not configured" } unless enabled?
      return { error: "No text provided" } if text.blank?

      selection = resolve_text_selection(provider: provider, model: model)
      return { error: selection[:error] } if selection[:error]

      provider = selection["provider"]
      model = selection["model"]
      return { error: "No AI provider available" } unless provider && model

      log_text_request(feature: "grammar", provider:, model:, selection:)

      configure_client(provider:)
      chat = RubyLLM.chat(model: model, provider: provider.to_sym, assume_model_exists: provider == "ollama")
      chat.with_instructions(GRAMMAR_PROMPT)
      response = chat.ask(text)

      { corrected: response.content, provider: provider, model: model }
    rescue StandardError => e
      safe_error = build_processing_error_message(e)
      Rails.logger.error "AI error (#{provider}/#{model}): #{e.class} - #{safe_error}"
      { error: safe_error }
    end

    def generate_custom_prompt(text, prompt, provider: nil, model: nil)
      return { error: "AI not configured" } unless enabled?
      return { error: "No prompt provided" } if prompt.blank?

      selection = resolve_text_selection(provider: provider, model: model)
      return { error: selection[:error] } if selection[:error]

      provider = selection["provider"]
      model = selection["model"]
      return { error: "No AI provider available" } unless provider && model

      log_text_request(feature: "custom_prompt", provider:, model:, selection:)

      configure_client(provider:)
      chat = RubyLLM.chat(model: model, provider: provider.to_sym, assume_model_exists: provider == "ollama")
      chat.with_instructions(build_custom_prompt_instructions(prompt))
      response = chat.ask(build_custom_prompt_input(text))

      { corrected: clean_custom_prompt_output(response.content), provider: provider, model: model }
    rescue StandardError => e
      safe_error = build_processing_error_message(e)
      Rails.logger.error "AI custom error (#{provider}/#{model}): #{e.class} - #{safe_error}"
      { error: safe_error }
    end

    # Get provider info for frontend display
    def provider_info
      {
        enabled: enabled?,
        provider: current_provider,
        model: current_model,
        available_providers: available_providers,
        available_options: available_options,
        default_option: current_selection,
        current_selection: current_selection,
        saved_selections: saved_selections,
        selection_states: selection_states
      }
    end

    # === Image Generation ===

    def image_generation_enabled?
      # Image generation uses RubyLLM + OpenRouter (Gemini model)
      # Check both .fed and ENV since image generation is independent of text provider choice
      openrouter_key_for_images.present?
    end

    def image_generation_model
      config_instance.get("image_generation_model") || "google/gemini-3.1-flash-image-preview"
    end

    # Get OpenRouter key specifically for image generation
    # Unlike text processing, we always want to check ENV as fallback
    # since image generation is independent of text provider configuration
    def openrouter_key_for_images
      cfg = config_instance
      # First check .fed, then ENV (bypasses get_ai which ignores ENV when any AI key is in .fed)
      cfg.instance_variable_get(:@values)&.dig("openrouter_api_key") ||
        ENV["OPENROUTER_API_KEY"]
    end

    def image_generation_info
      {
        enabled: image_generation_enabled?,
        model: image_generation_model
      }
    end

    def generate_image(prompt, reference_image_path: nil)
      return { error: "Image generation not configured. Requires OpenRouter API key." } unless image_generation_enabled?
      return { error: "No prompt provided" } if prompt.blank?

      model = image_generation_model

      # Resolve reference image if provided
      reference_image_path_full = nil
      if reference_image_path.present?
        reference_image_path_full = ImagesService.find_image(reference_image_path)
        unless reference_image_path_full&.exist?
          Rails.logger.warn "Reference image not found: #{reference_image_path}"
          reference_image_path_full = nil
        end
      end

      Rails.logger.info "Image generation: model=#{model}, prompt_length=#{prompt.length}, reference=#{reference_image_path_full.present?}"

      configure_image_client
      chat = RubyLLM.chat(model: model, provider: :openrouter)
      chat.with_params(modalities: %w[text image])

      content = build_image_content(prompt, reference_image_path_full)
      response = chat.ask(content)

      extract_image_from_response(response, model)
    rescue StandardError => e
      Rails.logger.error "Image generation error: #{e.class} - #{e.message}"
      { error: "Image generation failed: #{e.message}" }
    end

    def extract_image_from_response(response, model)
      content = response.content

      if content.is_a?(RubyLLM::Content) && content.attachments.any?
        attachment = content.attachments.first
        {
          data: Base64.strict_encode64(attachment.content),
          mime_type: attachment.mime_type || "image/png",
          model: model,
          revised_prompt: nil
        }
      else
        text = content.is_a?(RubyLLM::Content) ? content.text : content.to_s
        if text.present?
          Rails.logger.warn "Image model returned text instead of image: #{text.truncate(200)}"
        end
        { error: "No image data in response" }
      end
    end

    private

    def log_text_request(feature:, provider:, model:, selection:)
      selection_source = selection["model_source"] || "default"
      Rails.logger.info(
        "AI request: feature=#{feature} provider=#{provider} model=#{model} selection_source=#{selection_source}"
      )
    end

    def build_processing_error_message(error)
      safe_message = sanitize_ai_error_text(error.message)
      return "AI processing failed. Please try again." if safe_message.blank?

      "AI processing failed: #{safe_message}"
    end

    def sanitize_ai_error_text(message)
      sanitized = message.to_s.gsub(/\s+/, " ").strip
      return nil if sanitized.blank?

      sensitive_ai_values.each do |value|
        sanitized = sanitized.gsub(value, "[redacted]") if value.present?
      end

      sanitized.truncate(200)
    end

    def sensitive_ai_values
      cfg = config_instance

      %w[openai_api_key openrouter_api_key anthropic_api_key gemini_api_key].filter_map do |key|
        cfg.get_ai(key).presence
      end.uniq.sort_by { |value| -value.length }
    end

    def build_image_content(prompt, reference_image_path)
      return prompt unless reference_image_path

      content = RubyLLM::Content.new(prompt)
      content.add_attachment(reference_image_path.to_s)
      content
    end

    def configure_image_client
      RubyLLM.configure do |config|
        # Clear all keys first
        config.openai_api_key = nil
        config.openrouter_api_key = nil
        config.anthropic_api_key = nil
        config.gemini_api_key = nil
        config.ollama_api_base = nil

        # Image generation uses OpenRouter
        config.openrouter_api_key = openrouter_key_for_images
      end
    end

    def resolve_text_selection(provider:, model:)
      provider = provider.to_s.strip
      model = model.to_s.strip

      if provider.blank? && model.blank?
        selection = current_selection
        return { error: "No AI provider available" } unless selection

        return selection
      end

      if provider.blank? || model.blank?
        return { error: "Provider and model must be supplied together." }
      end

      selection = available_options.find do |option|
        option["provider"] == provider && option["model"] == model
      end
      return { error: "That AI option is no longer available." } unless selection

      selection.merge(
        "model_source" => "request_override",
        "selected" => true
      )
    end

    def configure_client(provider:)
      cfg = config_instance

      RubyLLM.configure do |config|
        # Clear ALL provider keys first to avoid cross-contamination
        # RubyLLM.configure is additive, so previous keys may persist
        config.openai_api_key = nil
        config.openrouter_api_key = nil
        config.anthropic_api_key = nil
        config.gemini_api_key = nil
        config.ollama_api_base = nil

        # Now set ONLY the specific provider we're using
        # Use get_ai to respect .fed override of ENV vars
        case provider
        when "ollama"
          config.ollama_api_base = cfg.get_ai("ollama_api_base")
        when "openrouter"
          config.openrouter_api_key = cfg.get_ai("openrouter_api_key")
        when "anthropic"
          config.anthropic_api_key = cfg.get_ai("anthropic_api_key")
        when "gemini"
          config.gemini_api_key = cfg.get_ai("gemini_api_key")
        when "openai"
          config.openai_api_key = cfg.get_ai("openai_api_key")
        end
      end
    end

    def build_custom_prompt_instructions(prompt)
      <<~PROMPT
        #{CUSTOM_PROMPT_INSTRUCTIONS}

        User instructions:
        #{prompt.to_s.strip}
      PROMPT
    end

    def build_custom_prompt_input(text)
      normalized = normalize_ai_text(text)
      return normalized if normalized.present?

      <<~TEXT.strip
        The current note is empty.

        Generate the requested note content from the user's instructions alone.
      TEXT
    end

    def clean_custom_prompt_output(content)
      normalized = normalize_ai_text(content)
      unwrapped = unwrap_wrapping_code_fence(normalized)
      paragraphs = unwrapped.split(/\n{2,}/)

      paragraphs.shift while paragraphs.length > 1 && introductory_ai_paragraph?(paragraphs.first)
      paragraphs.pop while paragraphs.length > 1 && closing_ai_paragraph?(paragraphs.last)

      cleaned = unwrap_wrapping_code_fence(paragraphs.join("\n\n").strip).strip
      cleaned.presence || unwrapped
    end

    def normalize_ai_text(content)
      content.to_s.gsub(/\r\n?/, "\n").strip
    end

    def unwrap_wrapping_code_fence(text)
      match = text.match(/\A```(?:markdown|md|text|txt)?\s*\n(?<body>[\s\S]*?)\n```\s*\z/i)
      match ? match[:body].to_s.strip : text
    end

    def introductory_ai_paragraph?(paragraph)
      normalized = paragraph.to_s.strip
      return false if normalized.blank? || normalized.length > 180

      normalized.match?(
        /\A(?:(?:sure|absolutely|certainly|of course)[!.\s]*)?(?:here(?:'s| is)|below is|i(?:'ve| have)\s+(?:rewritten|revised|updated|polished|translated)|(?:revised|updated|corrected|polished|rewritten|translated)\s+(?:version|text|note)|translation|result)\b/i
      )
    end

    def closing_ai_paragraph?(paragraph)
      normalized = paragraph.to_s.strip
      return false if normalized.blank? || normalized.length > 220

      normalized.match?(/\A(?:let me know|if you'd like|if you want|feel free to|happy to|i can also|i can help)\b/i)
    end

    def config_instance
      # Don't cache - config may change
      Config.new
    end
  end
end
