# frozen_string_literal: true

require "test_helper"

class RemoteShareProviderTest < ActiveSupport::TestCase
  def setup
    setup_test_notes_dir
    @config = Config.new(base_path: @test_notes_dir)
    @config.update(
      share_backend: "remote",
      share_remote_api_host: "shares.example.com",
      share_remote_api_port: 443,
      share_remote_public_base: "https://shares.example.com",
      share_remote_api_token: "token-123",
      share_remote_signing_secret: "signing-secret"
    )
    @registry = RemoteShareRegistryService.new(base_path: @test_notes_dir)
  end

  def teardown
    teardown_test_notes_dir
  end

  test "create_or_find publishes a remote share and persists registry metadata" do
    client = mock("remote-share-client")
    client.expects(:create_share).with do |payload|
      assert_equal "Shared Note", payload[:title]
      assert_equal 1, payload[:assets].length
      assert_equal "asset-1", payload[:assets].first[:upload_reference]
      assert_includes payload[:html_fragment], 'src="asset://asset-1"'
      true
    end.returns(
      {
        token: "remote-share-1234",
        url: "https://shares.example.com/s/remote-share-1234",
        title: "Shared Note",
        created_at: "2026-03-25T12:00:00Z",
        updated_at: "2026-03-25T12:00:00Z"
      }
    )
    client.stubs(:last_capabilities).returns({ "api_version" => "1" })

    provider = SharePublishers::RemoteShareProvider.new(
      base_path: @test_notes_dir,
      config: @config,
      registry: @registry,
      client: client
    )

    share = provider.create_or_find(
      path: "shared-note.md",
      title: "Shared Note",
      snapshot_html: "<html><body>Ignored</body></html>",
      share_payload: share_payload
    )

    assert_equal true, share[:created]
    assert_equal "remote-share-1234", share[:token]
    assert_equal false, share[:stale]
    assert_equal "https://shares.example.com/s/remote-share-1234", @registry.active_share_for("shared-note.md")[:url]
  end

  test "create_or_find reuses an existing remote registry entry" do
    @registry.save(existing_share_metadata)
    client = mock("remote-share-client")
    client.expects(:create_share).never

    provider = SharePublishers::RemoteShareProvider.new(
      base_path: @test_notes_dir,
      config: @config,
      registry: @registry,
      client: client
    )

    share = provider.create_or_find(
      path: "shared-note.md",
      title: "Shared Note",
      snapshot_html: "<html><body>Ignored</body></html>",
      share_payload: share_payload
    )

    assert_equal false, share[:created]
    assert_equal "remote-share-1234", share[:token]
  end

  test "refresh marks the remote share stale when the remote API fails" do
    @registry.save(existing_share_metadata)
    client = mock("remote-share-client")
    client.expects(:update_share).raises(RemoteShareClient::RequestError.new("Remote share API timed out", status: 503))

    provider = SharePublishers::RemoteShareProvider.new(
      base_path: @test_notes_dir,
      config: @config,
      registry: @registry,
      client: client
    )

    error = assert_raises(ShareService::InvalidShareError) do
      provider.refresh(
        path: "shared-note.md",
        title: "Shared Note",
        snapshot_html: "<html><body>Ignored</body></html>",
        share_payload: share_payload
      )
    end

    assert_includes error.message, "timed out"

    stale_share = @registry.active_share_for("shared-note.md")
    assert_equal true, stale_share[:stale]
    assert_equal "Remote share API timed out", stale_share[:last_error]
    assert_equal "https://shares.example.com/s/remote-share-1234", stale_share[:url]
  end

  test "revoke deletes the stored registry entry after the remote API succeeds" do
    @registry.save(existing_share_metadata)
    client = mock("remote-share-client")
    client.expects(:revoke_share).with(token: "remote-share-1234").returns(true)

    provider = SharePublishers::RemoteShareProvider.new(
      base_path: @test_notes_dir,
      config: @config,
      registry: @registry,
      client: client
    )

    share = provider.revoke(path: "shared-note.md")

    assert_equal "remote-share-1234", share[:token]
    assert_nil @registry.active_share_for("shared-note.md")
  end

  private

  def share_payload
    {
      source: "preview",
      note_identifier: "shared-note.md",
      path: "shared-note.md",
      title: "Shared Note",
      html_fragment: '<p><img src="data:image/png;base64,aGVsbG8=" alt="Inline image"></p>',
      plain_text: "Hello",
      theme_id: "dark",
      locale: "en",
      content_hash: "abc123",
      asset_manifest: [
        {
          source_url: "data:image/png;base64,aGVsbG8=",
          source_type: "data_uri",
          filename: "embedded-asset.png",
          mime_type: "image/png",
          byte_size: 5,
          sha256: Digest::SHA256.hexdigest("hello"),
          upload_reference: "asset-1"
        }
      ],
      assets: [
        {
          source_url: "data:image/png;base64,aGVsbG8=",
          source_type: "data_uri",
          upload_reference: "asset-1",
          filename: "embedded-asset.png",
          mime_type: "image/png",
          byte_size: 5,
          sha256: Digest::SHA256.hexdigest("hello"),
          content_base64: "aGVsbG8="
        }
      ]
    }
  end

  def existing_share_metadata
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
      asset_manifest: [],
      capabilities: { "api_version" => "1" }
    }
  end
end
