# frozen_string_literal: true

require "test_helper"

class SharesControllerTest < ActionDispatch::IntegrationTest
  def setup
    setup_test_notes_dir
    create_test_note("shared-note.md", "# Shared Note\n\nContent")
  end

  def teardown
    WebMock.reset!
    WebMock.allow_net_connect!
    teardown_test_notes_dir
  end

  test "create returns token and url and writes snapshot files" do
    post shares_url,
      params: {
        path: "shared-note.md",
        title: "Shared Note",
        html: "<html><body><h1>Shared Note</h1></body></html>"
      },
      as: :json

    assert_response :created

    data = JSON.parse(response.body)
    assert data["token"].present?
    assert data["note_identifier"].present?
    assert data["note_content"].present?
    assert_equal "shared-note.md", data["path"]
    assert_equal "Shared Note", data["title"]
    assert_equal true, data["created"]
    assert_equal share_snapshot_url(token: data["token"]), data["url"]
    assert_includes File.read(@test_notes_dir.join("shared-note.md")), "lewismd_note_id: #{data["note_identifier"]}"

    assert @test_notes_dir.join(".frankmd/shares/#{data["token"]}.json").exist?
    assert @test_notes_dir.join(".frankmd/share_snapshots/#{data["token"]}.html").exist?
  end

  test "create reuses active token for same note" do
    post shares_url,
      params: {
        path: "shared-note.md",
        title: "Shared Note",
        html: "<html><body>Version One</body></html>"
      },
      as: :json
    original = JSON.parse(response.body)

    post shares_url,
      params: {
        path: "shared-note.md",
        title: "Shared Note Updated",
        html: "<html><body>Version Two</body></html>"
      },
      as: :json

    assert_response :success

    repeated = JSON.parse(response.body)
    assert_equal original["token"], repeated["token"]
    assert_equal false, repeated["created"]
    assert_equal original["note_identifier"], repeated["note_identifier"]
    assert_includes File.read(@test_notes_dir.join(".frankmd/share_snapshots/#{original["token"]}.html")), "Version One"
  end

  test "create returns 404 for missing note" do
    post shares_url,
      params: {
        path: "missing.md",
        title: "Missing",
        html: "<html><body>Missing</body></html>"
      },
      as: :json

    assert_response :not_found
  end

  test "create rejects invalid share request" do
    post shares_url,
      params: {
        path: "shared-note.md",
        title: "Shared Note",
        html: ""
      },
      as: :json

    assert_response :unprocessable_entity
  end

  test "create rejects share payloads that sanitize down to nothing" do
    post shares_url,
      params: {
        path: "shared-note.md",
        title: "Shared Note",
        html: '<html><body><article class="export-article"><script>alert("xss")</script></article></body></html>'
      },
      as: :json

    assert_response :unprocessable_entity
  end

  test "create returns the remote public url when remote publishing is configured" do
    configure_remote_share_backend
    stub_remote_capabilities
    stub_request(:post, "https://shares.example.com/api/v1/shares")
      .with do |request|
        body = JSON.parse(request.body)
        body["snapshot_document_html"].include?("export-article") &&
          body["shell_payload"]["title"] == "Shared Note" &&
          body["expires_at"].present?
      end
      .to_return(
        status: 201,
        body: {
          token: "remote-share-1234",
          public_url: "https://shares.example.com/s/remote-share-1234",
          title: "Shared Note",
          created_at: "2026-03-25T12:00:00Z",
          updated_at: "2026-03-25T12:00:00Z"
        }.to_json
      )

    post shares_url,
      params: {
        path: "shared-note.md",
        title: "Shared Note",
        html: '<html lang="en" data-theme="dark"><body><article class="export-article"><h1>Shared Snapshot</h1></article></body></html>'
      },
      as: :json

    assert_response :created

    data = JSON.parse(response.body)
    assert_equal "remote-share-1234", data["token"]
    assert_equal "https://shares.example.com/s/remote-share-1234", data["url"]
    assert_equal true, data["created"]
    assert data["expires_at"].present?
  end

  test "create surfaces the upstream remote share error message" do
    configure_remote_share_backend
    stub_remote_capabilities
    stub_request(:post, "https://shares.example.com/api/v1/shares")
      .to_return(status: 500, body: "")

    post shares_url,
      params: {
        path: "shared-note.md",
        title: "Shared Note",
        html: '<html lang="en" data-theme="dark"><body><article class="export-article"><h1>Shared Snapshot</h1></article></body></html>'
      },
      as: :json

    assert_response :unprocessable_entity

    data = JSON.parse(response.body)
    assert_includes data["error"], "Remote share API request failed with status 500"
    assert_includes data["error"], "share-api container logs"
  end

  test "lookup returns active share metadata for a note path" do
    post shares_url,
      params: {
        path: "shared-note.md",
        title: "Shared Note",
        html: "<html><body>Version One</body></html>"
      },
      as: :json
    created_share = JSON.parse(response.body)

    get share_status_url(path: "shared-note.md"), as: :json

    assert_response :success

    data = JSON.parse(response.body)
    assert_equal created_share["token"], data["token"]
    assert_equal "shared-note.md", data["path"]
    assert_equal share_snapshot_url(token: created_share["token"]), data["url"]
  end

  test "lookup returns the existing share after the note is renamed" do
    post shares_url,
      params: {
        path: "shared-note.md",
        title: "Shared Note",
        html: "<html><body>Version One</body></html>"
      },
      as: :json
    created_share = JSON.parse(response.body)

    post rename_note_url(path: "shared-note.md"),
      params: { new_path: "renamed/shared-note.md" },
      as: :json

    assert_response :success

    get share_status_url(path: "renamed/shared-note.md"), as: :json

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal created_share["token"], data["token"]
    assert_equal "renamed/shared-note.md", data["path"]
    assert_equal share_snapshot_url(token: created_share["token"]), data["url"]
  end

  test "lookup returns 404 when the note has no active share" do
    get share_status_url(path: "shared-note.md"), as: :json

    assert_response :not_found
  end

  test "update refreshes snapshot content while keeping token stable" do
    post shares_url,
      params: {
        path: "shared-note.md",
        title: "Shared Note",
        html: "<html><body>Version One</body></html>"
      },
      as: :json
    original = JSON.parse(response.body)

    patch update_share_url(path: "shared-note.md"),
      params: {
        title: "Shared Note Refreshed",
        html: "<html><body>Version Two</body></html>"
      },
      as: :json

    assert_response :success

    updated = JSON.parse(response.body)
    assert_equal original["token"], updated["token"]
    assert_equal original["note_identifier"], updated["note_identifier"]
    assert_equal "Shared Note Refreshed", updated["title"]
    assert_includes File.read(@test_notes_dir.join(".frankmd/share_snapshots/#{original["token"]}.html")), "Version Two"
  end

  test "remote update preserves the existing share url and marks the share stale on API failure" do
    configure_remote_share_backend
    stub_remote_capabilities
    stub_remote_create

    post shares_url,
      params: {
        path: "shared-note.md",
        title: "Shared Note",
        html: '<html lang="en" data-theme="dark"><body><article class="export-article"><p>Version One</p></article></body></html>'
      },
      as: :json
    created_share = JSON.parse(response.body)

    stub_remote_capabilities
    stub_request(:put, "https://shares.example.com/api/v1/shares/remote-share-1234")
      .to_return(status: 503, body: { error: "Remote share API timed out" }.to_json)

    patch update_share_url(path: "shared-note.md"),
      params: {
        title: "Shared Note",
        html: '<html lang="en" data-theme="dark"><body><article class="export-article"><p>Version Two</p></article></body></html>'
      },
      as: :json

    assert_response :unprocessable_entity

    get share_status_url(path: "shared-note.md"), as: :json

    assert_response :success

    data = JSON.parse(response.body)
    assert_equal created_share["token"], data["token"]
    assert_equal "https://shares.example.com/s/remote-share-1234", data["url"]
    assert_equal true, data["stale"]
    assert_equal "Remote share API timed out", data["last_error"]
  end

  test "destroy revokes active share" do
    post shares_url,
      params: {
        path: "shared-note.md",
        title: "Shared Note",
        html: "<html><body>Version One</body></html>"
      },
      as: :json
    created_share = JSON.parse(response.body)

    delete destroy_share_url(path: "shared-note.md"), as: :json

    assert_response :success

    data = JSON.parse(response.body)
    assert_equal true, data["revoked"]
    refute @test_notes_dir.join(".frankmd/share_snapshots/#{created_share["token"]}.html").exist?
  end

  test "destroy revokes the existing share after the note is renamed" do
    post shares_url,
      params: {
        path: "shared-note.md",
        title: "Shared Note",
        html: "<html><body>Version One</body></html>"
      },
      as: :json
    created_share = JSON.parse(response.body)

    post rename_note_url(path: "shared-note.md"),
      params: { new_path: "renamed/shared-note.md" },
      as: :json

    delete destroy_share_url(path: "renamed/shared-note.md"), as: :json

    assert_response :success
    refute @test_notes_dir.join(".frankmd/share_snapshots/#{created_share["token"]}.html").exist?
  end

  test "destroy revokes the remote share when remote publishing is configured" do
    configure_remote_share_backend
    stub_remote_capabilities
    stub_remote_create

    post shares_url,
      params: {
        path: "shared-note.md",
        title: "Shared Note",
        html: '<html lang="en" data-theme="dark"><body><article class="export-article"><p>Version One</p></article></body></html>'
      },
      as: :json

    stub_remote_capabilities
    stub_request(:delete, "https://shares.example.com/api/v1/shares/remote-share-1234")
      .to_return(status: 204, body: "")

    delete destroy_share_url(path: "shared-note.md"), as: :json

    assert_response :success
    assert_nil SharePublishers::RemoteShareProvider.new(base_path: @test_notes_dir).active_share_for("shared-note.md")
  end

  test "show renders the share shell even after note is deleted" do
    post shares_url,
      params: {
        path: "shared-note.md",
        title: "Shared Note",
        html: "<html><body><article>Shared Snapshot</article></body></html>"
      },
      as: :json
    created_share = JSON.parse(response.body)

    File.delete(@test_notes_dir.join("shared-note.md"))

    get share_snapshot_url(token: created_share["token"])

    assert_response :success
    assert_select "div[data-controller='share-view']"
    assert_includes response.body, share_snapshot_content_path(token: created_share["token"])
  end

  test "content serves stored snapshot html even after note is deleted" do
    post shares_url,
      params: {
        path: "shared-note.md",
        title: "Shared Note",
        html: "<html><body><article>Shared Snapshot</article></body></html>"
      },
      as: :json
    created_share = JSON.parse(response.body)

    File.delete(@test_notes_dir.join("shared-note.md"))

    get share_snapshot_content_url(token: created_share["token"])

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_includes response.body, "Shared Snapshot"
  end

  test "show returns 404 for revoked token" do
    post shares_url,
      params: {
        path: "shared-note.md",
        title: "Shared Note",
        html: "<html><body>Shared Snapshot</body></html>"
      },
      as: :json
    created_share = JSON.parse(response.body)

    delete destroy_share_url(path: "shared-note.md"), as: :json
    get share_snapshot_url(token: created_share["token"])

    assert_response :not_found
  end

  test "content returns 404 for revoked token" do
    post shares_url,
      params: {
        path: "shared-note.md",
        title: "Shared Note",
        html: "<html><body>Shared Snapshot</body></html>"
      },
      as: :json
    created_share = JSON.parse(response.body)

    delete destroy_share_url(path: "shared-note.md"), as: :json
    get share_snapshot_content_url(token: created_share["token"])

    assert_response :not_found
  end

  private

  def configure_remote_share_backend
    Config.new(base_path: @test_notes_dir).update(
      share_backend: "remote",
      share_remote_api_host: "shares.example.com",
      share_remote_api_port: 443,
      share_remote_public_base: "https://shares.example.com",
      share_remote_api_token: "token-123",
      share_remote_signing_secret: "signing-secret",
      share_remote_expiration_days: 14
    )
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def stub_remote_capabilities
    stub_request(:get, "https://shares.example.com/api/v1/capabilities")
      .to_return(status: 200, body: { api_version: "1" }.to_json)
  end

  def stub_remote_create
    stub_request(:post, "https://shares.example.com/api/v1/shares")
      .to_return(
        status: 201,
        body: {
          token: "remote-share-1234",
          public_url: "https://shares.example.com/s/remote-share-1234",
          title: "Shared Note",
          created_at: "2026-03-25T12:00:00Z",
          updated_at: "2026-03-25T12:00:00Z"
        }.to_json
      )
  end
end
