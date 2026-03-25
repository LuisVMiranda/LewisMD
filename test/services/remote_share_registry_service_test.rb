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
    loaded = @service.active_share_for("shared-note.md")

    assert_equal "remote-share-1234", metadata[:token]
    assert_equal "remote", loaded[:backend]
    assert_equal "shared-note.md", loaded[:path]
    assert_equal "Shared Note", loaded[:title]
    assert_equal "https://shares.example.com/s/remote-share-1234", loaded[:url]
    assert_equal false, loaded[:stale]
    assert_equal "abc123", loaded[:content_hash]
    assert_equal "en", loaded[:locale]
    assert_equal "dark", loaded[:theme_id]
    assert_equal 1, loaded[:asset_manifest].length
  end

  test "mark_stale preserves metadata and records the last error" do
    @service.save(remote_share_metadata)

    updated = @service.mark_stale(path: "shared-note.md", error: "Remote share API timed out")

    assert_equal true, updated[:stale]
    assert_equal "Remote share API timed out", updated[:last_error]

    loaded = @service.active_share_for("shared-note.md")
    assert_equal true, loaded[:stale]
    assert_equal "https://shares.example.com/s/remote-share-1234", loaded[:url]
  end

  test "delete removes stored metadata" do
    @service.save(remote_share_metadata)

    @service.delete(path: "shared-note.md")

    assert_nil @service.active_share_for("shared-note.md")
  end

  test "active_share_for ignores malformed metadata files" do
    registry_dir = @test_notes_dir.join(RemoteShareRegistryService::REGISTRY_DIR)
    FileUtils.mkdir_p(registry_dir)
    registry_dir.join("broken.json").write("{not valid json")

    assert_nil @service.active_share_for("shared-note.md")
  end

  private

  def remote_share_metadata
    {
      token: "remote-share-1234",
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
