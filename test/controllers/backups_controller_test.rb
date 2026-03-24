# frozen_string_literal: true

require "test_helper"
require "zip"

class BackupsControllerTest < ActionDispatch::IntegrationTest
  def setup
    setup_test_notes_dir
    create_test_note("projects/alpha.md", "# Alpha\n\nBackup me")
    create_test_note("projects/nested/beta.md", "# Beta\n\nNested note")
    create_test_folder("projects/empty")
  end

  def teardown
    teardown_test_notes_dir
  end

  test "note download returns a zip attachment with the selected markdown file" do
    get backup_note_url(path: "projects/alpha")

    assert_response :success
    assert_equal "application/zip", response.media_type
    assert_match(/attachment; filename="alpha-backup\.zip"/, response.headers["Content-Disposition"])

    Zip::File.open_buffer(response.body) do |zip_file|
      entry = zip_file.find_entry("alpha.md")

      assert_not_nil entry
      assert_equal "# Alpha\n\nBackup me", entry.get_input_stream.read
    end
  end

  test "folder download returns a zip attachment with the selected subtree" do
    get backup_folder_url(path: "projects")

    assert_response :success
    assert_equal "application/zip", response.media_type
    assert_match(/attachment; filename="projects-backup\.zip"/, response.headers["Content-Disposition"])

    Zip::File.open_buffer(response.body) do |zip_file|
      entry_names = zip_file.entries.map(&:name)

      assert_includes entry_names, "projects/"
      assert_includes entry_names, "projects/alpha.md"
      assert_includes entry_names, "projects/nested/"
      assert_includes entry_names, "projects/nested/beta.md"
      assert_includes entry_names, "projects/empty/"
    end
  end

  test "note download returns not found for missing note" do
    get backup_note_url(path: "projects/missing")

    assert_response :not_found
    assert_includes JSON.parse(response.body)["error"], "not found"
  end

  test "folder download returns not found for missing folder" do
    get backup_folder_url(path: "projects/missing")

    assert_response :not_found
    assert_includes JSON.parse(response.body)["error"], "not found"
  end

  test "note download rejects invalid paths" do
    get backup_note_url(path: "../outside")

    assert_response :unprocessable_entity
  end

  test "folder download rejects invalid paths" do
    get backup_folder_url(path: "../outside")

    assert_response :unprocessable_entity
  end

  test "note download returns forbidden when the backup cannot be read" do
    BackupService.any_instance.stubs(:backup_note).raises(Errno::EACCES)

    get backup_note_url(path: "projects/alpha")

    assert_response :forbidden
    assert_includes JSON.parse(response.body)["error"], "Permission denied"
  end

  test "folder download returns forbidden when the backup cannot be read" do
    BackupService.any_instance.stubs(:backup_folder).raises(Errno::EPERM)

    get backup_folder_url(path: "projects")

    assert_response :forbidden
    assert_includes JSON.parse(response.body)["error"], "Permission denied"
  end
end
