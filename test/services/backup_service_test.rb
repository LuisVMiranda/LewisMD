# frozen_string_literal: true

require "test_helper"
require "zip"

class BackupServiceTest < ActiveSupport::TestCase
  def setup
    setup_test_notes_dir
    @service = BackupService.new(base_path: @test_notes_dir)
    create_test_note("projects/alpha.md", "# Alpha\n\nBackup me")
    create_test_note("projects/nested/beta.md", "# Beta\n\nNested note")
    create_test_folder("projects/empty")
  end

  def teardown
    teardown_test_notes_dir
  end

  test "backup_note creates a zip with the selected markdown file" do
    archive = @service.backup_note("projects/alpha")

    assert_equal "alpha-backup.zip", archive.filename
    assert archive.path.exist?

    Zip::File.open(archive.path.to_s) do |zip_file|
      entry = zip_file.find_entry("alpha.md")

      assert_not_nil entry
      assert_equal "# Alpha\n\nBackup me", entry.get_input_stream.read
    end
  ensure
    archive&.cleanup!
  end

  test "backup_folder creates a zip with the selected folder subtree" do
    archive = @service.backup_folder("projects")

    assert_equal "projects-backup.zip", archive.filename

    Zip::File.open(archive.path.to_s) do |zip_file|
      entry_names = zip_file.entries.map(&:name)

      assert_includes entry_names, "projects/"
      assert_includes entry_names, "projects/alpha.md"
      assert_includes entry_names, "projects/nested/"
      assert_includes entry_names, "projects/nested/beta.md"
      assert_includes entry_names, "projects/empty/"
    end
  ensure
    archive&.cleanup!
  end

  test "backup_note rejects path traversal" do
    assert_raises(BackupService::InvalidPathError) do
      @service.backup_note("../outside")
    end
  end

  test "backup_folder rejects path traversal" do
    assert_raises(BackupService::InvalidPathError) do
      @service.backup_folder("../outside")
    end
  end

  test "backup_note raises not found for missing note" do
    assert_raises(BackupService::NotFoundError) do
      @service.backup_note("projects/missing")
    end
  end

  test "backup_folder raises not found for missing folder" do
    assert_raises(BackupService::NotFoundError) do
      @service.backup_folder("projects/missing")
    end
  end

  test "backup_note only allows markdown note backups" do
    fed_path = @test_notes_dir.join(".fed")
    fed_path.write("notes_path=#{@test_notes_dir}")

    assert_raises(BackupService::InvalidPathError) do
      @service.backup_note(".fed")
    end
  end

  test "archive cleanup removes generated zip file" do
    archive = @service.backup_note("projects/alpha")

    assert archive.path.exist?

    archive.cleanup!

    refute archive.path.exist?
  end

  test "backup_note normalizes disappearing files during archive creation" do
    @service.stubs(:add_file_entry).raises(Errno::ENOENT)

    assert_raises(BackupService::NotFoundError) do
      @service.backup_note("projects/alpha")
    end
  end
end
