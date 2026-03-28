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
      share_remote_verify_tls: false,
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
    assert_equal true, reloaded.get("share_remote_verify_tls")
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
    assert_equal 30, data.dig("status", "local_default_expiration_days")
    assert_equal 365, data.dig("status", "remote_max_expiration_days")
    assert data.dig("status", "warnings").any? { |warning| warning["id"] == "cloudflare_edge_checklist" }
    refute data.dig("status", "warnings").any? { |warning| warning["id"] == "payload_limit_inconsistent" }
  end

  test "show surfaces legacy tls and expiry mismatch warnings" do
    configure_remote_share_backend
    Config.new(base_path: @test_notes_dir).update(
      share_remote_verify_tls: false,
      share_remote_expiration_days: 45
    )
    stub_request(:get, "https://shares.example.com/api/v1/capabilities")
      .to_return(
        status: 200,
        body: {
          api_version: "1",
          max_expiration_days: 7,
          max_payload_bytes: 200_000,
          max_asset_bytes: 5_000_000,
          max_asset_count: 16,
          feature_flags: {
            asset_uploads: true,
            full_share_shell: true
          }
        }.to_json
      )

    get share_admin_url, as: :json

    assert_response :success
    data = JSON.parse(response.body)
    warning_ids = data.dig("status", "warnings").map { |warning| warning["id"] }

    assert_includes warning_ids, "legacy_insecure_tls_config"
    assert_includes warning_ids, "remote_admin_features_unavailable"
    assert_includes warning_ids, "remote_expiration_clamped"
    assert_includes warning_ids, "payload_limit_inconsistent"
    assert_equal 45, data.dig("status", "local_default_expiration_days")
    assert_equal 7, data.dig("status", "remote_max_expiration_days")
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

  test "published returns normalized published shares with current note names and missing local rows" do
    create_test_note("drafts/original.md", "# Original")
    identity = NoteShareIdentityService.new(base_path: @test_notes_dir).ensure_identity!("drafts/original.md")
    share_service = ShareService.new(base_path: @test_notes_dir)
    local_share = share_service.create_or_find(
      path: "drafts/original.md",
      title: "Original",
      snapshot_html: "<html><body>Original</body></html>",
      note_identifier: identity[:note_identifier]
    )
    assert Note.find("drafts/original.md").rename("published/final-name.md")

    RemoteShareRegistryService.new(base_path: @test_notes_dir).save(
      token: "remote-stale-123",
      note_identifier: "missing-note-123",
      path: "missing/deleted-note.md",
      title: "Deleted Note",
      url: "https://shares.example.com/s/remote-stale-123",
      created_at: "2026-03-27T12:00:00Z",
      updated_at: "2026-03-27T12:00:00Z",
      stale: true,
      last_error: "Remote share missing",
      last_synced_at: "2026-03-27T12:00:00Z",
      content_hash: "hash-1",
      locale: "en",
      theme_id: "default",
      asset_manifest: [],
      expires_at: "2026-04-10T12:00:00Z",
      capabilities: {}
    )

    get published_share_admin_url, as: :json

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 2, data["published_shares"].length

    local_row = data["published_shares"].find { |row| row["token"] == local_share[:token] }
    remote_row = data["published_shares"].find { |row| row["token"] == "remote-stale-123" }

    assert_equal "published/final-name.md", local_row["path"]
    assert_equal "final-name", local_row["title"]
    assert_equal false, local_row["missing_locally"]
    assert_equal "/s/#{local_share[:token]}", local_row["url"]

    assert_equal "missing/deleted-note.md", remote_row["path"]
    assert_equal "Deleted Note", remote_row["title"]
    assert_equal true, remote_row["missing_locally"]
    assert_equal true, remote_row["stale"]
  end

  test "destroy_published revokes a local published note by token" do
    create_test_note("drafts/local-share.md", "# Local")
    identity = NoteShareIdentityService.new(base_path: @test_notes_dir).ensure_identity!("drafts/local-share.md")
    share_service = ShareService.new(base_path: @test_notes_dir)
    share = share_service.create_or_find(
      path: "drafts/local-share.md",
      title: "Local",
      snapshot_html: "<html><body>Local</body></html>",
      note_identifier: identity[:note_identifier]
    )

    delete destroy_published_share_admin_url(token: share[:token]), as: :json

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal true, data["deleted"]
    assert_equal "local", data["backend"]
    assert_nil share_service.metadata_for_token(share[:token])
  end

  test "destroy_published clears stale remote registry entries when the remote share is already gone" do
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
      stale: true,
      last_error: "Remote share missing",
      last_synced_at: "2026-03-27T12:00:00Z",
      content_hash: "hash-1",
      locale: "en",
      theme_id: "dark",
      asset_manifest: [],
      expires_at: "2026-04-10T12:00:00Z",
      capabilities: { "api_version" => "1" }
    )

    stub_remote_capabilities
    stub_request(:delete, "https://shares.example.com/api/v1/shares/remote-share-1234")
      .to_return(status: 404, body: { error: "Share not found" }.to_json)

    delete destroy_published_share_admin_url(token: "remote-share-1234"), as: :json

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal true, data["deleted"]
    assert_equal true, data["remote_missing"]
    assert_nil registry.find_by_token("remote-share-1234")
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
          max_expiration_days: 365,
          max_payload_bytes: 8_000_000,
          max_asset_bytes: 5_000_000,
          max_asset_count: 16,
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
