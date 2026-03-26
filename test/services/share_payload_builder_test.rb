# frozen_string_literal: true

require "test_helper"

class SharePayloadBuilderTest < ActiveSupport::TestCase
  def setup
    setup_test_notes_dir
    @original_images_path = ENV["IMAGES_PATH"]
    @builder = SharePayloadBuilder.new
  end

  def teardown
    ENV["IMAGES_PATH"] = @original_images_path
    teardown_test_notes_dir
  end

  test "build extracts a sanitized fragment and payload metadata from a standalone share document" do
    payload = @builder.build(
      path: "shared-note.md",
      title: "Shared Note",
      document_html: <<~HTML
        <!DOCTYPE html>
        <html lang="pt-BR" data-theme="nord">
          <head>
            <title>Ignored Document Title</title>
            <meta name="color-scheme" content="dark">
            <style>
              .export-shell { padding: 3rem 1.5rem; }
              .export-article { max-width: 72ch; }
            </style>
          </head>
          <body>
            <main class="export-shell">
              <article class="export-article">
                <h1 onclick="alert('xss')">Shared</h1>
                <p>Hello <strong>world</strong>.</p>
                <script>alert("xss")</script>
                <iframe src="https://example.com/embed"></iframe>
                <p><a href="javascript:alert('xss')">Bad link</a></p>
                <p><a href="https://example.com/read">Good link</a></p>
                <img src="data:image/png;base64,aGVsbG8=" alt="Inline image" onerror="boom()">
                <table><tbody><tr><td colspan="2">Cell</td></tr></tbody></table>
              </article>
            </main>
          </body>
        </html>
      HTML
    )

    assert_equal "preview", payload[:source]
    assert_equal 2, payload[:snapshot_version]
    assert_equal 1, payload[:shell_version]
    assert_equal "shared-note.md", payload[:path]
    assert_equal "shared-note.md", payload[:note_identifier]
    assert_equal "Shared Note", payload[:title]
    assert_equal "pt-BR", payload[:locale]
    assert_equal "nord", payload[:theme_id]
    assert_equal 64, payload[:content_hash].length
    assert_equal "Shared Note", payload.dig(:shell_payload, :title)
    assert_equal "pt-BR", payload.dig(:shell_payload, :locale)
    assert_equal "nord", payload.dig(:shell_payload, :theme_id)
    assert_equal 100, payload.dig(:shell_payload, :display, :default_zoom)
    assert_equal 72, payload.dig(:shell_payload, :display, :default_width)
    assert_equal "default", payload.dig(:shell_payload, :display, :font_family)

    assert_includes payload[:html_fragment], "<h1>Shared</h1>"
    assert_includes payload[:html_fragment], "<strong>world</strong>"
    assert_includes payload[:html_fragment], "https://example.com/read"
    assert_includes payload[:html_fragment], "rel=\"noopener noreferrer nofollow\""
    assert_includes payload[:html_fragment], "<table>"
    refute_includes payload[:html_fragment], "<script"
    refute_includes payload[:html_fragment], "<iframe"
    refute_includes payload[:html_fragment], "onclick="
    refute_includes payload[:html_fragment], "onerror="
    refute_includes payload[:html_fragment], "javascript:"
    assert_equal "Shared\nHello world.\nBad link\nGood link\nCell", payload[:plain_text]
    assert_includes payload[:snapshot_document_html], "<!DOCTYPE html>"
    assert_includes payload[:snapshot_document_html], '<html lang="pt-BR" data-theme="nord">'
    assert_includes payload[:snapshot_document_html], '<meta name="color-scheme" content="dark">'
    assert_includes payload[:snapshot_document_html], "<style>"
    assert_includes payload[:snapshot_document_html], ".export-shell"
    assert_includes payload[:snapshot_document_html], '<main class="export-shell">'
    assert_includes payload[:snapshot_document_html], '<article class="export-article">'
    assert_includes payload[:snapshot_document_html], "<strong>world</strong>"
    refute_includes payload[:snapshot_document_html], "<script"
    refute_includes payload[:snapshot_document_html], "<iframe"
    refute_includes payload[:snapshot_document_html], "onclick="
    refute_includes payload[:snapshot_document_html], "onerror="

    assert_equal 1, payload[:asset_manifest].length
    asset = payload[:asset_manifest].first
    assert_equal "data:image/png;base64,aGVsbG8=", asset[:source_url]
    assert_equal "data_uri", asset[:source_type]
    assert_equal "embedded-asset.png", asset[:filename]
    assert_equal "image/png", asset[:mime_type]
    assert_equal 5, asset[:byte_size]
    assert_equal Digest::SHA256.hexdigest("hello"), asset[:sha256]
    assert_equal "asset-1", asset[:upload_reference]

    assert_equal 1, payload[:assets].length
    uploaded_asset = payload[:assets].first
    assert_equal "asset-1", uploaded_asset[:upload_reference]
    assert_equal "embedded-asset.png", uploaded_asset[:filename]
    assert_equal "image/png", uploaded_asset[:mime_type]
    assert_equal 5, uploaded_asset[:byte_size]
    assert_equal Digest::SHA256.hexdigest("hello"), uploaded_asset[:sha256]
    assert_equal "aGVsbG8=", uploaded_asset[:content_base64]
  end

  test "build falls back to document title when explicit title is blank" do
    payload = @builder.build(
      path: "nested/shared-note.md",
      title: "   ",
      document_html: <<~HTML
        <html lang="en">
          <head><title>Document Title</title></head>
          <body><article class="export-article"><p>Body</p></article></body>
        </html>
      HTML
    )

    assert_equal "Document Title", payload[:title]
  end

  test "build rejects fragments that sanitize down to no renderable content" do
    assert_raises(ShareService::InvalidShareError) do
      @builder.build(
        path: "shared-note.md",
        title: "Shared Note",
        document_html: <<~HTML
          <html><body><article class="export-article"><script>alert('xss')</script><iframe src="https://example.com"></iframe></article></body></html>
        HTML
      )
    end
  end

  test "build captures local preview images as uploadable assets" do
    image_path = @test_notes_dir.join(".frankmd", "images", "diagram.png")
    FileUtils.mkdir_p(image_path.dirname)
    image_path.binwrite("png-bytes")
    ENV["IMAGES_PATH"] = image_path.dirname.to_s

    payload = @builder.build(
      path: "shared-note.md",
      title: "Shared Note",
      document_html: <<~HTML
        <html lang="en">
          <body>
            <article class="export-article">
              <p><img src="/images/preview/diagram.png" alt="Diagram"></p>
            </article>
          </body>
        </html>
      HTML
    )

    assert_equal 1, payload[:asset_manifest].length
    manifest_entry = payload[:asset_manifest].first
    assert_equal "/images/preview/diagram.png", manifest_entry[:source_url]
    assert_equal "local_preview", manifest_entry[:source_type]
    assert_equal "diagram.png", manifest_entry[:filename]
    assert_equal "image/png", manifest_entry[:mime_type]
    assert_equal 9, manifest_entry[:byte_size]
    assert_equal Digest::SHA256.hexdigest("png-bytes"), manifest_entry[:sha256]
    assert_equal "asset-1", manifest_entry[:upload_reference]

    assert_equal 1, payload[:assets].length
    uploaded_asset = payload[:assets].first
    assert_equal "local_preview", uploaded_asset[:source_type]
    assert_equal "diagram.png", uploaded_asset[:filename]
    assert_equal Base64.strict_encode64("png-bytes"), uploaded_asset[:content_base64]
  end
end
