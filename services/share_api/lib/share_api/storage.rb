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

    def upsert_share(identity_key:, share:, fragment_html:, assets: [])
      validate_identity_key!(identity_key)
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

      persisted_share = share.merge(
        "token" => token,
        "identity_key" => identity_key,
        "created_at" => existing_share&.fetch("created_at", nil) || timestamp,
        "updated_at" => timestamp,
        "asset_manifest" => resolved_asset_manifest(share["asset_manifest"], token, prepared_assets)
      )

      promote_assets(token: token, prepared_assets: prepared_assets)
      write_fragment(token, resolved_fragment_html)
      write_share_metadata(persisted_share)
      write_identity_index(identity_key, token)
      cleanup_orphan_assets(token: token, keep_names: prepared_assets.map { |asset| asset[:stored_name] })

      [ existing_share.nil?, persisted_share ]
    end

    def update_share(token:, share:, fragment_html:, assets: [])
      validate_token!(token)
      existing_share = fetch_share(token)
      prepared_assets = prepare_assets(assets)
      resolved_fragment_html = resolve_fragment_assets(
        token: token,
        fragment_html: fragment_html,
        prepared_assets: prepared_assets
      )

      persisted_share = existing_share.merge(share).merge(
        "token" => token,
        "updated_at" => Time.now.utc.iso8601,
        "asset_manifest" => resolved_asset_manifest(share["asset_manifest"], token, prepared_assets)
      )

      promote_assets(token: token, prepared_assets: prepared_assets)
      write_fragment(token, resolved_fragment_html)
      write_share_metadata(persisted_share)
      write_identity_index(existing_share.fetch("identity_key"), token)
      cleanup_orphan_assets(token: token, keep_names: prepared_assets.map { |asset| asset[:stored_name] })

      persisted_share
    end

    def fetch_share(token)
      validate_token!(token)
      file = share_file(token)
      raise NotFoundError unless file.file?

      JSON.parse(file.read)
    rescue JSON::ParserError
      raise NotFoundError
    end

    def find_share_by_identity(identity_key)
      validate_identity_key!(identity_key)
      file = identity_index_file(identity_key)
      return nil unless file.file?

      payload = JSON.parse(file.read)
      fetch_share(payload.fetch("token"))
    rescue JSON::ParserError, KeyError, NotFoundError
      nil
    end

    def read_fragment(token)
      validate_token!(token)
      file = fragment_file(token)
      raise NotFoundError unless file.file?

      file.read
    end

    def delete_share(token:)
      share = fetch_share(token)
      share_file(token).delete if share_file(token).exist?
      fragment_file(token).delete if fragment_file(token).exist?
      FileUtils.rm_rf(asset_dir(token)) if asset_dir(token).exist?
      identity_index_file(share.fetch("identity_key")).delete if identity_index_file(share.fetch("identity_key")).exist?
      share
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

    def share_file(token)
      shares_dir.join("#{token}.json")
    end

    def fragment_file(token)
      snapshots_dir.join(token, "index.html")
    end

    def asset_dir(token)
      assets_dir.join(token)
    end

    def identity_index_file(identity_key)
      path_index_dir.join("#{Digest::SHA256.hexdigest(identity_key)}.json")
    end

    def nonce_file(request_id)
      nonces_dir.join("#{Digest::SHA256.hexdigest(request_id)}.json")
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
  end
end
