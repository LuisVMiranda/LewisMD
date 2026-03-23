# frozen_string_literal: true

class TranslationsController < ApplicationController
  # GET /translations
  # Returns translations for JavaScript use
  def show
    locale = requested_locale || I18n.locale
    js_keys = %w[common dialogs status status_strip errors success editor sidebar preview context_menu connection export_menu header share_view]
    translations = js_keys.each_with_object({}) do |key, hash|
      hash[key] = I18n.t(key, locale: locale, default: {})
    end
    render json: { locale: locale.to_s, translations: translations }
  end

  private

  def requested_locale
    locale = params[:locale].presence&.to_s&.to_sym
    return nil unless locale && I18n.available_locales.include?(locale)

    locale
  end
end
