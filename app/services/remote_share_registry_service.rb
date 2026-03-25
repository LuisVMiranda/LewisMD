# frozen_string_literal: true

require "digest"
require "json"
require "tempfile"

class RemoteShareRegistryService
  REGISTRY_DIR = ".frankmd/remote_shares"
  TOKEN_PATTERN = /\A[a-zA-Z0-9\-_]{8,}\z/

  def initialize(base_path: nil)
    @base_path = Pathname.new(base_path || ENV.fetch("NOTES_PATH", Rails.root.join("notes"))).expand_path
    FileUtils.mkdir_p(@base_path) unless @base_path.exist?
  end

  def active_share_for(path)
    normalized_path = normalize_note_path(path)
    file = metadata_file(normalized_path)
    return nil unless file.file?

    parse_metadata_file(file)
  end

  def save(metadata)
    normalized_path = normalize_note_path(metadata.fetch(:path))
    normalized_metadata = {
      backend: "remote",
      token: metadata.fetch(:token),
      path: normalized_path,
      title: metadata.fetch(:title),
      url: metadata.fetch(:url),
      created_at: metadata.fetch(:created_at),
      updated_at: metadata.fetch(:updated_at),
      stale: BooleanCaster.cast(metadata[:stale]),
      last_error: metadata[:last_error],
      last_synced_at: metadata[:last_synced_at],
      content_hash: metadata[:content_hash],
      locale: metadata[:locale],
      theme_id: metadata[:theme_id],
      asset_manifest: metadata[:asset_manifest] || [],
      capabilities: metadata[:capabilities] || {}
    }

    write_metadata(normalized_path, normalized_metadata)
    normalized_metadata
  end

  def mark_stale(path:, error:)
    metadata = active_share_for(path)
    raise ShareService::NotFoundError, "Share not found for #{path}" unless metadata

    save(metadata.merge(
      stale: true,
      last_error: error.to_s,
      last_synced_at: Time.current.iso8601
    ))
  end

  def delete(path:)
    normalized_path = normalize_note_path(path)
    file = metadata_file(normalized_path)
    file.delete if file.exist?
  end

  private

  attr_reader :base_path

  def registry_dir
    @registry_dir ||= base_path.join(REGISTRY_DIR)
  end

  def metadata_file(normalized_path)
    registry_dir.join("#{Digest::SHA256.hexdigest(normalized_path)}.json")
  end

  def normalize_note_path(path)
    normalized_path = Note.normalize_path(path)
    raise ShareService::InvalidShareError, "Invalid share path" if normalized_path.blank?
    raise ShareService::InvalidShareError, "Only markdown notes can be shared" unless normalized_path.end_with?(".md")

    normalized_path
  end

  def parse_metadata_file(file)
    payload = JSON.parse(File.read(file), symbolize_names: true)
    return nil unless payload[:backend] == "remote"
    return nil unless payload[:token].to_s.match?(TOKEN_PATTERN)
    return nil if payload[:url].to_s.strip.blank?

    {
      backend: payload[:backend],
      token: payload[:token],
      path: payload[:path],
      title: payload[:title],
      url: payload[:url],
      created_at: payload[:created_at],
      updated_at: payload[:updated_at],
      stale: BooleanCaster.cast(payload[:stale]),
      last_error: payload[:last_error],
      last_synced_at: payload[:last_synced_at],
      content_hash: payload[:content_hash],
      locale: payload[:locale],
      theme_id: payload[:theme_id],
      asset_manifest: Array(payload[:asset_manifest]),
      capabilities: payload[:capabilities].is_a?(Hash) ? payload[:capabilities] : {}
    }
  rescue JSON::ParserError
    nil
  end

  def write_metadata(normalized_path, metadata)
    file = metadata_file(normalized_path)
    FileUtils.mkdir_p(file.dirname)

    tempfile = Tempfile.new([ file.basename.to_s, ".tmp" ], file.dirname.to_s)
    tempfile.binmode
    tempfile.write(JSON.pretty_generate(metadata))
    tempfile.flush
    tempfile.fsync

    temp_path = tempfile.path
    tempfile.close
    FileUtils.mv(temp_path, file.to_s, force: true)
  ensure
    tempfile&.close!
  end

  module BooleanCaster
    module_function

    def cast(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end
  end
end
