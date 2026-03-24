# frozen_string_literal: true

require "find"
require "fileutils"
require "tempfile"
require "zip"

class BackupService
  class NotFoundError < StandardError; end
  class InvalidPathError < StandardError; end

  class Archive
    attr_reader :path, :filename

    def initialize(path:, filename:)
      @path = Pathname.new(path).expand_path
      @filename = filename
    end

    def cleanup!
      FileUtils.rm_f(path)
    end
  end

  attr_reader :base_path

  def initialize(base_path: nil, temp_root: nil)
    @base_path = Pathname.new(base_path || ENV.fetch("NOTES_PATH", Rails.root.join("notes"))).expand_path
    @temp_root = Pathname.new(temp_root || Rails.root.join("tmp", "backups")).expand_path

    FileUtils.mkdir_p(@base_path) unless @base_path.exist?
    FileUtils.mkdir_p(@temp_root)
  end

  def backup_note(path)
    note_path = safe_note_path(path)
    archive_path = build_archive_path
    archive_filename = build_archive_filename(note_path.basename(".md").to_s)

    create_archive(archive_path) do |zip_file|
      add_file_entry(zip_file, note_path, note_path.basename.to_s)
    end

    Archive.new(path: archive_path, filename: archive_filename)
  end

  def backup_folder(path)
    folder_path = safe_folder_path(path)
    archive_path = build_archive_path
    archive_root = folder_path.basename.to_s
    archive_filename = build_archive_filename(archive_root)

    create_archive(archive_path) do |zip_file|
      add_directory_entry(zip_file, "#{archive_root}/")

      Find.find(folder_path.to_s) do |entry|
        entry_path = Pathname.new(entry)
        next if entry_path == folder_path

        relative_path = entry_path.relative_path_from(folder_path).to_s.tr("\\", "/")
        archive_entry_path = "#{archive_root}/#{relative_path}"

        if entry_path.directory?
          add_directory_entry(zip_file, "#{archive_entry_path}/")
        elsif entry_path.file?
          add_file_entry(zip_file, entry_path, archive_entry_path)
        end
      end
    end

    Archive.new(path: archive_path, filename: archive_filename)
  end

  private

  def safe_note_path(path)
    normalized_path = Note.normalize_path(path)
    raise InvalidPathError, "Invalid note path: #{path}" unless normalized_path.end_with?(".md")

    full_path = safe_path(normalized_path)
    raise NotFoundError, "Note not found: #{path}" unless full_path.file?

    full_path
  end

  def safe_folder_path(path)
    full_path = safe_path(path)
    raise NotFoundError, "Folder not found: #{path}" unless full_path.directory?

    full_path
  end

  def safe_path(path)
    normalized_path = normalize_path(path)
    full_path = base_path.join(normalized_path).expand_path

    unless full_path.to_s.start_with?(base_path.to_s)
      raise InvalidPathError, "Invalid backup path: #{path}"
    end

    raise NotFoundError, "Path not found: #{path}" unless full_path.exist?

    full_path
  end

  def normalize_path(path)
    candidate = path.to_s.strip
    raise InvalidPathError, "Invalid backup path: #{path}" if candidate.blank?

    normalized = Pathname.new(candidate).cleanpath
    if normalized.absolute? || normalized.each_filename.include?("..")
      raise InvalidPathError, "Invalid backup path: #{path}"
    end

    normalized
  end

  def build_archive_path
    tempfile = Tempfile.new([ "frankmd-backup-", ".zip" ], @temp_root.to_s)
    tempfile.close
    Pathname.new(tempfile.path)
  end

  def build_archive_filename(name)
    "#{name}-backup.zip"
  end

  def create_archive(archive_path)
    Zip::File.open(archive_path.to_s, create: true) do |zip_file|
      yield zip_file
    end
  rescue Errno::ENOENT => e
    FileUtils.rm_f(archive_path)
    raise NotFoundError, e.message
  rescue StandardError
    FileUtils.rm_f(archive_path)
    raise
  end

  def add_directory_entry(zip_file, entry_path)
    return if zip_file.find_entry(entry_path)

    zip_file.mkdir(entry_path)
  end

  def add_file_entry(zip_file, source_path, entry_path)
    return if zip_file.find_entry(entry_path)

    zip_file.get_output_stream(entry_path) do |stream|
      stream.write(source_path.binread)
    end
  end
end
