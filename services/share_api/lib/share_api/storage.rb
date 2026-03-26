# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "pathname"
require "securerandom"
require "set"
require "tempfile"
require "time"
require "base64"
require "nokogiri"

module ShareAPI
  class Storage
    class NotFoundError < StandardError; end
    class ValidationError < StandardError; end

    SHARES_DIR = "shares"
    PATH_INDEX_DIR = "path-index"
    SNAPSHOTS_DIR = "snapshots"
    ASSETS_DIR = "assets"
    NONCES_DIR = "nonces"
    MAINTENANCE_DIR = "maintenance"
    TOKEN_PATTERN = /\A[a-zA-Z0-9\-_]{8,}\z/
    ALLOWED_ASSET_MIME_TYPES = %w[
      image/avif
      image/gif
      image/jpeg
      image/jpg
      image/png
      image/webp
    ].freeze

    def initialize(storage_path:, max_asset_bytes:, max_asset_count:)
      @storage_path = Pathname.new(storage_path).expand_path
      @max_asset_bytes = max_asset_bytes
      @max_asset_count = max_asset_count
      FileUtils.mkdir_p(storage_root)
    end

    def upsert_share(identity_key:, share:, fragment_html:, snapshot_document_html: nil, assets: [])
      validate_identity_key!(identity_key)
      share = normalize_share(share)
      validate_share!(share)
      prepared_assets = prepare_assets(assets)

      existing_share = find_share_by_identity(identity_key)
      timestamp = Time.now.utc.iso8601
      token = existing_share&.fetch("token", nil) || generate_token
      resolved_fragment_html = resolve_fragment_assets(
        token: token,
        fragment_html: fragment_html,
        prepared_assets: prepared_assets
      )
      resolved_snapshot_document_html = resolve_snapshot_document_assets(
        token: token,
        snapshot_document_html: snapshot_document_html,
        prepared_assets: prepared_assets
      )

      persisted_share = share.merge(
        "token" => token,
        "identity_key" => identity_key,
        "created_at" => existing_share&.fetch("created_at", nil) || timestamp,
        "updated_at" => timestamp,
        "asset_manifest" => resolved_asset_manifest(share["asset_manifest"], token, prepared_assets)
      )

      promote_assets(token: token, prepared_assets: prepared_assets)
      write_fragment(token, resolved_fragment_html)
      write_snapshot_document(token, resolved_snapshot_document_html)
      write_share_metadata(persisted_share)
      write_identity_index(identity_key, token)
      cleanup_orphan_assets(token: token, keep_names: prepared_assets.map { |asset| asset[:stored_name] })

      [ existing_share.nil?, persisted_share ]
    end

    def update_share(token:, share:, fragment_html:, snapshot_document_html: nil, assets: [])
      validate_token!(token)
      share = normalize_share(share)
      existing_share = fetch_share(token)
      prepared_assets = prepare_assets(assets)
      resolved_fragment_html = resolve_fragment_assets(
        token: token,
        fragment_html: fragment_html,
        prepared_assets: prepared_assets
      )
      resolved_snapshot_document_html = resolve_snapshot_document_assets(
        token: token,
        snapshot_document_html: snapshot_document_html,
        prepared_assets: prepared_assets
      )

      persisted_share = existing_share.merge(share).merge(
        "token" => token,
        "updated_at" => Time.now.utc.iso8601,
        "asset_manifest" => resolved_asset_manifest(share["asset_manifest"], token, prepared_assets)
      )

      promote_assets(token: token, prepared_assets: prepared_assets)
      write_fragment(token, resolved_fragment_html)
      write_snapshot_document(token, resolved_snapshot_document_html)
      write_share_metadata(persisted_share)
      write_identity_index(existing_share.fetch("identity_key"), token)
      cleanup_orphan_assets(token: token, keep_names: prepared_assets.map { |asset| asset[:stored_name] })

      persisted_share
    end

    def fetch_share(token, allow_expired: false)
      validate_token!(token)
      file = share_file(token)
      raise NotFoundError unless file.file?

      share = JSON.parse(file.read)
      if !allow_expired && expired_share?(share)
        purge_share(share)
        raise NotFoundError
      end

      share
    rescue JSON::ParserError
      raise NotFoundError
    end

    def find_share_by_identity(identity_key, allow_expired: false)
      validate_identity_key!(identity_key)
      file = identity_index_file(identity_key)
      return nil unless file.file?

      payload = JSON.parse(file.read)
      fetch_share(payload.fetch("token"), allow_expired: allow_expired)
    rescue JSON::ParserError, KeyError, NotFoundError
      file.delete if file&.file?
      nil
    end

    def read_fragment(token)
      validate_token!(token)
      file = fragment_file(token)
      raise NotFoundError unless file.file?

      file.read
    end

    def read_snapshot_document(token)
      validate_token!(token)
      file = snapshot_document_file(token)
      raise NotFoundError unless file.file?

      file.read
    end

    def delete_share(token:)
      share = fetch_share(token, allow_expired: true)
      purge_share(share)
      share
    end

    def sweep_expired_shares!(now: Time.now.utc)
      removed_tokens = []

      Dir.glob(shares_dir.join("*.json")).sort.each do |share_path|
        file = Pathname.new(share_path)
        share = JSON.parse(file.read)
        next unless expired_share?(share, now: now)

        removed_tokens << share.fetch("token")
        purge_share(share)
      rescue JSON::ParserError, KeyError
        file.delete if file.file?
      end

      prune_orphan_identity_indexes!
      removed_tokens
    end

    def asset_path(token:, asset_name:)
      validate_token!(token)
      asset_dir(token).join(File.basename(asset_name.to_s))
    end

    def nonce_seen?(request_id:)
      nonce_file(request_id).file?
    end

    def remember_nonce!(request_id:, timestamp:)
      write_json(
        nonce_file(request_id),
        {
          request_id: request_id,
          timestamp: timestamp
        }
      )
    end

    def prune_nonces!(before:)
      Dir.glob(nonces_dir.join("*.json")).each do |file_path|
        file = Pathname.new(file_path)
        payload = JSON.parse(file.read)
        file.delete if payload["timestamp"].to_i < before.to_i
      rescue JSON::ParserError
        file.delete
      end
    end

    def write_sweeper_report!(checked_at:, status:, removed_tokens:, error: nil)
      payload = {
        checked_at: checked_at,
        status: status,
        removed_count: Array(removed_tokens).length,
        removed_tokens: Array(removed_tokens)
      }
      payload[:error] = error.to_s unless error.to_s.strip.empty?

      write_json(sweeper_report_file, payload)
    end

    def verify_write_access!
      marker_path = maintenance_dir.join(".write-check-#{SecureRandom.hex(8)}")
      FileUtils.mkdir_p(marker_path.dirname)
      atomic_write(marker_path, "ok\n")
      marker_path.delete if marker_path.file?

      true
    rescue SystemCallError => e
      raise ValidationError, "Share storage is not writable at #{storage_root}: #{e.message}"
    end

    private

    attr_reader :storage_path, :max_asset_bytes, :max_asset_count

    def storage_root
      @storage_root ||= storage_path
    end

    def shares_dir
      @shares_dir ||= storage_root.join(SHARES_DIR)
    end

    def path_index_dir
      @path_index_dir ||= storage_root.join(PATH_INDEX_DIR)
    end

    def snapshots_dir
      @snapshots_dir ||= storage_root.join(SNAPSHOTS_DIR)
    end

    def assets_dir
      @assets_dir ||= storage_root.join(ASSETS_DIR)
    end

    def nonces_dir
      @nonces_dir ||= storage_root.join(NONCES_DIR)
    end

    def maintenance_dir
      @maintenance_dir ||= storage_root.join(MAINTENANCE_DIR)
    end

    def share_file(token)
      shares_dir.join("#{token}.json")
    end

    def fragment_file(token)
      snapshot_dir(token).join("index.html")
    end

    def snapshot_document_file(token)
      snapshot_dir(token).join("document.html")
    end

    def asset_dir(token)
      assets_dir.join(token)
    end

    def snapshot_dir(token)
      snapshots_dir.join(token)
    end

    def identity_index_file(identity_key)
      path_index_dir.join("#{Digest::SHA256.hexdigest(identity_key)}.json")
    end

    def nonce_file(request_id)
      nonces_dir.join("#{Digest::SHA256.hexdigest(request_id)}.json")
    end

    def sweeper_report_file
      maintenance_dir.join("sweeper-state.json")
    end

    def write_share_metadata(share)
      write_json(share_file(share.fetch("token")), share)
    end

    def write_identity_index(identity_key, token)
      write_json(identity_index_file(identity_key), { identity_key: identity_key, token: token })
    end

    def write_fragment(token, fragment_html)
      path = fragment_file(token)
      FileUtils.mkdir_p(path.dirname)
      atomic_write(path, fragment_html)
    end

    def write_snapshot_document(token, snapshot_document_html)
      return if snapshot_document_html.to_s.strip.empty?

      path = snapshot_document_file(token)
      FileUtils.mkdir_p(path.dirname)
      atomic_write(path, snapshot_document_html)
    end

    def write_json(path, payload)
      FileUtils.mkdir_p(path.dirname)
      atomic_write(path, JSON.pretty_generate(payload))
    end

    def atomic_write(path, content)
      tempfile = Tempfile.new([ path.basename.to_s, ".tmp" ], path.dirname.to_s)
      tempfile.binmode
      tempfile.write(content)
      tempfile.flush
      tempfile.fsync

      temp_path = tempfile.path
      tempfile.close
      FileUtils.mv(temp_path, path.to_s, force: true)
    ensure
      tempfile&.close!
    end

    def generate_token
      loop do
        token = SecureRandom.urlsafe_base64(18).delete("=")
        next unless token.match?(TOKEN_PATTERN)
        return token unless share_file(token).exist?
      end
    end

    def validate_token!(token)
      raise NotFoundError unless token.to_s.match?(TOKEN_PATTERN)
    end

    def validate_identity_key!(identity_key)
      raise ValidationError, "identity key is required" if identity_key.to_s.strip.empty?
    end

    def validate_share!(share)
      raise ValidationError, "title is required" if share["title"].to_s.strip.empty?
      raise ValidationError, "path is required" if share["path"].to_s.strip.empty?
      raise ValidationError, "content_hash is required" if share["content_hash"].to_s.strip.empty?
    end

    def normalize_share(share)
      normalized_share = share.dup
      normalized_share["expires_at"] = normalized_timestamp_or_nil(normalized_share["expires_at"])
      normalized_share
    end

    def normalized_timestamp_or_nil(value)
      return nil if value.to_s.strip.empty?

      Time.iso8601(value.to_s).utc.iso8601
    rescue ArgumentError
      raise ValidationError, "expires_at must be an ISO8601 timestamp"
    end

    def prepare_assets(assets)
      assets = Array(assets)
      raise ValidationError, "Asset count exceeds the configured maximum" if assets.length > max_asset_count

      assets.map do |asset|
        validate_asset_payload!(asset)
        bytes = decode_asset_bytes(asset)
        validate_asset_bytes!(asset, bytes)

        safe_filename = sanitize_filename(asset.fetch("filename"))
        stored_name = "#{asset.fetch("sha256")}-#{safe_filename}"
        {
          upload_reference: asset.fetch("upload_reference"),
          stored_name: stored_name,
          filename: safe_filename,
          mime_type: asset.fetch("mime_type"),
          byte_size: bytes.bytesize,
          sha256: asset.fetch("sha256"),
          bytes: bytes
        }
      end
    end

    def validate_asset_payload!(asset)
      raise ValidationError, "Each asset must be a JSON object" unless asset.is_a?(Hash)

      %w[upload_reference filename mime_type byte_size sha256 content_base64].each do |key|
        raise ValidationError, "Asset #{key} is required" if asset[key].to_s.strip.empty?
      end

      unless ALLOWED_ASSET_MIME_TYPES.include?(asset["mime_type"].to_s)
        raise ValidationError, "Asset type #{asset["mime_type"]} is not allowed"
      end
    end

    def decode_asset_bytes(asset)
      Base64.strict_decode64(asset.fetch("content_base64"))
    rescue ArgumentError
      raise ValidationError, "Asset #{asset["filename"]} did not contain valid base64 data"
    end

    def validate_asset_bytes!(asset, bytes)
      raise ValidationError, "Asset #{asset["filename"]} exceeds the configured size limit" if bytes.bytesize > max_asset_bytes
      raise ValidationError, "Asset #{asset["filename"]} size metadata did not match the uploaded bytes" if asset.fetch("byte_size").to_i != bytes.bytesize
      raise ValidationError, "Asset #{asset["filename"]} checksum did not match the uploaded bytes" if asset.fetch("sha256") != Digest::SHA256.hexdigest(bytes)
    end

    def sanitize_filename(filename)
      sanitized = File.basename(filename.to_s).gsub(/[^a-zA-Z0-9._-]/, "_")
      raise ValidationError, "Asset filename is invalid" if sanitized.empty? || sanitized == "." || sanitized == ".."

      sanitized
    end

    def resolve_fragment_assets(token:, fragment_html:, prepared_assets:)
      replacements = prepared_assets.each_with_object({}) do |asset, map|
        map[asset[:upload_reference]] = "/assets/#{token}/#{asset[:stored_name]}"
      end
      return fragment_html if replacements.empty?

      fragment = Nokogiri::HTML::DocumentFragment.parse(fragment_html.to_s)
      fragment.css("img").each do |image|
        src = image["src"].to_s.strip
        upload_reference =
          if src.start_with?("asset://")
            src.delete_prefix("asset://")
          elsif src.start_with?(ShareAPI::ASSET_PLACEHOLDER_PREFIX)
            src.delete_prefix(ShareAPI::ASSET_PLACEHOLDER_PREFIX)
          end
        next if upload_reference.to_s.strip.empty?

        resolved_url = replacements[upload_reference]
        raise ValidationError, "Asset reference #{upload_reference} was not uploaded" if resolved_url.nil?

        image["src"] = resolved_url
      end

      fragment.to_html
    end

    def resolve_snapshot_document_assets(token:, snapshot_document_html:, prepared_assets:)
      return nil if snapshot_document_html.to_s.strip.empty?

      replacements = prepared_assets.each_with_object({}) do |asset, map|
        map[asset[:upload_reference]] = "/assets/#{token}/#{asset[:stored_name]}"
      end
      return snapshot_document_html if replacements.empty?

      document = Nokogiri::HTML.parse(snapshot_document_html.to_s)
      document.css("img").each do |image|
        src = image["src"].to_s.strip
        upload_reference =
          if src.start_with?("asset://")
            src.delete_prefix("asset://")
          elsif src.start_with?(ShareAPI::ASSET_PLACEHOLDER_PREFIX)
            src.delete_prefix(ShareAPI::ASSET_PLACEHOLDER_PREFIX)
          end
        next if upload_reference.to_s.strip.empty?

        resolved_url = replacements[upload_reference]
        raise ValidationError, "Asset reference #{upload_reference} was not uploaded" if resolved_url.nil?

        image["src"] = resolved_url
      end

      document.to_html
    end

    def promote_assets(token:, prepared_assets:)
      target_dir = asset_dir(token)
      FileUtils.mkdir_p(target_dir)

      prepared_assets.each do |asset|
        path = target_dir.join(asset[:stored_name])
        atomic_write(path, asset[:bytes])
      end
    end

    def cleanup_orphan_assets(token:, keep_names:)
      target_dir = asset_dir(token)
      return unless target_dir.directory?

      keep_names = Array(keep_names).to_set
      target_dir.each_child do |child|
        child.delete if child.file? && !keep_names.include?(child.basename.to_s)
      end

      target_dir.rmdir if target_dir.empty?
    end

    def resolved_asset_manifest(asset_manifest, token, prepared_assets)
      replacements = prepared_assets.each_with_object({}) do |asset, map|
        map[asset[:upload_reference]] = {
          public_url: "/assets/#{token}/#{asset[:stored_name]}",
          stored_name: asset[:stored_name]
        }
      end

      Array(asset_manifest).map do |entry|
        next entry unless entry.is_a?(Hash)

        upload_reference = entry["upload_reference"] || entry[:upload_reference]
        resolved = replacements[upload_reference]
        next entry unless resolved

        entry.merge(
          "public_url" => resolved[:public_url],
          "stored_name" => resolved[:stored_name]
        )
      end
    end

    def expired_share?(share, now: Time.now.utc)
      expires_at = share["expires_at"].to_s.strip
      return false if expires_at.empty?

      Time.iso8601(expires_at) <= now.utc
    rescue ArgumentError
      false
    end

    def purge_share(share)
      token = share.fetch("token")
      share_file(token).delete if share_file(token).exist?
      FileUtils.rm_rf(snapshot_dir(token)) if snapshot_dir(token).exist?
      FileUtils.rm_rf(asset_dir(token)) if asset_dir(token).exist?

      identity_key = share["identity_key"].to_s
      unless identity_key.empty?
        index_file = identity_index_file(identity_key)
        index_file.delete if index_file.exist?
      end
    end

    def prune_orphan_identity_indexes!
      Dir.glob(path_index_dir.join("*.json")).sort.each do |file_path|
        file = Pathname.new(file_path)
        payload = JSON.parse(file.read)
        token = payload.fetch("token")
        file.delete unless share_file(token).file?
      rescue JSON::ParserError, KeyError
        file.delete if file.file?
      end
    end
  end
end
