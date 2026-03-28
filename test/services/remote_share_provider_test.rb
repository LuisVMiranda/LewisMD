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
      share_remote_signing_secret: "signing-secret",
      share_remote_expiration_days: 14
    )
    @registry = RemoteShareRegistryService.new(base_path: @test_notes_dir)
  end

  def teardown
    teardown_test_notes_dir
  end

  test "create_or_find publishes a remote share and persists registry metadata" do
    travel_to Time.zone.parse("2026-03-25 12:00:00 UTC") do
      client = mock("remote-share-client")
      client.expects(:create_share).with do |payload|
        assert_equal "Shared Note", payload[:title]
        assert_equal "note-123", payload[:note_identifier]
        assert_equal 2, payload[:snapshot_version]
        assert_equal 1, payload[:shell_version]
        assert_equal "Shared Note", payload.dig(:shell_payload, :title)
        assert_equal "dark", payload[:theme_id]
        assert_equal "2026-04-08T12:00:00Z", payload[:expires_at]
        assert_equal 1, payload[:assets].length
        assert_equal "asset-1", payload[:assets].first[:upload_reference]
        assert_includes payload[:html_fragment], 'src="asset://asset-1"'
        assert_includes payload[:snapshot_document_html], 'src="asset://asset-1"'
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
      client.stubs(:last_capabilities).returns({ "api_version" => "1", "feature_flags" => { "full_share_shell" => true } })

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
      assert_equal "2026-04-08T12:00:00Z", share[:expires_at]
      assert_equal "https://shares.example.com/s/remote-share-1234", @registry.active_share_for("shared-note.md", note_identifier: "note-123")[:url]
    end
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

  test "create_or_find republishes when the stored remote share has expired" do
    @registry.save(existing_share_metadata.merge(expires_at: "2026-03-25T11:59:00Z"))

    travel_to Time.zone.parse("2026-03-25 12:00:00 UTC") do
      client = mock("remote-share-client")
      client.expects(:create_share).with do |payload|
        assert_equal "2026-04-08T12:00:00Z", payload[:expires_at]
        true
      end.returns(
        {
          token: "remote-share-5678",
          url: "https://shares.example.com/s/remote-share-5678",
          title: "Shared Note",
          created_at: "2026-03-25T12:00:00Z",
          updated_at: "2026-03-25T12:00:00Z",
          expires_at: "2026-04-08T12:00:00Z"
        }
      )
      client.stubs(:last_capabilities).returns({ "api_version" => "1", "feature_flags" => { "full_share_shell" => true } })

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
      assert_equal "remote-share-5678", share[:token]
      assert_equal "remote-share-5678", @registry.active_share_for("shared-note.md", note_identifier: "note-123")[:token]
    end
  end

  test "create_or_find clamps the requested expiry to the remote maximum" do
    travel_to Time.zone.parse("2026-03-25 12:00:00 UTC") do
      client = mock("remote-share-client")
      client.stubs(:last_capabilities).returns(nil)
      client.expects(:fetch_capabilities).returns({ "api_version" => "1", "max_expiration_days" => 7 })
      client.expects(:create_share).with do |payload|
        assert_equal "2026-04-01T12:00:00Z", payload[:expires_at]
        true
      end.returns(
        {
          token: "remote-share-7777",
          url: "https://shares.example.com/s/remote-share-7777",
          title: "Shared Note",
          created_at: "2026-03-25T12:00:00Z",
          updated_at: "2026-03-25T12:00:00Z",
          expires_at: "2026-04-01T12:00:00Z"
        }
      )

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

      assert_equal "2026-04-01T12:00:00Z", share[:expires_at]
    end
  end

  test "refresh marks the remote share stale when the remote API fails" do
    @registry.save(existing_share_metadata)
    client = mock("remote-share-client")
    client.stubs(:last_capabilities).returns({})
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

    stale_share = @registry.active_share_for("shared-note.md", note_identifier: "note-123")
    assert_equal true, stale_share[:stale]
    assert_equal "Remote share API timed out", stale_share[:last_error]
    assert_equal "https://shares.example.com/s/remote-share-1234", stale_share[:url]
  end

  test "refresh republishes the share when the remote API reports that it is already gone" do
    @registry.save(existing_share_metadata)
    client = mock("remote-share-client")
    client.expects(:update_share).raises(RemoteShareClient::RequestError.new("Share not found", status: 404))
    client.expects(:create_share).with do |payload|
      assert_equal "note-123", payload[:note_identifier]
      assert_equal "shared-note.md", payload[:path]
      true
    end.returns(
      {
        token: "remote-share-5678",
        url: "https://shares.example.com/s/remote-share-5678",
        title: "Shared Note",
        created_at: "2026-03-26T12:00:00Z",
        updated_at: "2026-03-26T12:00:00Z"
      }
    )
    client.stubs(:last_capabilities).returns({ "api_version" => "1", "feature_flags" => { "full_share_shell" => true } })

    provider = SharePublishers::RemoteShareProvider.new(
      base_path: @test_notes_dir,
      config: @config,
      registry: @registry,
      client: client
    )

    share = provider.refresh(
      path: "shared-note.md",
      title: "Shared Note",
      snapshot_html: "<html><body>Ignored</body></html>",
      share_payload: share_payload
    )

    assert_equal "remote-share-5678", share[:token]
    assert_equal false, share[:stale]
    assert_nil share[:last_error]
    assert_nil @registry.find_by_token("remote-share-1234")
    assert_equal "remote-share-5678", @registry.active_share_for("shared-note.md", note_identifier: "note-123")[:token]
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

    share = provider.revoke(path: "shared-note.md", note_identifier: "note-123")

    assert_equal "remote-share-1234", share[:token]
    assert_nil @registry.active_share_for("shared-note.md", note_identifier: "note-123")
  end

  test "revoke clears the local registry entry when the remote API reports that it is already gone" do
    @registry.save(existing_share_metadata)
    client = mock("remote-share-client")
    client.expects(:revoke_share).with(token: "remote-share-1234")
      .raises(RemoteShareClient::RequestError.new("Share not found", status: 404))

    provider = SharePublishers::RemoteShareProvider.new(
      base_path: @test_notes_dir,
      config: @config,
      registry: @registry,
      client: client
    )

    share = provider.revoke(path: "shared-note.md", note_identifier: "note-123")

    assert_equal "remote-share-1234", share[:token]
    assert_nil @registry.active_share_for("shared-note.md", note_identifier: "note-123")
  end

  private

  def share_payload
    {
      source: "preview",
      note_identifier: "note-123",
      path: "shared-note.md",
      title: "Shared Note",
      html_fragment: '<p><img src="data:image/png;base64,aGVsbG8=" alt="Inline image"></p>',
      plain_text: "Hello",
      theme_id: "dark",
      locale: "en",
      content_hash: "abc123",
      snapshot_version: 2,
      shell_version: 1,
      snapshot_document_html: '<!DOCTYPE html><html lang="en" data-theme="dark"><head><style>.export-shell { padding: 1rem; }</style></head><body><main class="export-shell"><article class="export-article"><p><img src="data:image/png;base64,aGVsbG8=" alt="Inline image"></p></article></main></body></html>',
      shell_payload: {
        title: "Shared Note",
        locale: "en",
        theme_id: "dark",
        display: {
          default_zoom: 100,
          default_width: 72,
          font_family: "default"
        }
      },
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
      asset_manifest: [],
      expires_at: "2026-04-08T12:00:00Z",
      capabilities: { "api_version" => "1" }
    }
  end
end
