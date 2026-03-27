# frozen_string_literal: true

require "test_helper"

class PublishedSharesOverviewServiceTest < ActiveSupport::TestCase
  def setup
    setup_test_notes_dir
    @share_service = ShareService.new(base_path: @test_notes_dir)
    @remote_registry = RemoteShareRegistryService.new(base_path: @test_notes_dir)
    @identity_service = NoteShareIdentityService.new(base_path: @test_notes_dir)
    @service = PublishedSharesOverviewService.new(base_path: @test_notes_dir)
  end

  def teardown
    teardown_test_notes_dir
  end

  test "list resolves renamed local and remote shares by note identifier" do
    create_test_note("original.md", "# Original")
    identity = @identity_service.ensure_identity!("original.md")

    local_share = @share_service.create_or_find(
      path: "original.md",
      title: "Original",
      snapshot_html: "<html><body>Original</body></html>",
      note_identifier: identity[:note_identifier]
    )
    @remote_registry.save(
      token: "remote-share-1234",
      note_identifier: identity[:note_identifier],
      path: "original.md",
      title: "Original",
      url: "https://shares.example.com/s/remote-share-1234",
      created_at: "2026-03-27T12:00:00Z",
      updated_at: "2026-03-27T12:00:00Z",
      stale: false,
      last_error: nil,
      last_synced_at: "2026-03-27T12:00:00Z",
      content_hash: "hash-1",
      locale: "en",
      theme_id: "default",
      asset_manifest: [],
      expires_at: "2026-04-10T12:00:00Z",
      capabilities: {}
    )

    assert Note.find("original.md").rename("Renamed/final-name.md")

    rows = @service.list
    local_row = rows.find { |row| row[:token] == local_share[:token] }
    remote_row = rows.find { |row| row[:token] == "remote-share-1234" }

    assert_equal "Renamed/final-name.md", local_row[:path]
    assert_equal "final-name", local_row[:title]
    assert_equal false, local_row[:missing_locally]

    assert_equal "Renamed/final-name.md", remote_row[:path]
    assert_equal "final-name", remote_row[:title]
    assert_equal false, remote_row[:missing_locally]
  end

  test "list keeps missing local notes visible with stored metadata" do
    @remote_registry.save(
      token: "remote-share-missing",
      note_identifier: "missing-note-123",
      path: "missing/deleted-note.md",
      title: "Deleted Note",
      url: "https://shares.example.com/s/remote-share-missing",
      created_at: "2026-03-27T12:00:00Z",
      updated_at: "2026-03-27T12:00:00Z",
      stale: true,
      last_error: "Remote snapshot missing",
      last_synced_at: "2026-03-27T12:00:00Z",
      content_hash: "hash-1",
      locale: "en",
      theme_id: "default",
      asset_manifest: [],
      expires_at: "2026-04-10T12:00:00Z",
      capabilities: {}
    )

    row = @service.list.find { |item| item[:token] == "remote-share-missing" }

    assert_equal "missing/deleted-note.md", row[:path]
    assert_equal "Deleted Note", row[:title]
    assert_equal true, row[:missing_locally]
    assert_equal true, row[:stale]
    assert_equal "Remote snapshot missing", row[:last_error]
  end

  test "list marks local shares stale when the snapshot file is missing" do
    create_test_note("shared-note.md", "# Shared")
    identity = @identity_service.ensure_identity!("shared-note.md")
    share = @share_service.create_or_find(
      path: "shared-note.md",
      title: "Shared Note",
      snapshot_html: "<html><body>Shared</body></html>",
      note_identifier: identity[:note_identifier]
    )
    @test_notes_dir.join(".frankmd/share_snapshots/#{share[:token]}.html").delete

    row = @service.list.find { |item| item[:token] == share[:token] }

    assert_equal "local", row[:backend]
    assert_equal true, row[:stale]
    assert_equal true, row[:snapshot_missing]
    assert_equal "/s/#{share[:token]}", row[:url]
  end
end
