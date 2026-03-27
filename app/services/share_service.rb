# frozen_string_literal: true

require "json"
require "securerandom"
require "tempfile"

class ShareService
  class NotFoundError < StandardError; end
  class InvalidShareError < StandardError; end

  METADATA_DIR = ".frankmd/shares"
  SNAPSHOT_DIR = ".frankmd/share_snapshots"
  TOKEN_PATTERN = /\A[a-f0-9]{32}\z/

  def initialize(base_path: nil)
    @base_path = Pathname.new(base_path || ENV.fetch("NOTES_PATH", Rails.root.join("notes"))).expand_path
    FileUtils.mkdir_p(@base_path) unless @base_path.exist?
  end

  def create_or_find(path:, title:, snapshot_html:, note_identifier: nil)
    normalized_path = normalize_note_path(path)
    normalized_note_identifier = normalize_note_identifier(note_identifier)
    validate_snapshot_html!(snapshot_html)

    existing_share = active_share_for(
      normalized_path,
      note_identifier: normalized_note_identifier,
      require_snapshot: false
    )
    return repair_missing_snapshot(existing_share, title, snapshot_html) if existing_share && !snapshot_file(existing_share[:token]).file?
    return existing_share.merge(created: false) if existing_share

    token = generate_token
    timestamp = Time.current.iso8601
    metadata = {
      token: token,
      note_identifier: normalized_note_identifier,
      path: normalized_path,
      title: normalized_title(title, normalized_path),
      snapshot_path: snapshot_relative_path(token),
      created_at: timestamp,
      updated_at: timestamp,
      revoked: false
    }

    write_snapshot(token, snapshot_html)
    write_metadata(metadata)

    metadata.merge(created: true)
  end

  def refresh(path:, title:, snapshot_html:, note_identifier: nil)
    normalized_path = normalize_note_path(path)
    normalized_note_identifier = normalize_note_identifier(note_identifier)
    validate_snapshot_html!(snapshot_html)

    metadata = active_share_for(
      normalized_path,
      note_identifier: normalized_note_identifier,
      require_snapshot: false
    )
    raise NotFoundError, "Share not found for #{normalized_path}" unless metadata

    updated_metadata = metadata.merge(
      note_identifier: normalized_note_identifier.presence || metadata[:note_identifier],
      title: normalized_title(title, normalized_path),
      path: normalized_path,
      snapshot_path: snapshot_relative_path(metadata[:token]),
      updated_at: Time.current.iso8601,
      revoked: false
    )

    write_snapshot(updated_metadata[:token], snapshot_html)
    write_metadata(updated_metadata)

    updated_metadata
  end

  def revoke(path:, note_identifier: nil)
    normalized_path = normalize_note_path(path)
    metadata = active_share_for(
      normalized_path,
      note_identifier: note_identifier,
      require_snapshot: false
    )
    raise NotFoundError, "Share not found for #{normalized_path}" unless metadata

    revoke_matching_shares(metadata)
  end

  def find_by_token(token)
    metadata = read_metadata(token)
    return nil unless metadata
    return nil if metadata[:revoked]

    file = snapshot_file(token)
    return nil unless file.file?

    metadata.merge(snapshot_file: file)
  end

  def metadata_for_token(token)
    metadata = read_metadata(token)
    return nil unless metadata
    return nil if metadata[:revoked]

    metadata.merge(
      snapshot_file: snapshot_file(token),
      snapshot_missing: !snapshot_file(token).file?
    )
  end

  def list_active_shares
    metadata_files.filter_map do |file|
      metadata = parse_metadata_file(file)
      next unless metadata
      next if metadata[:revoked]

      snapshot = snapshot_file(metadata[:token])
      metadata.merge(
        snapshot_file: snapshot,
        snapshot_missing: !snapshot.file?
      )
    end
  end

  def revoke_by_token(token)
    metadata = metadata_for_token(token)
    raise NotFoundError, "Share not found for token #{token}" unless metadata

    revoke_matching_shares(metadata.except(:snapshot_file, :snapshot_missing))
  end

  def active_share_for(path, note_identifier: nil, require_snapshot: true)
    normalized_path = normalize_note_path(path)
    normalized_note_identifier = normalize_note_identifier(note_identifier)

    metadata_files.each do |file|
      metadata = parse_metadata_file(file)
      next unless metadata
      next if metadata[:revoked]
      matches_identifier = normalized_note_identifier.present? && metadata[:note_identifier] == normalized_note_identifier
      matches_path = metadata[:path] == normalized_path
      next unless matches_identifier || matches_path
      next if require_snapshot && !snapshot_file(metadata[:token]).file?

      return synchronize_metadata(metadata, normalized_path:, note_identifier: normalized_note_identifier)
    end

    nil
  end

  private

  attr_reader :base_path

  def metadata_files
    Dir.glob(metadata_dir.join("*.json")).sort
  end

  def metadata_dir
    @metadata_dir ||= base_path.join(METADATA_DIR)
  end

  def snapshot_dir
    @snapshot_dir ||= base_path.join(SNAPSHOT_DIR)
  end

  def metadata_file(token)
    metadata_dir.join("#{token}.json")
  end

  def snapshot_file(token)
    snapshot_dir.join("#{token}.html")
  end

  def snapshot_relative_path(token)
    "#{SNAPSHOT_DIR}/#{token}.html"
  end

  def normalize_note_path(path)
    normalized_path = Note.normalize_path(path)
    raise InvalidShareError, "Invalid share path" if normalized_path.blank?
    raise InvalidShareError, "Only markdown notes can be shared" unless normalized_path.end_with?(".md")

    normalized_path
  end

  def normalize_note_identifier(note_identifier)
    note_identifier.to_s.strip.presence
  end

  def normalized_title(title, path)
    title.to_s.strip.presence || File.basename(path, ".md")
  end

  def validate_snapshot_html!(snapshot_html)
    raise InvalidShareError, "Snapshot HTML is required" if snapshot_html.to_s.strip.blank?
  end

  def repair_missing_snapshot(metadata, title, snapshot_html)
    repaired_metadata = metadata.merge(
      title: metadata[:title].presence || normalized_title(title, metadata[:path]),
      snapshot_path: snapshot_relative_path(metadata[:token]),
      updated_at: Time.current.iso8601,
      revoked: false
    )

    write_snapshot(repaired_metadata[:token], snapshot_html)
    write_metadata(repaired_metadata)

    repaired_metadata.merge(created: false)
  end

  def generate_token
    loop do
      token = SecureRandom.hex(16)
      return token unless metadata_file(token).exist?
    end
  end

  def read_metadata(token)
    return nil unless token.to_s.match?(TOKEN_PATTERN)

    file = metadata_file(token)
    return nil unless file.file?

    parse_metadata_file(file)
  end

  def parse_metadata_file(file)
    payload = JSON.parse(File.read(file), symbolize_names: true)
    return nil unless payload[:token].to_s.match?(TOKEN_PATTERN)

    {
      token: payload[:token],
      note_identifier: payload[:note_identifier],
      path: payload[:path],
      title: payload[:title],
      snapshot_path: payload[:snapshot_path],
      created_at: payload[:created_at],
      updated_at: payload[:updated_at],
      revoked: payload[:revoked]
    }
  rescue JSON::ParserError
    nil
  end

  def write_metadata(metadata)
    atomic_write(metadata_file(metadata[:token]), JSON.pretty_generate(metadata))
  end

  def synchronize_metadata(metadata, normalized_path:, note_identifier:)
    updates = {}
    updates[:path] = normalized_path if metadata[:path] != normalized_path

    normalized_note_identifier = normalize_note_identifier(note_identifier)
    if normalized_note_identifier.present? && metadata[:note_identifier] != normalized_note_identifier
      updates[:note_identifier] = normalized_note_identifier
    end

    return metadata if updates.empty?

    updated_metadata = metadata.merge(updates)
    write_metadata(updated_metadata)
    updated_metadata
  end

  def revoke_matching_shares(metadata)
    revoked_at = Time.current.iso8601

    matching_metadata_entries(metadata).each do |entry|
      revoked_metadata = entry[:metadata].merge(
        updated_at: revoked_at,
        revoked: true
      )

      write_metadata(revoked_metadata)

      file = snapshot_file(revoked_metadata[:token])
      file.delete if file.exist?
    end

    metadata.merge(
      updated_at: revoked_at,
      revoked: true
    )
  end

  def matching_metadata_entries(metadata)
    normalized_path = metadata[:path]
    normalized_note_identifier = normalize_note_identifier(metadata[:note_identifier])
    token = metadata[:token]

    metadata_files.filter_map do |file|
      parsed = parse_metadata_file(file)
      next unless parsed
      next if parsed[:revoked]

      matches = parsed[:token] == token ||
        (normalized_note_identifier.present? && parsed[:note_identifier] == normalized_note_identifier) ||
        parsed[:path] == normalized_path
      next unless matches

      {
        file: file,
        metadata: parsed
      }
    end
  end

  def write_snapshot(token, snapshot_html)
    atomic_write(snapshot_file(token), snapshot_html)
  end

  def atomic_write(pathname, content)
    FileUtils.mkdir_p(pathname.dirname)
    tempfile = Tempfile.new([ pathname.basename.to_s, ".tmp" ], pathname.dirname.to_s)
    tempfile.binmode
    tempfile.write(content)
    tempfile.flush
    tempfile.fsync

    temp_path = tempfile.path
    tempfile.close
    FileUtils.mv(temp_path, pathname.to_s, force: true)
  ensure
    tempfile&.close!
  end
end
