# frozen_string_literal: true

require "test_helper"

class ShareManagementControllerTest < ActionDispatch::IntegrationTest
  def setup
    setup_test_notes_dir
  end

  def teardown
    WebMock.reset!
    WebMock.allow_net_connect!
    teardown_test_notes_dir
  end

  test "show returns sanitized share settings without exposing secrets" do
    Config.new(base_path: @test_notes_dir).update(
      share_backend: "remote",
      share_remote_api_host: "shares.example.com",
      share_remote_api_token: "token-123",
      share_remote_signing_secret: "signing-secret"
    )

    get share_admin_url, as: :json

    assert_response :success
    data = JSON.parse(response.body)

    assert_equal "remote", data.dig("settings", "share_backend")
    assert_equal "shares.example.com", data.dig("settings", "share_remote_api_host")
    assert_equal true, data.dig("settings", "share_remote_api_token_configured")
    assert_equal true, data.dig("settings", "share_remote_signing_secret_configured")
    refute data["settings"].key?("share_remote_api_token")
    refute data["settings"].key?("share_remote_signing_secret")
  end

  test "update preserves configured secrets when blank secret fields are submitted" do
    config = Config.new(base_path: @test_notes_dir)
    config.update(
      share_backend: "remote",
      share_remote_api_host: "shares.example.com",
      share_remote_api_token: "token-123",
      share_remote_signing_secret: "signing-secret"
    )

    patch share_admin_url, params: {
      share_remote_api_host: "relay.example.com",
      share_remote_api_token: "",
      share_remote_signing_secret: ""
    }, as: :json

    assert_response :success
    reloaded = Config.new(base_path: @test_notes_dir)
    assert_equal "relay.example.com", reloaded.get("share_remote_api_host")
    assert_equal "token-123", reloaded.get("share_remote_api_token")
    assert_equal "signing-secret", reloaded.get("share_remote_signing_secret")
  end

  test "recheck returns remote status and admin capabilities" do
    configure_remote_share_backend
    stub_remote_capabilities
    stub_request(:get, "https://shares.example.com/api/v1/admin/status")
      .to_return(
        status: 200,
        body: {
          share_count: 3,
          storage_writable: true,
          checked_at: "2026-03-27T12:00:00Z"
        }.to_json
      )

    post recheck_share_admin_url, as: :json

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal "remote", data.dig("status", "backend")
    assert_equal true, data.dig("status", "reachable")
    assert_equal true, data.dig("status", "admin_enabled")
    assert_equal 3, data.dig("status", "remote_share_count")
    assert_equal true, data.dig("status", "storage_writable")
    assert_equal true, data.dig("status", "capabilities", "admin_status")
    assert_equal true, data.dig("status", "capabilities", "admin_bulk_delete")
  end

  test "destroy wipes remote shares and clears the local registry" do
    configure_remote_share_backend
    registry = RemoteShareRegistryService.new(base_path: @test_notes_dir)
    registry.save(
      token: "remote-share-1234",
      note_identifier: "note-123",
      path: "shared-note.md",
      title: "Shared Note",
      url: "https://shares.example.com/s/remote-share-1234",
      created_at: "2026-03-27T12:00:00Z",
      updated_at: "2026-03-27T12:00:00Z",
      stale: false,
      last_error: nil,
      last_synced_at: "2026-03-27T12:00:00Z",
      content_hash: "hash-1",
      locale: "en",
      theme_id: "dark",
      asset_manifest: [],
      expires_at: "2026-04-10T12:00:00Z",
      capabilities: { "api_version" => "1" }
    )

    stub_remote_capabilities
    stub_request(:delete, "https://shares.example.com/api/v1/admin/shares")
      .to_return(status: 200, body: {
        deleted: true,
        deleted_count: 5,
        cleanup: {
          removed_tokens: [ "remote-share-1234" ],
          orphan_snapshot_dirs_deleted: 1,
          orphan_asset_dirs_deleted: 0
        }
      }.to_json)
    stub_request(:get, "https://shares.example.com/api/v1/admin/status")
      .to_return(status: 200, body: { share_count: 0, storage_writable: true }.to_json)

    delete share_admin_url, as: :json

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal true, data["deleted"]
    assert_equal 5, data["deleted_count"]
    assert_equal 1, data.dig("cleanup", "orphan_snapshot_dirs_deleted")
    assert_nil registry.active_share_for("shared-note.md", note_identifier: "note-123")
  end

  test "destroy rejects bulk delete when remote sharing is disabled" do
    delete share_admin_url, as: :json

    assert_response :unprocessable_entity
    data = JSON.parse(response.body)
    assert_includes data["error"], "remote sharing"
  end

  private

  def configure_remote_share_backend
    Config.new(base_path: @test_notes_dir).update(
      share_backend: "remote",
      share_remote_api_host: "shares.example.com",
      share_remote_api_port: 443,
      share_remote_public_base: "https://shares.example.com",
      share_remote_api_token: "token-123",
      share_remote_signing_secret: "signing-secret"
    )
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def stub_remote_capabilities
    stub_request(:get, "https://shares.example.com/api/v1/capabilities")
      .to_return(
        status: 200,
        body: {
          api_version: "1",
          feature_flags: {
            asset_uploads: true,
            full_share_shell: true,
            admin_status: true,
            admin_bulk_delete: true
          }
        }.to_json
      )
  end
end
