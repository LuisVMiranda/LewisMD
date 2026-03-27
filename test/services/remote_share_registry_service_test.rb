# frozen_string_literal: true

require "test_helper"

class RemoteShareRegistryServiceTest < ActiveSupport::TestCase
  def setup
    setup_test_notes_dir
    @service = RemoteShareRegistryService.new(base_path: @test_notes_dir)
  end

  def teardown
    teardown_test_notes_dir
  end

  test "save persists metadata and active_share_for returns it" do
    metadata = @service.save(remote_share_metadata)
    loaded = @service.active_share_for("shared-note.md", note_identifier: "note-123")

    assert_equal "remote-share-1234", metadata[:token]
    assert_equal "remote", loaded[:backend]
    assert_equal "note-123", loaded[:note_identifier]
    assert_equal "shared-note.md", loaded[:path]
    assert_equal "Shared Note", loaded[:title]
    assert_equal "https://shares.example.com/s/remote-share-1234", loaded[:url]
    assert_equal false, loaded[:stale]
    assert_equal "abc123", loaded[:content_hash]
    assert_equal "en", loaded[:locale]
    assert_equal "dark", loaded[:theme_id]
    assert_equal "2026-04-08T12:00:00Z", loaded[:expires_at]
    assert_equal 1, loaded[:asset_manifest].length
  end

  test "mark_stale preserves metadata and records the last error" do
    @service.save(remote_share_metadata)

    updated = @service.mark_stale(path: "shared-note.md", note_identifier: "note-123", error: "Remote share API timed out")

    assert_equal true, updated[:stale]
    assert_equal "Remote share API timed out", updated[:last_error]

    loaded = @service.active_share_for("shared-note.md", note_identifier: "note-123")
    assert_equal true, loaded[:stale]
    assert_equal "https://shares.example.com/s/remote-share-1234", loaded[:url]
  end

  test "delete removes stored metadata" do
    @service.save(remote_share_metadata)

    @service.delete(path: "shared-note.md", note_identifier: "note-123")

    assert_nil @service.active_share_for("shared-note.md", note_identifier: "note-123")
  end

  test "delete_all removes every stored registry entry" do
    @service.save(remote_share_metadata)
    @service.save(remote_share_metadata.merge(
      token: "remote-share-5678",
      note_identifier: "note-456",
      path: "other-note.md",
      url: "https://shares.example.com/s/remote-share-5678"
    ))

    deleted_count = @service.delete_all

    assert_equal 2, deleted_count
    assert_nil @service.active_share_for("shared-note.md", note_identifier: "note-123")
    assert_nil @service.active_share_for("other-note.md", note_identifier: "note-456")
  end

  test "active_share_for prunes expired metadata and returns nil" do
    @service.save(remote_share_metadata.merge(expires_at: "2026-03-25T11:59:00Z"))

    travel_to Time.zone.parse("2026-03-25 12:00:00 UTC") do
      assert_nil @service.active_share_for("shared-note.md", note_identifier: "note-123")
    end

    registry_dir = @test_notes_dir.join(RemoteShareRegistryService::REGISTRY_DIR)
    assert_empty Dir.glob(registry_dir.join("*.json"))
  end

  test "active_share_for ignores malformed metadata files" do
    registry_dir = @test_notes_dir.join(RemoteShareRegistryService::REGISTRY_DIR)
    FileUtils.mkdir_p(registry_dir)
    registry_dir.join("broken.json").write("{not valid json")

    assert_nil @service.active_share_for("shared-note.md", note_identifier: "note-123")
  end

  test "active_share_for resolves by note identifier after the note path changes" do
    @service.save(remote_share_metadata)

    loaded = @service.active_share_for("renamed/shared-note.md", note_identifier: "note-123")

    assert_equal "remote-share-1234", loaded[:token]
    assert_equal "renamed/shared-note.md", loaded[:path]
    assert @test_notes_dir.join(RemoteShareRegistryService::REGISTRY_DIR, "remote-share-1234.json").exist?
  end

  test "list_active_shares returns non-expired entries and prunes expired ones" do
    @service.save(remote_share_metadata)
    @service.save(remote_share_metadata.merge(
      token: "expired-share-123",
      note_identifier: "note-expired",
      path: "expired-note.md",
      url: "https://shares.example.com/s/expired-share-123",
      expires_at: "2026-03-25T11:59:00Z"
    ))

    travel_to Time.zone.parse("2026-03-25 12:00:00 UTC") do
      shares = @service.list_active_shares

      assert_equal 1, shares.length
      assert_equal "remote-share-1234", shares.first[:token]
    end

    refute @test_notes_dir.join(RemoteShareRegistryService::REGISTRY_DIR, "expired-share-123.json").exist?
  end

  private

  def remote_share_metadata
    {
      token: "remote-share-1234",
      note_identifier: "note-123",
      path: "shared-note.md",
      title: "Shared Note",
      url: "https://shares.example.com/s/remote-share-1234",
      created_at: "2026-03-25T12:00:00Z",
      updated_at: "2026-03-25T12:00:00Z",
      stale: false,
      last_error: nil,
      last_synced_at: "2026-03-25T12:00:00Z",
      content_hash: "abc123",
      locale: "en",
      theme_id: "dark",
      expires_at: "2026-04-08T12:00:00Z",
      asset_manifest: [
        {
          "source_url" => "data:image/png;base64,AAAA",
          "filename" => "embedded-asset.png",
          "mime_type" => "image/png",
          "byte_size" => 4,
          "sha256" => "deadbeef"
        }
      ],
      capabilities: { "api_version" => "1" }
    }
  end
end
