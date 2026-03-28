# frozen_string_literal: true

require "test_helper"
require "base64"
require Rails.root.join("services/share_api/lib/share_api/storage")

class ShareApiStorageTest < ActiveSupport::TestCase
  def setup
    @storage_path = Rails.root.join("tmp", "share_api_storage_test_#{SecureRandom.hex(6)}")
    FileUtils.mkdir_p(@storage_path)
    @storage = ShareAPI::Storage.new(
      storage_path: @storage_path,
      max_asset_bytes: 5_000_000,
      max_asset_count: 16,
      max_expiration_days: 50_000
    )
  end

  def teardown
    FileUtils.rm_rf(@storage_path)
  end

  test "fetch_share prunes expired shares from disk" do
    _created, share = @storage.upsert_share(
      identity_key: identity_key,
      share: share_attributes(expires_at: "2026-03-25T11:59:00Z"),
      fragment_html: "<p>Expired share</p>",
      snapshot_document_html: "<!doctype html><html><body><p>Expired share</p></body></html>"
    )

    travel_to Time.zone.parse("2026-03-25 12:00:00 UTC") do
      assert_raises(ShareAPI::Storage::NotFoundError) do
        @storage.fetch_share(share.fetch("token"))
      end
    end

    refute @storage_path.join("shares", "#{share.fetch("token")}.json").exist?
    refute @storage_path.join("snapshots", share.fetch("token")).exist?
    refute @storage_path.join("path-index", "#{Digest::SHA256.hexdigest(identity_key)}.json").exist?
  end

  test "sweep_expired_shares removes expired shares, assets, and indexes" do
    expired_asset = asset_payload(upload_reference: "asset-1", filename: "expired.png", content: "expired")
    _created, expired_share = @storage.upsert_share(
      identity_key: identity_key,
      share: share_attributes(
        content_hash: "hash-expired",
        expires_at: "2026-03-25T11:00:00Z",
        asset_manifest: [ asset_manifest_entry(expired_asset) ]
      ),
      fragment_html: '<p><img src="asset://asset-1" alt="Expired"></p>',
      snapshot_document_html: '<!doctype html><html><body><p><img src="asset://asset-1" alt="Expired"></p></body></html>',
      assets: [ expired_asset ]
    )
    _created, active_share = @storage.upsert_share(
      identity_key: "local-machine:notes/active-note.md",
      share: share_attributes(
        path: "notes/active-note.md",
        note_identifier: "notes/active-note.md",
        title: "Active Note",
        content_hash: "hash-active",
        expires_at: "2099-03-26T12:00:00Z"
      ),
      fragment_html: "<p>Active share</p>",
      snapshot_document_html: "<!doctype html><html><body><p>Active share</p></body></html>"
    )

    removed_tokens = @storage.sweep_expired_shares!(now: Time.iso8601("2026-03-25T12:00:00Z"))

    assert_equal [ expired_share.fetch("token") ], removed_tokens
    assert_equal active_share.fetch("token"), @storage.fetch_share(active_share.fetch("token")).fetch("token")
    refute @storage_path.join("shares", "#{expired_share.fetch("token")}.json").exist?
    refute @storage_path.join("snapshots", expired_share.fetch("token")).exist?
    refute @storage_path.join("assets", expired_share.fetch("token")).exist?
    refute @storage_path.join("path-index", "#{Digest::SHA256.hexdigest(identity_key)}.json").exist?
  end

  test "upsert_share creates a new token when the existing identity has expired" do
    _created, expired_share = @storage.upsert_share(
      identity_key: identity_key,
      share: share_attributes(expires_at: "2026-03-25T11:59:00Z"),
      fragment_html: "<p>First version</p>",
      snapshot_document_html: "<!doctype html><html><body><p>First version</p></body></html>"
    )

    travel_to Time.zone.parse("2026-03-25 12:00:00 UTC") do
      created, replacement_share = @storage.upsert_share(
        identity_key: identity_key,
        share: share_attributes(
          content_hash: "hash-2",
          expires_at: "2026-03-26T12:00:00Z"
        ),
        fragment_html: "<p>Second version</p>",
        snapshot_document_html: "<!doctype html><html><body><p>Second version</p></body></html>"
      )

      assert_equal true, created
      refute_equal expired_share.fetch("token"), replacement_share.fetch("token")
    end
  end

  test "write_sweeper_report persists janitor state under the storage root" do
    @storage.write_sweeper_report!(
      checked_at: "2026-03-25T12:34:56Z",
      status: "ok",
      removed_tokens: [ "token-1", "token-2" ]
    )

    report = JSON.parse(@storage_path.join("maintenance", "sweeper-state.json").read)

    assert_equal "2026-03-25T12:34:56Z", report.fetch("checked_at")
    assert_equal "ok", report.fetch("status")
    assert_equal 2, report.fetch("removed_count")
    assert_equal [ "token-1", "token-2" ], report.fetch("removed_tokens")
  end

  test "verify_write_access creates and removes a temporary marker under maintenance" do
    assert_equal true, @storage.verify_write_access!
    assert_equal [], Dir.glob(@storage_path.join("maintenance", ".write-check-*")).sort
  end

  private

  def identity_key
    "local-machine:notes/shared-note.md"
  end

  def share_attributes(path: "notes/shared-note.md", note_identifier: "notes/shared-note.md", title: "Shared Note", content_hash: "hash-1", expires_at: nil, asset_manifest: [])
    {
      "source" => "preview",
      "note_identifier" => note_identifier,
      "path" => path,
      "title" => title,
      "plain_text" => "Hello from LewisMD",
      "theme_id" => "dark",
      "locale" => "en",
      "content_hash" => content_hash,
      "expires_at" => expires_at,
      "asset_manifest" => asset_manifest,
      "instance_name" => "local-machine"
    }
  end

  def asset_payload(upload_reference:, filename:, content:)
    {
      "upload_reference" => upload_reference,
      "filename" => filename,
      "mime_type" => "image/png",
      "byte_size" => content.bytesize,
      "sha256" => Digest::SHA256.hexdigest(content),
      "content_base64" => Base64.strict_encode64(content)
    }
  end

  def asset_manifest_entry(asset)
    {
      "source_url" => "data:image/png;base64,#{asset.fetch("content_base64")}",
      "source_type" => "data_uri",
      "filename" => asset.fetch("filename"),
      "mime_type" => asset.fetch("mime_type"),
      "byte_size" => asset.fetch("byte_size"),
      "sha256" => asset.fetch("sha256"),
      "upload_reference" => asset.fetch("upload_reference")
    }
  end
end
