# frozen_string_literal: true

require "json"
require "tempfile"

class TemplatesService
  class NotFoundError < StandardError; end
  class InvalidPathError < StandardError; end
  class InvalidNoteError < StandardError; end
  class ConflictError < StandardError; end

  SUPPORTED_EXTENSIONS = %w[.md .markdown].freeze
  DEFAULT_ROOT = ".frankmd/templates"
  LINKS_PATH = ".frankmd/template_links.json"

  attr_reader :base_path

  def initialize(base_path: nil, seed_source: nil, config: nil)
    @config = config || Config.new(base_path: base_path)
    @notes_path = Pathname.new(base_path || @config.base_path).expand_path
    configured_path = @config.get("templates_path")
    @base_path = Pathname.new(configured_path.presence || default_templates_path(@notes_path)).expand_path
    @seed_source = Pathname.new(seed_source || Rails.root.join("lib", "templates", "default")).expand_path
    ensure_templates_directory!
  end

  def list
    template_files.sort_by { |path| path.relative_path_from(base_path).to_s.downcase }.filter_map do |path|
      next unless path.file?

      relative_path = path.relative_path_from(base_path).to_s
      {
        name: File.basename(relative_path, path.extname),
        path: relative_path,
        directory: directory_for(relative_path),
        extname: path.extname,
        mtime: path.mtime.iso8601
      }
    rescue Errno::ENOENT
      nil
    end
  end

  def read(path)
    full_path = safe_path(path)
    raise NotFoundError, "Template not found: #{path}" unless full_path.file?

    full_path.read
  rescue Errno::ENOENT
    raise NotFoundError, "Template not found: #{path}"
  end

  def write(path, content)
    full_path = safe_path(path, must_exist: false)
    FileUtils.mkdir_p(full_path.dirname)
    full_path.write(content.to_s)
    full_path.relative_path_from(base_path).to_s
  end

  def update(path:, content:, new_path: nil)
    normalized_current_path = normalize_path(path)
    normalized_new_path = normalize_path(new_path.presence || path)
    current_full_path = safe_path(normalized_current_path)
    raise NotFoundError, "Template not found: #{path}" unless current_full_path.file?

    destination_full_path = safe_path(normalized_new_path, must_exist: false)
    if normalized_new_path != normalized_current_path
      if destination_full_path.exist?
        raise ConflictError, "Template already exists: #{normalized_new_path}"
      end

      FileUtils.mkdir_p(destination_full_path.dirname)
      FileUtils.mv(current_full_path, destination_full_path)
      rewrite_linked_template_paths(normalized_current_path, normalized_new_path)
    end

    destination_full_path.write(content.to_s)
    destination_full_path.relative_path_from(base_path).to_s
  rescue Errno::ENOENT
    raise NotFoundError, "Template not found: #{path}"
  end

  def delete(path)
    full_path = safe_path(path)
    raise NotFoundError, "Template not found: #{path}" unless full_path.file?

    full_path.delete
    full_path.relative_path_from(base_path).to_s
  rescue Errno::ENOENT
    raise NotFoundError, "Template not found: #{path}"
  end

  def exists?(path)
    safe_path(path, must_exist: false).file?
  end

  def linked_template_path_for(note_path)
    normalized_note_path = normalize_note_path(note_path)
    template_path = template_links[normalized_note_path]
    return nil if template_path.blank?

    normalized_template_path = normalize_path(template_path)
    return normalized_template_path if exists?(normalized_template_path)

    unlink_note(normalized_note_path)
    nil
  end

  def template_linked?(note_path)
    linked_template_path_for(note_path).present?
  end

  def save_from_note(note_path:, template_path: nil)
    normalized_note_path = normalize_note_path(note_path)
    note_file = note_file_for(normalized_note_path)
    raise InvalidNoteError, "Note not found: #{note_path}" unless note_file.file?

    stored_template_path = write(template_path.presence || normalized_note_path, note_file.read)
    links = template_links
    links[normalized_note_path] = stored_template_path
    write_template_links(links)

    stored_template_path
  end

  def delete_for_note(note_path)
    normalized_note_path = normalize_note_path(note_path)
    linked_template_path = template_links[normalized_note_path]
    raise NotFoundError, "Linked template not found for #{note_path}" if linked_template_path.blank?

    delete(linked_template_path) if exists?(linked_template_path)

    links = template_links
    links.delete(normalized_note_path)
    write_template_links(links)

    normalize_path(linked_template_path)
  end

  def unlink_note(note_path)
    normalized_note_path = normalize_note_path(note_path)
    links = template_links
    removed_path = links.delete(normalized_note_path)
    write_template_links(links) if removed_path
    removed_path
  end

  def move_note_link(old_note_path, new_note_path)
    normalized_old_note_path = normalize_note_path(old_note_path)
    normalized_new_note_path = normalize_note_path(new_note_path)
    links = template_links
    linked_template_path = links.delete(normalized_old_note_path)
    return nil unless linked_template_path

    links[normalized_new_note_path] = linked_template_path
    write_template_links(links)
    linked_template_path
  end

  private

  def default_templates_path(notes_path)
    notes_path.join(DEFAULT_ROOT)
  end

  def ensure_templates_directory!
    FileUtils.mkdir_p(base_path)
    seed_defaults!
  end

  def seed_defaults!
    return unless @seed_source.directory?

    @seed_source.glob("**/*").sort.each do |source_path|
      next if source_path.directory?
      next unless supported_template?(source_path)

      relative_path = source_path.relative_path_from(@seed_source)
      destination = base_path.join(relative_path)
      next if destination.exist?

      FileUtils.mkdir_p(destination.dirname)
      FileUtils.cp(source_path, destination)
    end
  end

  def template_files(dir = base_path)
    return [] unless dir.directory?

    dir.children.filter_map do |entry|
      next if hidden_entry?(entry)

      if entry.directory?
        template_files(entry)
      elsif entry.file? && supported_template?(entry)
        entry
      end
    end.flatten
  end

  def hidden_entry?(entry)
    entry.basename.to_s.start_with?(".")
  end

  def supported_template?(path)
    SUPPORTED_EXTENSIONS.include?(path.extname.downcase)
  end

  def safe_path(path, must_exist: true)
    normalized = normalize_path(path)
    full_path = base_path.join(normalized).expand_path

    unless full_path.to_s.start_with?(base_path.to_s)
      raise InvalidPathError, "Invalid template path: #{path}"
    end

    if must_exist && !full_path.exist?
      raise NotFoundError, "Template not found: #{path}"
    end

    full_path
  end

  def normalize_path(path)
    candidate = path.to_s.strip
    raise InvalidPathError, "Invalid template path: #{path}" if candidate.blank?

    normalized = Pathname.new(candidate).cleanpath
    raise InvalidPathError, "Invalid template path: #{path}" if normalized.each_filename.include?("..")

    normalized_string = normalized.to_s
    return normalized_string if SUPPORTED_EXTENSIONS.include?(File.extname(normalized_string).downcase)

    "#{normalized_string}.md"
  end

  def directory_for(relative_path)
    directory = File.dirname(relative_path)
    directory == "." ? "" : directory
  end

  def normalize_note_path(path)
    normalized_path = Note.normalize_path(path)
    raise InvalidNoteError, "Invalid note path: #{path}" if normalized_path.blank?
    raise InvalidNoteError, "Only markdown notes can be used as templates" unless normalized_path.end_with?(".md")

    normalized_path
  end

  def note_file_for(normalized_note_path)
    note_pathname = @notes_path.join(normalized_note_path).expand_path
    raise InvalidNoteError, "Invalid note path: #{normalized_note_path}" unless note_pathname.to_s.start_with?(@notes_path.to_s)

    note_pathname
  end

  def template_links_path
    @template_links_path ||= @notes_path.join(LINKS_PATH)
  end

  def template_links
    file = template_links_path
    if file.file?
      JSON.parse(file.read)
    else
      {}
    end
  rescue JSON::ParserError
    {}
  end

  def write_template_links(links)
    atomic_write(template_links_path, JSON.pretty_generate(links))
  end

  def rewrite_linked_template_paths(old_template_path, new_template_path)
    links = template_links
    updated = false

    links.each do |note_path, linked_template_path|
      next unless normalize_path(linked_template_path) == old_template_path

      links[note_path] = new_template_path
      updated = true
    end

    write_template_links(links) if updated
  end

  def atomic_write(pathname, content)
    FileUtils.mkdir_p(pathname.dirname)

    Tempfile.create([ pathname.basename.to_s, ".tmp" ], pathname.dirname.to_s) do |tempfile|
      tempfile.binmode
      tempfile.write(content)
      tempfile.flush
      tempfile.fsync
      FileUtils.mv(tempfile.path, pathname, force: true)
    end
  end
end
