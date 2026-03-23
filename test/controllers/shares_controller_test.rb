# frozen_string_literal: true

require "test_helper"

class SharesControllerTest < ActionDispatch::IntegrationTest
  def setup
    setup_test_notes_dir
    create_test_note("shared-note.md", "# Shared Note\n\nContent")
  end

  def teardown
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
    assert_equal "shared-note.md", data["path"]
    assert_equal "Shared Note", data["title"]
    assert_equal true, data["created"]
    assert_equal share_snapshot_url(token: data["token"]), data["url"]

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
    assert_equal "Shared Note Refreshed", updated["title"]
    assert_includes File.read(@test_notes_dir.join(".frankmd/share_snapshots/#{original["token"]}.html")), "Version Two"
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
end
