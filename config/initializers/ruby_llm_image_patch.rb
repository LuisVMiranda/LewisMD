# frozen_string_literal: true

# Monkey-patches for RubyLLM's OpenRouter provider to support image generation.
#
# 1. Response parser: OpenRouter returns generated images in a `message.images`
#    array (separate from `message.content`). The stock parser drops them.
#    This patch wraps them into RubyLLM::Content with Attachment objects.
#
# 2. Model registry: OpenRouter adds new models faster than RubyLLM gem releases.
#    We register missing image models so `RubyLLM.chat(model: ...)` can find them.

module RubyLLM
  module Providers
    class OpenRouter
      module ImageChatPatch
        def parse_completion_response(response)
          message = super
          return message unless message

          images = response.body.dig("choices", 0, "message", "images")
          return message if images.nil? || images.empty?

          text = case message.content
          when String then message.content
          when RubyLLM::Content then message.content.text
          end

          content = RubyLLM::Content.new(text.presence || "Image generated")

          images.each do |img|
            url = img.dig("image_url", "url") || img["url"]
            next if url.nil?

            if url.start_with?("data:")
              match = url.match(/\Adata:([^;]+);base64,(.+)\z/m)
              next unless match

              io = StringIO.new(Base64.decode64(match[2]))
              io.set_encoding(Encoding::BINARY)
              ext = match[1].split("/").last
              content.add_attachment(io, filename: "generated_image.#{ext}")
            else
              content.add_attachment(url, filename: "generated_image.png")
            end
          end

          message.content = content
          message
        end
      end

      prepend ImageChatPatch
    end
  end
end

# Register OpenRouter image models missing from RubyLLM's bundled registry.
# This runs after RubyLLM loads its models.json — we only add models that
# aren't already known, so it's safe across gem upgrades.
Rails.application.config.after_initialize do
  missing_image_models = [
    {
      id: "google/gemini-3.1-flash-image-preview",
      name: "Google: Gemini 3.1 Flash Image Preview",
      provider: "openrouter",
      family: "google",
      context_window: 65_536,
      max_output_tokens: 32_768,
      modalities: { input: %w[image text], output: %w[image text] },
      capabilities: %w[streaming structured_output],
      pricing: {
        text_tokens: {
          standard: {
            input_per_million: 0.5,
            output_per_million: 3.0
          }
        }
      },
      metadata: {}
    }
  ]

  registry = RubyLLM::Models.instance
  missing_image_models.each do |model_data|
    existing = registry.all.find { |m| m.id == model_data[:id] && m.provider == model_data[:provider] }
    next if existing

    registry.all << RubyLLM::Model::Info.new(model_data)
    Rails.logger.info("[RubyLLM] Registered missing model: #{model_data[:id]}")
  end
end
