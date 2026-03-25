# frozen_string_literal: true

require "test_helper"
require "base64"
require "rack/test"
require Rails.root.join("services/share_api/app")

class ShareApiAppTest < ActiveSupport::TestCase
  include Rack::Test::Methods

  def setup
    @storage_path = Rails.root.join("tmp", "share_api_test_#{SecureRandom.hex(6)}")
    FileUtils.mkdir_p(@storage_path)
    @config = ShareAPI::Configuration.new(
      env: {
        "LEWISMD_SHARE_STORAGE_PATH" => @storage_path.to_s,
        "LEWISMD_SHARE_API_TOKEN" => "token-123",
        "LEWISMD_SHARE_SIGNING_SECRET" => "signing-secret",
        "LEWISMD_SHARE_PUBLIC_BASE" => "https://shares.example.com"
      }
    )
    @app = ShareAPI::App.new(config: @config)
  end

  def teardown
    FileUtils.rm_rf(@storage_path)
  end

  def app
    @app
  end

  test "health endpoint returns ok" do
    get "/up"

    assert_equal 200, last_response.status
    assert_equal({ "status" => "ok" }, JSON.parse(last_response.body))
  end

  test "capabilities endpoint returns the current contract" do
    get "/api/v1/capabilities"

    assert_equal 200, last_response.status

    payload = JSON.parse(last_response.body)
    assert_equal "1", payload["api_version"]
    assert_equal true, payload.dig("feature_flags", "asset_uploads")
  end

  test "post creates a share, sanitizes the fragment, and serves it publicly" do
    body = JSON.generate(valid_payload.merge("html_fragment" => "<h1>Shared Note</h1><script>alert(1)</script>"))

    post "/api/v1/shares", body, signed_headers(method: "POST", path: "/api/v1/shares", body: body)

    assert_equal 201, last_response.status

    payload = JSON.parse(last_response.body)
    assert_match %r{\Ahttps://shares\.example\.com/s/}, payload["public_url"]

    get "/s/#{payload["token"]}"

    assert_equal 200, last_response.status
    assert_equal "text/html", last_response.media_type
    assert_equal "DENY", last_response.headers["X-Frame-Options"]
    assert_equal "nosniff", last_response.headers["X-Content-Type-Options"]
    assert_equal "no-referrer", last_response.headers["Referrer-Policy"]
    assert_equal "noindex, nofollow, noarchive", last_response.headers["X-Robots-Tag"]
    assert_includes last_response.headers["Content-Security-Policy"], "default-src 'none'"
    assert_includes last_response.headers["Content-Security-Policy"], "script-src 'none'"
    assert_includes last_response.body, "<header>"
    assert_includes last_response.body, "LewisMD Share"
    assert_includes last_response.body, "Read-only snapshot"
    assert_includes last_response.body, "<h1>Shared Note</h1>"
    refute_includes last_response.body, "<script>"
  end

  test "post is idempotent per identity key and reuses the same token" do
    body = JSON.generate(valid_payload)

    post "/api/v1/shares", body, signed_headers(method: "POST", path: "/api/v1/shares", body: body)
    first = JSON.parse(last_response.body)

    post "/api/v1/shares", body, signed_headers(method: "POST", path: "/api/v1/shares", body: body, request_id: SecureRandom.uuid)
    second = JSON.parse(last_response.body)

    assert_equal first["token"], second["token"]
  end

  test "put updates an existing share" do
    create_response = create_share!
    token = create_response.fetch("token")
    body = JSON.generate(valid_payload.merge("title" => "Updated Title", "html_fragment" => "<p>Version Two</p>", "content_hash" => "hash-2"))

    put "/api/v1/shares/#{token}", body, signed_headers(method: "PUT", path: "/api/v1/shares/#{token}", body: body)

    assert_equal 200, last_response.status
    assert_equal "Updated Title", JSON.parse(last_response.body)["title"]

    get "/s/#{token}"

    assert_includes last_response.body, "Version Two"
  end

  test "post stores uploaded image assets and serves them publicly" do
    body = JSON.generate(
      valid_payload.merge(
        "html_fragment" => '<p><img src="asset://asset-1" alt="Inline image"></p>',
        "asset_manifest" => [
          {
            "source_url" => "data:image/png;base64,aGVsbG8=",
            "source_type" => "data_uri",
            "filename" => "embedded-asset.png",
            "mime_type" => "image/png",
            "byte_size" => 5,
            "sha256" => Digest::SHA256.hexdigest("hello"),
            "upload_reference" => "asset-1"
          }
        ],
        "assets" => [
          {
            "source_url" => "data:image/png;base64,aGVsbG8=",
            "source_type" => "data_uri",
            "upload_reference" => "asset-1",
            "filename" => "embedded-asset.png",
            "mime_type" => "image/png",
            "byte_size" => 5,
            "sha256" => Digest::SHA256.hexdigest("hello"),
            "content_base64" => Base64.strict_encode64("hello")
          }
        ]
      )
    )

    post "/api/v1/shares", body, signed_headers(method: "POST", path: "/api/v1/shares", body: body)

    assert_equal 201, last_response.status
    payload = JSON.parse(last_response.body)

    get "/s/#{payload["token"]}"

    assert_equal 200, last_response.status
    asset_path = last_response.body[%r{/assets/#{payload["token"]}/[^"]+}]
    assert asset_path.present?

    get asset_path

    assert_equal 200, last_response.status
    assert_equal "image/png", last_response.media_type
    assert_equal "hello", last_response.body
    assert_equal "same-origin", last_response.headers["Cross-Origin-Resource-Policy"]
  end

  test "put removes orphaned uploaded assets after replacing a share snapshot" do
    create_body = JSON.generate(
      valid_payload.merge(
        "html_fragment" => '<p><img src="asset://asset-1" alt="First"></p>',
        "asset_manifest" => [
          {
            "source_url" => "data:image/png;base64,aGVsbG8=",
            "source_type" => "data_uri",
            "filename" => "first.png",
            "mime_type" => "image/png",
            "byte_size" => 5,
            "sha256" => Digest::SHA256.hexdigest("hello"),
            "upload_reference" => "asset-1"
          }
        ],
        "assets" => [
          {
            "source_url" => "data:image/png;base64,aGVsbG8=",
            "source_type" => "data_uri",
            "upload_reference" => "asset-1",
            "filename" => "first.png",
            "mime_type" => "image/png",
            "byte_size" => 5,
            "sha256" => Digest::SHA256.hexdigest("hello"),
            "content_base64" => Base64.strict_encode64("hello")
          }
        ]
      )
    )

    post "/api/v1/shares", create_body, signed_headers(method: "POST", path: "/api/v1/shares", body: create_body)
    created = JSON.parse(last_response.body)

    get "/s/#{created["token"]}"
    first_asset_path = last_response.body[%r{/assets/#{created["token"]}/[^"]+}]
    assert first_asset_path.present?

    update_body = JSON.generate(
      valid_payload.merge(
        "title" => "Updated Title",
        "html_fragment" => '<p><img src="asset://asset-2" alt="Second"></p>',
        "content_hash" => "hash-2",
        "asset_manifest" => [
          {
            "source_url" => "data:image/png;base64,d29ybGQ=",
            "source_type" => "data_uri",
            "filename" => "second.png",
            "mime_type" => "image/png",
            "byte_size" => 5,
            "sha256" => Digest::SHA256.hexdigest("world"),
            "upload_reference" => "asset-2"
          }
        ],
        "assets" => [
          {
            "source_url" => "data:image/png;base64,d29ybGQ=",
            "source_type" => "data_uri",
            "upload_reference" => "asset-2",
            "filename" => "second.png",
            "mime_type" => "image/png",
            "byte_size" => 5,
            "sha256" => Digest::SHA256.hexdigest("world"),
            "content_base64" => Base64.strict_encode64("world")
          }
        ]
      )
    )

    put "/api/v1/shares/#{created["token"]}", update_body, signed_headers(method: "PUT", path: "/api/v1/shares/#{created["token"]}", body: update_body)

    assert_equal 200, last_response.status

    get first_asset_path
    assert_equal 404, last_response.status

    get "/s/#{created["token"]}"
    second_asset_path = last_response.body[%r{/assets/#{created["token"]}/[^"]+}]
    assert second_asset_path.present?

    get second_asset_path
    assert_equal 200, last_response.status
    assert_equal "world", last_response.body
  end

  test "post rejects asset uploads with blocked mime types" do
    body = JSON.generate(
      valid_payload.merge(
        "html_fragment" => '<p><img src="asset://asset-1" alt="Inline image"></p>',
        "asset_manifest" => [
          {
            "source_url" => "data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=",
            "source_type" => "data_uri",
            "filename" => "vector.svg",
            "mime_type" => "image/svg+xml",
            "byte_size" => 11,
            "sha256" => Digest::SHA256.hexdigest("<svg></svg>"),
            "upload_reference" => "asset-1"
          }
        ],
        "assets" => [
          {
            "source_url" => "data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=",
            "source_type" => "data_uri",
            "upload_reference" => "asset-1",
            "filename" => "vector.svg",
            "mime_type" => "image/svg+xml",
            "byte_size" => 11,
            "sha256" => Digest::SHA256.hexdigest("<svg></svg>"),
            "content_base64" => Base64.strict_encode64("<svg></svg>")
          }
        ]
      )
    )

    post "/api/v1/shares", body, signed_headers(method: "POST", path: "/api/v1/shares", body: body)

    assert_equal 422, last_response.status
    assert_includes JSON.parse(last_response.body)["error"], "not allowed"
  end

  test "delete revokes an existing share" do
    create_response = create_share!
    token = create_response.fetch("token")

    delete "/api/v1/shares/#{token}", nil, signed_headers(method: "DELETE", path: "/api/v1/shares/#{token}", body: "")

    assert_equal 200, last_response.status
    assert_equal true, JSON.parse(last_response.body)["revoked"]

    get "/s/#{token}"

    assert_equal 404, last_response.status
  end

  test "public not found pages are uniform for invalid, missing, and revoked share tokens" do
    create_response = create_share!
    token = create_response.fetch("token")

    delete "/api/v1/shares/#{token}", nil, signed_headers(method: "DELETE", path: "/api/v1/shares/#{token}", body: "")
    assert_equal 200, last_response.status

    get "/s/#{token}"
    revoked_body = last_response.body
    revoked_headers = last_response.headers

    get "/s/invalid!token"
    invalid_body = last_response.body
    invalid_headers = last_response.headers

    get "/s/missingtoken"
    missing_body = last_response.body
    missing_headers = last_response.headers

    assert_equal 404, last_response.status
    assert_equal revoked_body, invalid_body
    assert_equal revoked_body, missing_body
    assert_equal revoked_headers["Content-Security-Policy"], invalid_headers["Content-Security-Policy"]
    assert_equal revoked_headers["Content-Security-Policy"], missing_headers["Content-Security-Policy"]
    assert_equal "DENY", invalid_headers["X-Frame-Options"]
    assert_includes invalid_body, "This shared note is not available."
  end

  test "missing assets return a hardened not found response" do
    get "/assets/missingtoken/image.png"

    assert_equal 404, last_response.status
    assert_equal "text/plain", last_response.media_type
    assert_equal "nosniff", last_response.headers["X-Content-Type-Options"]
    assert_equal "same-origin", last_response.headers["Cross-Origin-Resource-Policy"]
    assert_equal "Not found", last_response.body
  end

  test "reused request ids are rejected" do
    request_id = SecureRandom.uuid
    body = JSON.generate(valid_payload)
    headers = signed_headers(method: "POST", path: "/api/v1/shares", body: body, request_id: request_id, timestamp: Time.now.to_i)

    post "/api/v1/shares", body, headers
    assert_equal 201, last_response.status

    post "/api/v1/shares", body, headers

    assert_equal 409, last_response.status
    assert_includes JSON.parse(last_response.body)["error"], "already been processed"
  end

  private

  def create_share!
    body = JSON.generate(valid_payload)
    post "/api/v1/shares", body, signed_headers(method: "POST", path: "/api/v1/shares", body: body)
    JSON.parse(last_response.body)
  end

  def valid_payload
    {
      "source" => "preview",
      "note_identifier" => "notes/shared-note.md",
      "path" => "notes/shared-note.md",
      "title" => "Shared Note",
      "html_fragment" => "<p>Hello from LewisMD</p>",
      "plain_text" => "Hello from LewisMD",
      "theme_id" => "dark",
      "locale" => "en",
      "content_hash" => "hash-1",
      "asset_manifest" => [],
      "instance_name" => "local-machine"
    }
  end

  def signed_headers(method:, path:, body:, request_id: SecureRandom.uuid, timestamp: Time.now.to_i)
    payload = [
      timestamp.to_s,
      request_id,
      method.upcase,
      path,
      body.to_s
    ].join("\n")

    signature = OpenSSL::HMAC.hexdigest("SHA256", "signing-secret", payload)

    {
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer token-123",
      "HTTP_X_LEWISMD_TIMESTAMP" => timestamp.to_s,
      "HTTP_X_LEWISMD_REQUEST_ID" => request_id,
      "HTTP_X_LEWISMD_SIGNATURE" => signature
    }
  end
end
