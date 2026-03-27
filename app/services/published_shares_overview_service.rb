# frozen_string_literal: true

class PublishedSharesOverviewService
  def initialize(base_path: nil, share_service: nil, remote_share_registry_service: nil, note_share_identity_service: nil)
    @share_service = share_service || ShareService.new(base_path: base_path)
    @remote_share_registry_service = remote_share_registry_service || RemoteShareRegistryService.new(base_path: base_path)
    @note_share_identity_service = note_share_identity_service || NoteShareIdentityService.new(base_path: base_path)
  end

  def list
    note_index = build_note_index

    rows = share_service.list_active_shares.map do |metadata|
      normalize_row(metadata, backend: "local", note_index:)
    end

    rows.concat(
      remote_share_registry_service.list_active_shares.map do |metadata|
        normalize_row(metadata, backend: "remote", note_index:)
      end
    )

    rows.sort_by { |row| timestamp_for(row) }.reverse
  end

  private

  attr_reader :share_service, :remote_share_registry_service, :note_share_identity_service

  def build_note_index
    notes = note_share_identity_service.indexed_notes

    {
      by_path: notes.index_by { |note| note[:path] },
      by_identifier: notes.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |note, grouped|
        next if note[:note_identifier].blank?

        grouped[note[:note_identifier]] << note
      end
    }
  end

  def normalize_row(metadata, backend:, note_index:)
    stored_path = metadata[:path]
    stored_title = metadata[:title].to_s.strip.presence || File.basename(stored_path.to_s, ".md")
    resolved_note = resolve_note(metadata, note_index)
    current_path = resolved_note&.dig(:path)
    current_title = resolved_note&.dig(:title)

    {
      backend: backend,
      token: metadata[:token],
      note_identifier: metadata[:note_identifier],
      path: current_path || stored_path,
      current_path: current_path,
      stored_path: stored_path,
      title: current_title.presence || stored_title,
      current_title: current_title,
      stored_title: stored_title,
      url: share_url_for(metadata, backend: backend),
      created_at: metadata[:created_at],
      updated_at: metadata[:updated_at],
      stale: stale_row?(metadata, backend: backend),
      missing_locally: resolved_note.nil?,
      snapshot_missing: metadata[:snapshot_missing] == true,
      last_error: metadata[:last_error],
      expires_at: metadata[:expires_at]
    }
  end

  def resolve_note(metadata, note_index)
    note_identifier = metadata[:note_identifier].to_s.strip
    stored_path = metadata[:path]

    if note_identifier.present?
      candidates = note_index[:by_identifier][note_identifier]
      return candidates.first if candidates.size == 1

      matched_path = candidates.find { |note| note[:path] == stored_path }
      return matched_path if matched_path
      return candidates.first if candidates.any?
    end

    note_index[:by_path][stored_path]
  end

  def share_url_for(metadata, backend:)
    return metadata[:url] if backend == "remote"

    Rails.application.routes.url_helpers.share_snapshot_path(token: metadata[:token])
  end

  def stale_row?(metadata, backend:)
    return metadata[:snapshot_missing] == true if backend == "local"

    metadata[:stale] == true
  end

  def timestamp_for(row)
    parse_time(row[:updated_at]) || parse_time(row[:created_at]) || Time.at(0)
  end

  def parse_time(value)
    return nil if value.to_s.strip.blank?

    Time.iso8601(value)
  rescue ArgumentError
    nil
  end
end
