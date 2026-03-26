# frozen_string_literal: true

class AiController < ApplicationController
  skip_forgery_protection only: [ :fix_grammar, :generate_image ]

  # GET /ai/config
  def status
    render json: AiService.provider_info
  end

  # POST /ai/fix_grammar
  def fix_grammar
    path = params[:path].to_s

    if path.blank?
      return render json: { error: t("errors.no_file_provided") }, status: :bad_request
    end

    # Read the file content from disk
    begin
      note = Note.find(path)
      text = note.content
    rescue NotesService::NotFoundError
      return render json: { error: t("errors.note_not_found") }, status: :not_found
    end

    if text.blank?
      return render json: { error: t("errors.note_is_empty") }, status: :bad_request
    end

    selection = requested_ai_selection
    return render_selection_error(selection) if selection[:error]

    result = if selection[:provider]
      AiService.fix_grammar(text, provider: selection[:provider], model: selection[:model])
    else
      AiService.fix_grammar(text)
    end

    if result[:error]
      render json: { error: result[:error] }, status: :unprocessable_entity
    else
      render json: {
        original: text,
        corrected: result[:corrected],
        provider: result[:provider],
        model: result[:model]
      }
    end
  end

  # POST /ai/generate_custom
  def generate_custom
    text = params[:selected_text].to_s
    prompt = params[:prompt].to_s

    if prompt.blank?
      return render json: { error: t("errors.no_prompt_provided") }, status: :bad_request
    end

    selection = requested_ai_selection
    return render_selection_error(selection) if selection[:error]

    result = if selection[:provider]
      AiService.generate_custom_prompt(text, prompt, provider: selection[:provider], model: selection[:model])
    else
      AiService.generate_custom_prompt(text, prompt)
    end

    if result[:error]
      render json: { error: result[:error] }, status: :unprocessable_entity
    else
      render json: {
        original: text,
        corrected: result[:corrected],
        provider: result[:provider],
        model: result[:model]
      }
    end
  end

  # PATCH /ai/preferences
  def update_preference
    feature = params[:feature].to_s.strip
    provider = params[:provider].to_s.strip
    model = params[:model].to_s.strip

    if feature.blank?
      return render json: { error: "AI preference feature is required." }, status: :bad_request
    end

    if provider.blank? || model.blank?
      return render json: { error: "Provider and model are required." }, status: :bad_request
    end

    result = AiService.save_selection(feature:, provider:, model:)

    if result[:error]
      render json: { error: result[:error] }, status: :unprocessable_entity
    else
      render json: {
        feature: feature,
        selection: result[:selection],
        saved_selections: result[:saved_selections],
        selection_states: result[:selection_states],
        message: t("success.settings_saved")
      }
    end
  end

  # GET /ai/image_config
  def image_config
    render json: AiService.image_generation_info
  end

  # POST /ai/generate_image
  def generate_image
    prompt = params[:prompt].to_s
    reference_image_path = params[:reference_image_path].to_s.presence

    if prompt.blank?
      return render json: { error: t("errors.no_prompt_provided") }, status: :bad_request
    end

    result = AiService.generate_image(prompt, reference_image_path: reference_image_path)

    if result[:error]
      render json: { error: result[:error] }, status: :unprocessable_entity
    else
      render json: result
    end
  end

  private

  def requested_ai_selection
    provider = params[:provider].to_s.strip
    model = params[:model].to_s.strip

    return {} if provider.blank? && model.blank?
    return { error: "Provider and model must be supplied together." } if provider.blank? || model.blank?

    { provider: provider, model: model }
  end

  def render_selection_error(selection)
    render json: { error: selection[:error] }, status: :bad_request
  end
end
