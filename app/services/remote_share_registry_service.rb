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

  def active_share_for(path, note_identifier: nil)
    normalized_path = normalize_note_path(path)
    normalized_note_identifier = normalize_note_identifier(note_identifier)

    metadata_files.each do |file|
      metadata = parse_metadata_file(file)
      next unless metadata

      if expired_share?(metadata)
        file.delete if file.exist?
        next
      end

      matches_identifier = normalized_note_identifier.present? && metadata[:note_identifier] == normalized_note_identifier
      matches_path = metadata[:path] == normalized_path
      next unless matches_identifier || matches_path

      return synchronize_metadata(
        metadata,
        file: file,
        normalized_path: normalized_path,
        note_identifier: normalized_note_identifier
      )
    end

    nil
  end

  def save(metadata)
    normalized_path = normalize_note_path(metadata.fetch(:path))
    normalized_note_identifier = normalize_note_identifier(metadata[:note_identifier])
    normalized_metadata = {
      backend: "remote",
      token: metadata.fetch(:token),
      note_identifier: normalized_note_identifier,
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
      expires_at: metadata[:expires_at],
      capabilities: metadata[:capabilities] || {}
    }

    file = metadata_file(normalized_metadata.fetch(:token))
    write_metadata(file, normalized_metadata)
    cleanup_duplicate_metadata_files(file, normalized_metadata)
    normalized_metadata
  end

  def mark_stale(path:, note_identifier: nil, error:)
    metadata = active_share_for(path, note_identifier: note_identifier)
    raise ShareService::NotFoundError, "Share not found for #{path}" unless metadata

    save(metadata.merge(
      stale: true,
      last_error: error.to_s,
      last_synced_at: Time.current.iso8601
    ))
  end

  def delete(path:, note_identifier: nil)
    metadata = active_share_for(path, note_identifier: note_identifier)
    return unless metadata

    matching_metadata_files(metadata).each do |file|
      file.delete if file.exist?
    end
  end

  def delete_all
    deleted_count = 0

    metadata_files.each do |file|
      next unless file.exist?

      file.delete
      deleted_count += 1
    end

    deleted_count
  end

  private

  attr_reader :base_path

  def registry_dir
    @registry_dir ||= base_path.join(REGISTRY_DIR)
  end

  def metadata_files
    Dir.glob(registry_dir.join("*.json")).sort.map { |path| Pathname.new(path) }
  end

  def metadata_file(token)
    registry_dir.join("#{token}.json")
  end

  def normalize_note_path(path)
    normalized_path = Note.normalize_path(path)
    raise ShareService::InvalidShareError, "Invalid share path" if normalized_path.blank?
    raise ShareService::InvalidShareError, "Only markdown notes can be shared" unless normalized_path.end_with?(".md")

    normalized_path
  end

  def normalize_note_identifier(note_identifier)
    note_identifier.to_s.strip.presence
  end

  def parse_metadata_file(file)
    payload = JSON.parse(File.read(file), symbolize_names: true)
    return nil unless payload[:backend] == "remote"
    return nil unless payload[:token].to_s.match?(TOKEN_PATTERN)
    return nil if payload[:url].to_s.strip.blank?

    {
      backend: payload[:backend],
      token: payload[:token],
      note_identifier: normalize_note_identifier(payload[:note_identifier]),
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
      expires_at: payload[:expires_at],
      capabilities: payload[:capabilities].is_a?(Hash) ? payload[:capabilities] : {}
    }
  rescue JSON::ParserError
    nil
  end

  def write_metadata(file, metadata)
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

  def expired_share?(metadata)
    expires_at = metadata[:expires_at].to_s.strip
    return false if expires_at.blank?

    Time.iso8601(expires_at) <= Time.current
  rescue ArgumentError
    false
  end

  def synchronize_metadata(metadata, file:, normalized_path:, note_identifier:)
    updates = {}
    updates[:path] = normalized_path if metadata[:path] != normalized_path

    normalized_note_identifier = normalize_note_identifier(note_identifier)
    if normalized_note_identifier.present? && metadata[:note_identifier] != normalized_note_identifier
      updates[:note_identifier] = normalized_note_identifier
    end

    return metadata if updates.empty? && file == metadata_file(metadata[:token])

    updated_metadata = metadata.merge(updates)
    save(updated_metadata)
  end

  def cleanup_duplicate_metadata_files(canonical_file, metadata)
    matching_metadata_files(metadata).each do |file|
      next if file == canonical_file

      file.delete if file.exist?
    end
  end

  def matching_metadata_files(metadata)
    normalized_path = metadata[:path]
    normalized_note_identifier = normalize_note_identifier(metadata[:note_identifier])
    token = metadata[:token]

    metadata_files.select do |file|
      parsed = parse_metadata_file(file)
      next false unless parsed

      parsed[:token] == token ||
        (normalized_note_identifier.present? && parsed[:note_identifier] == normalized_note_identifier) ||
        parsed[:path] == normalized_path
    end
  end
end
