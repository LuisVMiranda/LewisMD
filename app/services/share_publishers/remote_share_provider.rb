# frozen_string_literal: true

require "nokogiri"

module SharePublishers
  class RemoteShareProvider
    def initialize(base_path: nil, config: nil, registry: nil, client: nil)
      @base_path = base_path
      @config = config || Config.new(base_path: base_path)
      @registry = registry || RemoteShareRegistryService.new(base_path: resolved_base_path)
      @client = client || RemoteShareClient.new(config: @config)
    end

    def create_or_find(path:, title:, snapshot_html:, share_payload: nil)
      _ = snapshot_html
      existing_share = active_share_for(path)
      return existing_share.merge(created: false) if existing_share

      payload = normalize_share_payload(path:, title:, share_payload:)
      remote_share = client.create_share(remote_request_payload(payload))
      metadata = persist_remote_share(payload:, remote_share:)

      metadata.merge(created: true)
    rescue RemoteShareClient::Error => e
      raise ShareService::InvalidShareError, e.message
    end

    def refresh(path:, title:, snapshot_html:, share_payload: nil)
      _ = snapshot_html
      existing_share = registry.active_share_for(path)
      raise ShareService::NotFoundError, "Share not found for #{path}" unless existing_share

      payload = normalize_share_payload(path:, title:, share_payload:)
      remote_share = client.update_share(
        token: existing_share[:token],
        payload: remote_request_payload(payload)
      )

      persist_remote_share(
        payload: payload,
        remote_share: remote_share,
        existing_share: existing_share
      )
    rescue RemoteShareClient::Error => e
      registry.mark_stale(path: path, error: e.message) if existing_share
      raise ShareService::InvalidShareError, e.message
    end

    def revoke(path:)
      existing_share = registry.active_share_for(path)
      raise ShareService::NotFoundError, "Share not found for #{path}" unless existing_share

      client.revoke_share(token: existing_share[:token])
      registry.delete(path:)

      existing_share
    rescue RemoteShareClient::Error => e
      raise ShareService::InvalidShareError, e.message
    end

    def find_by_token(...)
      nil
    end

    def active_share_for(path, require_snapshot: true)
      _ = require_snapshot
      registry.active_share_for(path)
    rescue ShareService::InvalidShareError
      nil
    end

    private

    attr_reader :config, :registry, :client

    def resolved_base_path
      config.base_path
    end

    def normalize_share_payload(path:, title:, share_payload:)
      payload = share_payload&.deep_symbolize_keys || {}
      raise ShareService::InvalidShareError, "Remote share payload is missing" if payload.blank?

      payload.merge(
        path: path,
        note_identifier: payload[:note_identifier].presence || path,
        title: title,
        expires_at: payload[:expires_at].presence || requested_expires_at
      )
    end

    def remote_request_payload(payload)
      assets = upload_assets_enabled? ? Array(payload[:assets]) : []
      upload_references = upload_references_for(assets)

      {
        snapshot_version: payload[:snapshot_version],
        shell_version: payload[:shell_version],
        source: payload[:source],
        note_identifier: payload[:note_identifier],
        path: payload[:path],
        title: payload[:title],
        html_fragment: rewrite_images_for_remote(payload[:html_fragment], upload_references, fragment: true),
        snapshot_document_html: rewrite_images_for_remote(payload[:snapshot_document_html], upload_references),
        shell_payload: payload[:shell_payload],
        plain_text: payload[:plain_text],
        theme_id: payload[:theme_id],
        locale: payload[:locale],
        content_hash: payload[:content_hash],
        asset_manifest: payload[:asset_manifest],
        assets: assets,
        expires_at: payload[:expires_at],
        instance_name: config.get("share_remote_instance_name")
      }.compact
    end

    def persist_remote_share(payload:, remote_share:, existing_share: nil)
      timestamp = Time.current.iso8601
      metadata = registry.save(
        {
          token: remote_share[:token],
          path: payload[:path],
          title: remote_share[:title].presence || payload[:title],
          url: remote_share[:url],
          created_at: existing_share&.dig(:created_at) || remote_share[:created_at].presence || timestamp,
          updated_at: remote_share[:updated_at].presence || timestamp,
          stale: false,
          last_error: nil,
          last_synced_at: timestamp,
          content_hash: payload[:content_hash],
          locale: payload[:locale],
          theme_id: payload[:theme_id],
          asset_manifest: payload[:asset_manifest],
          expires_at: remote_share[:expires_at].presence || payload[:expires_at],
          capabilities: client.last_capabilities || {}
        }
      )

      metadata
    end

    def rewrite_images_for_remote(html, upload_references, fragment: false)
      return html if html.blank?
      return html if upload_references.blank?

      document = fragment ? Nokogiri::HTML::DocumentFragment.parse(html.to_s) : Nokogiri::HTML.parse(html.to_s)
      document.css("img").each do |image|
        upload_reference = upload_references[image["src"].to_s.strip]
        image["src"] = "asset://#{upload_reference}" if upload_reference.present?
      end

      document.to_html
    end

    def upload_assets_enabled?
      config.get("share_remote_upload_assets") != false
    end

    def upload_references_for(assets)
      assets.each_with_object({}) do |asset, references|
        references[asset[:source_url]] = asset[:upload_reference] if asset[:upload_reference].present?
      end
    end

    def requested_expires_at
      expiration_days = config.get("share_remote_expiration_days").to_i
      return nil unless expiration_days.positive?

      expiration_days.days.from_now.iso8601
    end
  end
end
