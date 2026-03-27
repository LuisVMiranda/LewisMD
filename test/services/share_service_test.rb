# frozen_string_literal: true

require "test_helper"

class ShareServiceTest < ActiveSupport::TestCase
  def setup
    setup_test_notes_dir
    @service = ShareService.new(base_path: @test_notes_dir)
    @note_identifier = SecureRandom.uuid
    create_test_note("shared-note.md", "# Shared\n\nContent")
  end

  def teardown
    teardown_test_notes_dir
  end

  test "create_or_find writes metadata and snapshot files" do
    share = @service.create_or_find(
      path: "shared-note.md",
      title: "Shared Note",
      snapshot_html: "<html><body><h1>Shared</h1></body></html>",
      note_identifier: @note_identifier
    )

    assert_equal true, share[:created]
    assert @test_notes_dir.join(".frankmd/shares/#{share[:token]}.json").exist?
    assert @test_notes_dir.join(".frankmd/share_snapshots/#{share[:token]}.html").exist?

    metadata = JSON.parse(File.read(@test_notes_dir.join(".frankmd/shares/#{share[:token]}.json")))
    assert_equal @note_identifier, metadata["note_identifier"]
    assert_equal "shared-note.md", metadata["path"]
    assert_equal "Shared Note", metadata["title"]
    assert_equal false, metadata["revoked"]
  end

  test "create_or_find reuses active token without overwriting snapshot" do
    original = @service.create_or_find(
      path: "shared-note.md",
      title: "Shared Note",
      snapshot_html: "<html><body>Version One</body></html>",
      note_identifier: @note_identifier
    )

    repeated = @service.create_or_find(
      path: "shared-note.md",
      title: "Shared Note Updated",
      snapshot_html: "<html><body>Version Two</body></html>",
      note_identifier: @note_identifier
    )

    assert_equal original[:token], repeated[:token]
    assert_equal false, repeated[:created]
    assert_includes File.read(@test_notes_dir.join(".frankmd/share_snapshots/#{original[:token]}.html")), "Version One"
    refute_includes File.read(@test_notes_dir.join(".frankmd/share_snapshots/#{original[:token]}.html")), "Version Two"
  end

  test "refresh updates snapshot and keeps token stable" do
    original = @service.create_or_find(
      path: "shared-note.md",
      title: "Shared Note",
      snapshot_html: "<html><body>Version One</body></html>",
      note_identifier: @note_identifier
    )

    refreshed = @service.refresh(
      path: "shared-note.md",
      title: "Shared Note Refreshed",
      snapshot_html: "<html><body>Version Two</body></html>",
      note_identifier: @note_identifier
    )

    assert_equal original[:token], refreshed[:token]
    assert_equal "Shared Note Refreshed", refreshed[:title]
    assert_includes File.read(@test_notes_dir.join(".frankmd/share_snapshots/#{original[:token]}.html")), "Version Two"
  end

  test "revoke marks share revoked and removes snapshot file" do
    share = @service.create_or_find(
      path: "shared-note.md",
      title: "Shared Note",
      snapshot_html: "<html><body>Version One</body></html>",
      note_identifier: @note_identifier
    )

    @service.revoke(path: "shared-note.md", note_identifier: @note_identifier)

    metadata = JSON.parse(File.read(@test_notes_dir.join(".frankmd/shares/#{share[:token]}.json")))
    assert_equal true, metadata["revoked"]
    refute @test_notes_dir.join(".frankmd/share_snapshots/#{share[:token]}.html").exist?
  end

  test "find_by_token returns nil for revoked share" do
    share = @service.create_or_find(
      path: "shared-note.md",
      title: "Shared Note",
      snapshot_html: "<html><body>Version One</body></html>",
      note_identifier: @note_identifier
    )
    @service.revoke(path: "shared-note.md", note_identifier: @note_identifier)

    assert_nil @service.find_by_token(share[:token])
  end

  test "create_or_find repairs active share when snapshot file is missing" do
    share = @service.create_or_find(
      path: "shared-note.md",
      title: "Shared Note",
      snapshot_html: "<html><body>Version One</body></html>",
      note_identifier: @note_identifier
    )
    @test_notes_dir.join(".frankmd/share_snapshots/#{share[:token]}.html").delete

    repaired = @service.create_or_find(
      path: "shared-note.md",
      title: "Shared Note",
      snapshot_html: "<html><body>Version Two</body></html>",
      note_identifier: @note_identifier
    )

    assert_equal share[:token], repaired[:token]
    assert_equal false, repaired[:created]
    assert_includes File.read(@test_notes_dir.join(".frankmd/share_snapshots/#{share[:token]}.html")), "Version Two"
  end

  test "create_or_find rejects non-markdown paths" do
    assert_raises(ShareService::InvalidShareError) do
      @service.create_or_find(
        path: ".fed",
        title: "Config",
        snapshot_html: "<html><body>Invalid</body></html>",
        note_identifier: @note_identifier
      )
    end
  end

  test "active_share_for resolves by note identifier after the note path changes" do
    share = @service.create_or_find(
      path: "shared-note.md",
      title: "Shared Note",
      snapshot_html: "<html><body>Version One</body></html>",
      note_identifier: @note_identifier
    )

    resolved = @service.active_share_for("renamed/shared-note.md", note_identifier: @note_identifier, require_snapshot: false)

    assert_equal share[:token], resolved[:token]
    assert_equal "renamed/shared-note.md", resolved[:path]
    metadata = JSON.parse(File.read(@test_notes_dir.join(".frankmd/shares/#{share[:token]}.json")))
    assert_equal "renamed/shared-note.md", metadata["path"]
  end
end
