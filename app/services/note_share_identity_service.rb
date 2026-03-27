# frozen_string_literal: true

require "securerandom"

class NoteShareIdentityService
  KEY = "lewismd_note_id"

  def initialize(base_path: nil, notes_service: nil)
    @notes_service = notes_service || NotesService.new(base_path: base_path)
  end

  def identity_for(note_or_path)
    note = load_note(note_or_path)
    extract_frontmatter_metadata(note_content_for(note))[:note_identifier]
  end

  def ensure_identity!(note_or_path)
    note = load_note(note_or_path)
    content = note_content_for(note)
    parsed = extract_frontmatter_metadata(content)
    existing_identifier = parsed[:note_identifier]

    if existing_identifier.present? && unique_identifier?(existing_identifier, excluding_path: note.path)
      return {
        note_identifier: existing_identifier,
        content: nil,
        updated: false
      }
    end

    note_identifier = generate_unique_identifier(excluding_path: note.path)
    updated_content = upsert_identifier(content, parsed:, note_identifier:)

    note.content = updated_content
    persist_note!(note)

    {
      note_identifier: note_identifier,
      content: updated_content,
      updated: true
    }
  end

  private

  attr_reader :notes_service

  def load_note(note_or_path)
    return note_or_path if note_or_path.is_a?(Note)

    Note.find(note_or_path)
  end

  def note_content_for(note)
    note.content.presence || note.read
  end

  def extract_frontmatter_metadata(content)
    normalized_content = content.to_s
    newline = normalized_content.include?("\r\n") ? "\r\n" : "\n"

    if normalized_content.start_with?("---")
      match = normalized_content.match(/\A---\r?\n(?<frontmatter>.*?)(?:\r?\n)---(?<separator>\r?\n|\z)/m)
      raise ShareService::InvalidShareError, I18n.t("errors.share_identity_frontmatter_invalid") unless match

      frontmatter = match[:frontmatter].to_s
      {
        format: :yaml,
        frontmatter: frontmatter,
        body: normalized_content[match.end(0)..].to_s,
        note_identifier: extract_yaml_identifier(frontmatter),
        newline: newline
      }
    elsif normalized_content.start_with?("+++")
      match = normalized_content.match(/\A\+\+\+\r?\n(?<frontmatter>.*?)(?:\r?\n)\+\+\+(?<separator>\r?\n|\z)/m)
      raise ShareService::InvalidShareError, I18n.t("errors.share_identity_frontmatter_invalid") unless match

      frontmatter = match[:frontmatter].to_s
      {
        format: :toml,
        frontmatter: frontmatter,
        body: normalized_content[match.end(0)..].to_s,
        note_identifier: extract_toml_identifier(frontmatter),
        newline: newline
      }
    else
      {
        format: nil,
        frontmatter: nil,
        body: normalized_content,
        note_identifier: nil,
        newline: newline
      }
    end
  end

  def extract_yaml_identifier(frontmatter)
    value = frontmatter[/^\s*#{Regexp.escape(KEY)}\s*:\s*(.+?)\s*$/, 1]
    normalize_identifier_value(value)
  end

  def extract_toml_identifier(frontmatter)
    value = frontmatter[/^\s*#{Regexp.escape(KEY)}\s*=\s*(.+?)\s*$/, 1]
    normalize_identifier_value(value)
  end

  def normalize_identifier_value(value)
    return nil if value.blank?

    trimmed = value.to_s.strip
    if (trimmed.start_with?('"') && trimmed.end_with?('"')) || (trimmed.start_with?("'") && trimmed.end_with?("'"))
      trimmed = trimmed[1...-1]
    end

    trimmed.presence
  end

  def upsert_identifier(content, parsed:, note_identifier:)
    newline = parsed[:newline]

    case parsed[:format]
    when :yaml
      updated_frontmatter = upsert_yaml_frontmatter(parsed[:frontmatter], note_identifier, newline)
      +"---#{newline}#{updated_frontmatter}#{newline}---#{newline}#{parsed[:body]}"
    when :toml
      updated_frontmatter = upsert_toml_frontmatter(parsed[:frontmatter], note_identifier, newline)
      +"+++#{newline}#{updated_frontmatter}#{newline}+++#{newline}#{parsed[:body]}"
    else
      base = +"---#{newline}#{KEY}: #{note_identifier}#{newline}---#{newline}"
      base << content.to_s
      base
    end
  end

  def upsert_yaml_frontmatter(frontmatter, note_identifier, newline)
    replacement = "#{KEY}: #{note_identifier}"
    existing_key_pattern = /^(\s*)#{Regexp.escape(KEY)}\s*:\s*.*$/

    if frontmatter.match?(existing_key_pattern)
      frontmatter.sub(existing_key_pattern) { "#{$1}#{replacement}" }
    else
      append_frontmatter_line(frontmatter, replacement, newline)
    end
  end

  def upsert_toml_frontmatter(frontmatter, note_identifier, newline)
    replacement = %(#{KEY} = "#{note_identifier}")
    existing_key_pattern = /^(\s*)#{Regexp.escape(KEY)}\s*=\s*.*$/

    if frontmatter.match?(existing_key_pattern)
      frontmatter.sub(existing_key_pattern) { "#{$1}#{replacement}" }
    else
      append_frontmatter_line(frontmatter, replacement, newline)
    end
  end

  def append_frontmatter_line(frontmatter, line, newline)
    normalized_frontmatter = frontmatter.to_s.sub(/(?:\r?\n)+\z/, "")
    return line if normalized_frontmatter.blank?

    "#{normalized_frontmatter}#{newline}#{line}"
  end

  def persist_note!(note)
    return if note.save

    message = note.errors.full_messages.join(", ").presence || I18n.t("errors.failed_to_save")
    raise ShareService::InvalidShareError, message
  end

  def generate_unique_identifier(excluding_path:)
    loop do
      note_identifier = SecureRandom.uuid
      return note_identifier if unique_identifier?(note_identifier, excluding_path: excluding_path)
    end
  end

  def unique_identifier?(note_identifier, excluding_path:)
    markdown_note_paths.each do |path|
      next if path == excluding_path

      content = notes_service.read(path)
      next unless extract_frontmatter_metadata(content)[:note_identifier] == note_identifier

      return false
    rescue NotesService::NotFoundError, ShareService::InvalidShareError
      next
    end

    true
  end

  def markdown_note_paths
    collect_markdown_note_paths(notes_service.list_tree)
  end

  def collect_markdown_note_paths(items)
    Array(items).each_with_object([]) do |item, paths|
      item_type = item[:type] || item["type"]

      if item_type == "folder"
        child_items = item[:children] || item["children"] || []
        paths.concat(collect_markdown_note_paths(child_items))
      elsif item_type == "file" && (item[:file_type] || item["file_type"]) == "markdown"
        path = item[:path] || item["path"]
        paths << path if path.present?
      end
    end
  end
end
