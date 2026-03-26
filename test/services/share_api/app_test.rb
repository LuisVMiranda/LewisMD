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
    assert_equal true, payload.dig("feature_flags", "full_share_shell")
  end

  test "reader bundle assets are served as static files" do
    get "/reader/assets/remote_reader_bundle.js"

    assert_equal 200, last_response.status
    assert_equal "text/javascript", last_response.media_type
    assert_includes last_response.body, "LewisMDRemoteReader"

    get "/reader/assets/remote_reader_bundle.css"

    assert_equal 200, last_response.status
    assert_equal "text/css", last_response.media_type
    assert_includes last_response.body, ".share-view__toolbar"
    assert_includes last_response.body, ".share-view__frame"
    assert_includes last_response.body, ".share-view__outline-card"
    assert_includes last_response.body, ".share-view__outline-menu-anchor"
    assert_includes last_response.body, ".share-view__outline-menu"
    assert_includes last_response.body, "@media (max-width: 1100px)"
    assert_includes last_response.body, "top: 30px;"
    assert_includes last_response.body, "left: 30px;"
    assert_includes last_response.body, "justify-content: center;"
    assert_includes last_response.body, "display: none !important;"
    assert_includes last_response.body, "box-sizing: border-box"

    get "/reader/assets/theme_helpers.js"

    assert_equal 200, last_response.status
    assert_equal "text/javascript", last_response.media_type
    assert_includes last_response.body, "BUILTIN_THEMES"

    get "/reader/assets/outline_helpers.js"

    assert_equal 200, last_response.status
    assert_equal "text/javascript", last_response.media_type
    assert_includes last_response.body, "collectOutlineEntries"

    get "/reader/assets/icon.svg"

    assert_equal 200, last_response.status
    assert_equal "image/svg+xml", last_response.media_type
    assert_includes last_response.body, "<svg"

    get "/reader/assets/share_view.css"

    assert_equal 200, last_response.status
    assert_equal "text/css", last_response.media_type
    assert_includes last_response.body, ".share-view__toolbar"

    get "/reader/assets/outline.css"

    assert_equal 200, last_response.status
    assert_equal "text/css", last_response.media_type
    assert_includes last_response.body, ".outline-item"

    get "/reader/assets/themes/dark.css"

    assert_equal 200, last_response.status
    assert_equal "text/css", last_response.media_type
    assert_includes last_response.body, '[data-theme="dark"]'
  end

  test "post creates a share, sanitizes the fragment, and serves it publicly" do
    body = JSON.generate(
      valid_payload.merge(
        "html_fragment" => "<h1>Shared Note</h1><script>alert(1)</script>",
        "snapshot_document_html" => <<~HTML
          <!doctype html>
          <html lang="en" data-theme="dark">
            <head>
              <style>
                .export-shell { padding: 3rem; }
              </style>
            </head>
            <body>
              <main class="export-shell">
                <article class="export-article">
                  <h1>Shared Note</h1><script>alert(1)</script>
                </article>
              </main>
            </body>
          </html>
        HTML
      )
    )

    post "/api/v1/shares", body, signed_headers(method: "POST", path: "/api/v1/shares", body: body)

    assert_equal 201, last_response.status

    payload = JSON.parse(last_response.body)
    assert_match %r{\Ahttps://shares\.example\.com/s/}, payload["public_url"]

    get "/s/#{payload["token"]}"

    assert_equal 200, last_response.status
    assert_equal "text/html", last_response.media_type
    assert_equal "DENY", last_response.headers["X-Frame-Options"]
    assert_equal "no-store", last_response.headers["Cache-Control"]
    assert_equal "nosniff", last_response.headers["X-Content-Type-Options"]
    assert_equal "no-referrer", last_response.headers["Referrer-Policy"]
    assert_equal "noindex, nofollow, noarchive", last_response.headers["X-Robots-Tag"]
    assert_includes last_response.headers["Content-Security-Policy"], "default-src 'none'"
    assert_includes last_response.headers["Content-Security-Policy"], "script-src 'self'"
    assert_includes last_response.headers["Content-Security-Policy"], "frame-src 'self'"
    assert_includes last_response.headers["Content-Security-Policy"], "style-src 'self' 'unsafe-inline'"
    assert_includes last_response.body, 'class="share-view share-view--remote"'
    assert_includes last_response.body, '<p class="share-view__eyebrow">Shared note</p>'
    assert_includes last_response.body, '<h1 class="share-view__title">Shared Note</h1>'
    assert_includes last_response.body, 'data-role="theme-toggle"'
    assert_includes last_response.body, 'data-role="locale-toggle"'
    assert_includes last_response.body, 'data-role="export-toggle"'
    assert_includes last_response.body, 'data-role="display-toggle"'
    assert_includes last_response.body, 'data-role="outline-section"'
    assert_includes last_response.body, 'data-role="outline-list"'
    assert_includes last_response.body, 'data-role="outline-menu-anchor"'
    assert_includes last_response.body, 'data-role="outline-menu-toggle"'
    assert_includes last_response.body, 'data-role="outline-menu"'
    assert_includes last_response.body, 'data-role="outline-menu-list"'
    assert_includes last_response.body, 'data-role="outline-menu-empty"'
    assert_includes last_response.body, 'data-role="outline-toggle"'
    assert_includes last_response.body, 'data-role="outline-body"'
    assert_includes last_response.body, '<h2 class="share-view__outline-title">Outline</h2>'
    assert_includes last_response.body, '<span class="share-view__toolbar-label">Outline</span>'
    assert_includes last_response.body, 'href="/reader/assets/icon.svg"'
    assert_includes last_response.body, 'href="/reader/assets/favicon-32x32.png"'
    assert_includes last_response.body, 'href="/reader/assets/apple-touch-icon.png"'
    assert_includes last_response.body, 'class="share-view__display-panel hidden"'
    assert_includes last_response.body, 'class="share-view__outline-shell hidden"'
    assert_includes last_response.body, 'title="Collapse outline"'
    refute_includes last_response.body, 'class="share-view__frame-shell"'
    assert_includes last_response.body, 'data-role="display-toggle"'
    assert_includes last_response.body, 'aria-expanded="false"'
    assert_includes last_response.body, 'title="Show reading controls"'
    assert_includes last_response.body, "remote_reader_bundle.css"
    assert_includes last_response.body, "remote_reader_bundle.js"
    assert_includes last_response.body, %(src="https://shares.example.com/snapshots/#{payload["token"]}")
    refute_includes last_response.body, "<script>alert(1)</script>"
  end

  test "public share shell honors theme and locale query params" do
    payload = create_share!

    get "/s/#{payload["token"]}?theme=light&locale=pt-BR"

    assert_equal 200, last_response.status
    assert_includes last_response.body, '<html lang="pt-BR" data-theme="light">'
    assert_includes last_response.body, '<p class="share-view__eyebrow">Nota compartilhada</p>'
    assert_includes last_response.body, 'data-translations="{&quot;header&quot;:{&quot;change_theme&quot;:&quot;Alterar Tema&quot;'
    assert_includes last_response.body, 'data-show-controls-label="Mostrar controles de leitura"'
    assert_includes last_response.body, 'data-hide-controls-label="Ocultar controles de leitura"'
    assert_includes last_response.body, 'title="Estrutura"'
    assert_includes last_response.body, '<span class="share-view__toolbar-label">Estrutura</span>'
    assert_includes last_response.body, '<h2 class="share-view__outline-title">Estrutura</h2>'
    assert_includes last_response.body, 'title="Recolher estrutura"'
    assert_includes last_response.body, ">Nenhum título ainda</p>"
    assert_includes last_response.body, 'title="Alterar Tema"'
    assert_includes last_response.body, 'title="Alterar Idioma"'
    assert_includes last_response.body, 'title="Abrir ações de compartilhamento, exportação e cópia"'
    assert_includes last_response.body, '<span class="share-view__toolbar-label">Compartilhar</span>'
    assert_includes last_response.body, '<span class="share-view__toolbar-label">Exibição</span>'
    assert_includes last_response.body, 'title="Visualização da nota compartilhada"'
    assert_includes last_response.body, '<span class="share-view__toolbar-label" data-role="theme-current-label">Light</span>'
    assert_includes last_response.body, '<span class="share-view__toolbar-label" data-role="locale-current-label">Português (Brasil)</span>'
    assert_includes last_response.body, 'data-default-zoom="100"'
    assert_includes last_response.body, 'data-default-width="72"'
    assert_includes last_response.body, 'data-default-font-family="default"'
  end

  test "post stores a snapshot document and serves it from the snapshot route" do
    body = JSON.generate(
      valid_payload.merge(
        "html_fragment" => "<h1>Shared Note</h1><script>alert(1)</script>",
        "snapshot_document_html" => <<~HTML
          <!doctype html>
          <html lang="pt-BR" data-theme="dark">
            <head>
              <meta name="color-scheme" content="dark">
              <style>
                .export-shell { padding: 3rem 1.5rem; }
                .export-article { max-width: 72ch; }
              </style>
            </head>
            <body>
              <main class="export-shell">
                <article class="export-article">
                  <h1>Shared Note</h1><script>alert(1)</script>
                </article>
              </main>
            </body>
          </html>
        HTML
      )
    )

    post "/api/v1/shares", body, signed_headers(method: "POST", path: "/api/v1/shares", body: body)
    assert_equal 201, last_response.status

    payload = JSON.parse(last_response.body)

    get "/snapshots/#{payload["token"]}"

    assert_equal 200, last_response.status
    assert_equal "text/html", last_response.media_type
    assert_equal "SAMEORIGIN", last_response.headers["X-Frame-Options"]
    assert_equal "no-store", last_response.headers["Cache-Control"]
    assert_includes last_response.headers["Content-Security-Policy"], "style-src 'unsafe-inline'"
    assert_includes last_response.headers["Content-Security-Policy"], "frame-ancestors 'self'"
    assert_includes last_response.body, '<html lang="en" data-theme="dark">'
    assert_includes last_response.body, '<main class="export-shell">'
    assert_includes last_response.body, '<article class="export-article">'
    assert_includes last_response.body, "width: min(100%, 72ch)"
    assert_includes last_response.body, "@media (max-width: 768px)"
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

    get "/snapshots/#{token}"

    assert_includes last_response.body, "Version Two"
  end

  test "different notes receive different public tokens and remain accessible simultaneously" do
    first_body = JSON.generate(valid_payload)
    second_body = JSON.generate(
      valid_payload.merge(
        "note_identifier" => "notes/second-note.md",
        "path" => "notes/second-note.md",
        "title" => "Second Shared Note",
        "html_fragment" => "<p>Hello from the second note</p>",
        "snapshot_document_html" => '<!doctype html><html lang="en" data-theme="light"><head><style>.export-shell { padding: 1rem; }</style></head><body><main class="export-shell"><article class="export-article"><p>Hello from the second note</p></article></main></body></html>',
        "shell_payload" => {
          "title" => "Second Shared Note",
          "locale" => "en",
          "theme_id" => "light",
          "display" => {
            "default_zoom" => 100,
            "default_width" => 72,
            "font_family" => "default"
          }
        },
        "theme_id" => "light",
        "content_hash" => "hash-2"
      )
    )

    post "/api/v1/shares", first_body, signed_headers(method: "POST", path: "/api/v1/shares", body: first_body)
    first_payload = JSON.parse(last_response.body)

    post "/api/v1/shares", second_body, signed_headers(method: "POST", path: "/api/v1/shares", body: second_body)
    second_payload = JSON.parse(last_response.body)

    refute_equal first_payload["token"], second_payload["token"]

    get "/s/#{first_payload["token"]}"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Shared Note"

    get "/s/#{second_payload["token"]}"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Second Shared Note"
  end

  test "post stores uploaded image assets and serves them publicly" do
    body = JSON.generate(
      valid_payload.merge(
        "html_fragment" => '<p><img src="asset://asset-1" alt="Inline image"></p>',
        "snapshot_document_html" => '<!doctype html><html lang="en" data-theme="dark"><head><style>.export-shell { padding: 1rem; }</style></head><body><main class="export-shell"><article class="export-article"><p><img src="asset://asset-1" alt="Inline image"></p></article></main></body></html>',
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

    get "/snapshots/#{payload["token"]}"

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

    get "/snapshots/#{created["token"]}"
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

    get "/snapshots/#{created["token"]}"
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

    get "/snapshots/#{token}"

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
    assert_equal "no-store", last_response.headers["Cache-Control"]
  end

  test "legacy shares without a stored snapshot document fall back to a generated snapshot page" do
    legacy_body = JSON.generate(
      valid_payload.except("snapshot_document_html", "shell_payload", "snapshot_version", "shell_version")
        .merge("html_fragment" => "<p>Legacy fragment</p>")
    )

    post "/api/v1/shares", legacy_body, signed_headers(method: "POST", path: "/api/v1/shares", body: legacy_body)
    assert_equal 201, last_response.status

    payload = JSON.parse(last_response.body)

    get "/snapshots/#{payload["token"]}"

    assert_equal 200, last_response.status
    assert_includes last_response.body, '<main class="export-shell">'
    assert_includes last_response.body, "<p>Legacy fragment</p>"
  end

  test "refreshing a legacy share migrates it to the full snapshot package format" do
    legacy_body = JSON.generate(
      valid_payload.except("snapshot_document_html", "shell_payload", "snapshot_version", "shell_version")
        .merge("html_fragment" => "<p>Legacy fragment</p>")
    )

    post "/api/v1/shares", legacy_body, signed_headers(method: "POST", path: "/api/v1/shares", body: legacy_body)
    assert_equal 201, last_response.status

    created = JSON.parse(last_response.body)
    refresh_body = JSON.generate(
      valid_payload.merge(
        "title" => "Migrated Share",
        "content_hash" => "hash-migrated",
        "theme_id" => "light",
        "locale" => "pt-BR",
        "html_fragment" => "<p>Migrated package</p>",
        "snapshot_document_html" => '<!doctype html><html lang="pt-BR" data-theme="light"><head><meta name="color-scheme" content="light"><style>.export-shell { padding: 2rem; }</style></head><body><main class="export-shell"><article class="export-article"><p>Migrated package</p></article></main></body></html>',
        "shell_payload" => {
          "title" => "Migrated Share",
          "locale" => "pt-BR",
          "theme_id" => "light",
          "display" => {
            "default_zoom" => 100,
            "default_width" => 72,
            "font_family" => "default"
          }
        }
      )
    )

    put "/api/v1/shares/#{created["token"]}", refresh_body, signed_headers(method: "PUT", path: "/api/v1/shares/#{created["token"]}", body: refresh_body)

    assert_equal 200, last_response.status
    assert_equal "Migrated Share", JSON.parse(last_response.body)["title"]

    get "/snapshots/#{created["token"]}"

    assert_equal 200, last_response.status
    assert_includes last_response.body, '<html lang="pt-BR" data-theme="light">'
    assert_includes last_response.body, "<p>Migrated package</p>"
    refute_includes last_response.body, "<p>Legacy fragment</p>"
  end

  test "expired shares return 404 immediately and are pruned from storage" do
    travel_to Time.zone.parse("2026-03-25 12:00:00 UTC")

    body = JSON.generate(
      valid_payload.merge(
        "expires_at" => "2026-03-25T12:01:00Z",
        "html_fragment" => '<p><img src="asset://asset-1" alt="Inline image"></p>',
        "snapshot_document_html" => '<!doctype html><html lang="en" data-theme="dark"><head><style>.export-shell { padding: 1rem; }</style></head><body><main class="export-shell"><article class="export-article"><p><img src="asset://asset-1" alt="Inline image"></p></article></main></body></html>',
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
    token = payload["token"]
    identity_digest = Digest::SHA256.hexdigest("local-machine:notes/shared-note.md")

    travel 2.minutes

    get "/s/#{token}"
    assert_equal 404, last_response.status
    assert_equal "no-store", last_response.headers["Cache-Control"]

    get "/snapshots/#{token}"
    assert_equal 404, last_response.status
    assert_equal "no-store", last_response.headers["Cache-Control"]

    get "/assets/#{token}/#{Digest::SHA256.hexdigest("hello")}-embedded-asset.png"
    assert_equal 404, last_response.status
    assert_equal "no-store", last_response.headers["Cache-Control"]

    refute @storage_path.join("shares", "#{token}.json").exist?
    refute @storage_path.join("snapshots", token).exist?
    refute @storage_path.join("assets", token).exist?
    refute @storage_path.join("path-index", "#{identity_digest}.json").exist?
  ensure
    travel_back
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
      "snapshot_version" => 2,
      "shell_version" => 1,
      "note_identifier" => "notes/shared-note.md",
      "path" => "notes/shared-note.md",
      "title" => "Shared Note",
      "html_fragment" => "<p>Hello from LewisMD</p>",
      "snapshot_document_html" => '<!doctype html><html lang="en" data-theme="dark"><head><style>.export-shell { padding: 1rem; }</style></head><body><main class="export-shell"><article class="export-article"><p>Hello from LewisMD</p></article></main></body></html>',
      "shell_payload" => {
        "title" => "Shared Note",
        "locale" => "en",
        "theme_id" => "dark",
        "display" => {
          "default_zoom" => 100,
          "default_width" => 72,
          "font_family" => "default"
        }
      },
      "plain_text" => "Hello from LewisMD",
      "theme_id" => "dark",
      "locale" => "en",
      "content_hash" => "hash-1",
      "expires_at" => "2026-04-08T12:00:00Z",
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
