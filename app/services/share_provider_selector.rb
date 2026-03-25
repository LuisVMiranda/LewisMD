# frozen_string_literal: true

class ShareProviderSelector
  BACKENDS = {
    "local" => "SharePublishers::LocalShareProvider",
    "remote" => "SharePublishers::RemoteShareProvider"
  }.freeze

  def initialize(base_path: nil, config: nil)
    @base_path = base_path
    @config = config || Config.new(base_path: base_path)
  end

  def provider
    provider_class.new(base_path: resolved_base_path, config: config)
  end

  def backend
    configured_backend = config.get("share_backend").to_s.strip.downcase
    return "local" if configured_backend.blank?
    return configured_backend if BACKENDS.key?(configured_backend)

    Rails.logger.warn("Unknown share_backend '#{configured_backend}', falling back to local")
    "local"
  end

  private

  attr_reader :base_path, :config

  def provider_class
    BACKENDS.fetch(backend).constantize
  end

  def resolved_base_path
    config.base_path
  end
end
