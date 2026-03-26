# frozen_string_literal: true

require "base64"
require "cgi"
require "digest"
require "uri"

class SharePayloadBuilder
  SNAPSHOT_VERSION = 2
  SHELL_VERSION = 1

  ALLOWED_TAGS = %w[
    a
    blockquote
    br
    code
    em
    h1
    h2
    h3
    h4
    h5
    h6
    hr
    img
    li
    ol
    p
    pre
    strong
    table
    tbody
    td
    th
    thead
    tr
    ul
  ].freeze

  ALLOWED_ATTRIBUTES = %w[
    alt
    colspan
    href
    rowspan
    src
    title
  ].freeze

  BLOCKED_TAGS = %w[
    embed
    form
    iframe
    object
    script
    style
  ].freeze

  DATA_URI_PATTERN = %r{\Adata:(?<mime>[-\w.+/]+)?(?:;charset=[^;,]+)?;base64,(?<data>.+)\z}i
  LOCAL_PREVIEW_PATH = %r{\A/images/preview/(?<path>.+)\z}
  MIME_EXTENSIONS = {
    "image/avif" => "avif",
    "image/gif" => "gif",
    "image/jpeg" => "jpg",
    "image/jpg" => "jpg",
    "image/png" => "png",
    "image/webp" => "webp"
  }.freeze
  LIGHT_THEME_IDS = %w[
    light
    solarized-light
    catppuccin-latte
    rose-pine
    flexoki-light
  ].freeze
  DEFAULT_SHELL_DISPLAY = {
    default_zoom: 100,
    default_width: 72,
    font_family: "default"
  }.freeze

  def initialize(sanitizer: Rails::HTML5::SafeListSanitizer.new)
    @sanitizer = sanitizer
  end

  def build(path:, title:, document_html:)
    normalized_path = normalize_path(path)
    raise ShareService::InvalidShareError, "Snapshot HTML is required" if document_html.to_s.strip.blank?

    document = parse_document(document_html)
    sanitized_fragment = sanitize_fragment(extract_fragment_html(document))
    raise ShareService::InvalidShareError, "Share content is empty after sanitization" unless renderable_fragment?(sanitized_fragment)

    normalized_fragment_html = sanitized_fragment.to_html
    normalized_note_title = normalized_title(title, document, normalized_path)
    locale = extract_locale(document)
    theme_id = extract_theme_id(document)
    snapshot_document_html = build_snapshot_document(
      document: document,
      title: normalized_note_title,
      locale: locale,
      theme_id: theme_id,
      fragment_html: normalized_fragment_html
    )
    asset_manifest, assets = build_assets(sanitized_fragment)

    {
      snapshot_version: SNAPSHOT_VERSION,
      shell_version: SHELL_VERSION,
      source: "preview",
      path: normalized_path,
      note_identifier: normalized_path,
      title: normalized_note_title,
      html_fragment: normalized_fragment_html,
      snapshot_document_html: snapshot_document_html,
      shell_payload: build_shell_payload(
        title: normalized_note_title,
        locale: locale,
        theme_id: theme_id
      ),
      plain_text: normalize_plain_text(sanitized_fragment.text),
      theme_id: theme_id,
      locale: locale,
      content_hash: Digest::SHA256.hexdigest(snapshot_document_html),
      asset_manifest: asset_manifest,
      assets: assets
    }
  end

  private

  attr_reader :sanitizer

  def normalize_path(path)
    normalized_path = Note.normalize_path(path)
    raise ShareService::InvalidShareError, "Invalid share path" if normalized_path.blank?
    raise ShareService::InvalidShareError, "Only markdown notes can be shared" unless normalized_path.end_with?(".md")

    normalized_path
  end

  def parse_document(document_html)
    if defined?(Nokogiri::HTML5)
      Nokogiri::HTML5(document_html)
    else
      Nokogiri::HTML(document_html)
    end
  rescue StandardError
    Nokogiri::HTML(document_html)
  end

  def extract_fragment_html(document)
    article = document.at_css("article.export-article") || document.at_css("article")
    return article.inner_html if article

    body = document.at_css("body")
    return body.inner_html if body

    document.to_html
  end

  def sanitize_fragment(fragment_html)
    unsanitized_fragment = Nokogiri::HTML::DocumentFragment.parse(fragment_html.to_s)
    strip_blocked_elements!(unsanitized_fragment)

    sanitized_html = sanitizer.sanitize(
      unsanitized_fragment.to_html,
      tags: ALLOWED_TAGS,
      attributes: ALLOWED_ATTRIBUTES
    ).to_s

    fragment = Nokogiri::HTML::DocumentFragment.parse(sanitized_html)
    normalize_fragment!(fragment)
    fragment
  end

  def strip_blocked_elements!(fragment)
    fragment.css(BLOCKED_TAGS.join(",")).each(&:remove)
    fragment.xpath(".//comment()").each(&:remove)
  end

  def normalize_fragment!(fragment)
    fragment.css("a").each do |link|
      href = link["href"].to_s.strip
      if href.blank?
        link.remove_attribute("href")
      else
        link["rel"] = "noopener noreferrer nofollow"
      end
    end

    fragment.css("img").each do |image|
      image.remove unless image["src"].to_s.strip.present?
    end
  end

  def renderable_fragment?(fragment)
    return true if fragment.css("img,table,pre,blockquote,ul,ol").any?

    normalize_plain_text(fragment.text).present?
  end

  def normalized_title(raw_title, document, path)
    explicit_title = raw_title.to_s.strip
    return explicit_title if explicit_title.present?

    document_title = document.at_css("title")&.text.to_s.strip
    return document_title if document_title.present?

    File.basename(path, ".md")
  end

  def extract_theme_id(document)
    document.at_css("html")&.[]("data-theme").to_s.strip.presence
  end

  def extract_locale(document)
    document.at_css("html")&.[]("lang").to_s.strip.presence || I18n.default_locale.to_s
  end

  def extract_color_scheme(document, theme_id)
    declared = document.at_css('meta[name="color-scheme"]')&.[]("content").to_s.strip.downcase
    return declared if %w[light dark].include?(declared)

    LIGHT_THEME_IDS.include?(theme_id) ? "light" : "dark"
  end

  def normalize_plain_text(text)
    text.to_s
      .tr("\u00A0", " ")
      .gsub(/\r\n?/, "\n")
      .lines
      .map { |line| line.strip }
      .reject(&:blank?)
      .join("\n")
  end

  def build_snapshot_document(document:, title:, locale:, theme_id:, fragment_html:)
    color_scheme = extract_color_scheme(document, theme_id)
    style_blocks = extract_style_blocks(document)

    head_parts = [
      '<meta charset="utf-8">',
      '<meta name="viewport" content="width=device-width, initial-scale=1">',
      %(<meta name="color-scheme" content="#{CGI.escapeHTML(color_scheme)}">),
      %(<title>#{CGI.escapeHTML(title)}</title>)
    ]
    head_parts.concat(style_blocks.map { |css| wrap_style_block(css) })

    <<~HTML.chomp
      <!DOCTYPE html>
      <html lang="#{CGI.escapeHTML(locale)}"#{theme_attribute(theme_id)}>
      <head>
        #{head_parts.join("\n    ")}
      </head>
      <body>
        <main class="export-shell">
          <article class="export-article">
            #{fragment_html}
          </article>
        </main>
      </body>
      </html>
    HTML
  end

  def build_shell_payload(title:, locale:, theme_id:)
    {
      title: title,
      locale: locale,
      theme_id: theme_id,
      display: DEFAULT_SHELL_DISPLAY.dup
    }
  end

  def extract_style_blocks(document)
    document.css("head style").map { |node| node.text.to_s }.reject(&:blank?)
  end

  def wrap_style_block(css_text)
    escaped = css_text.to_s.gsub(%r{</style}i, '<\/style')
    "<style>\n#{escaped}\n</style>"
  end

  def theme_attribute(theme_id)
    theme_id.present? ? %( data-theme="#{CGI.escapeHTML(theme_id)}") : ""
  end

  def build_assets(fragment)
    manifest = []
    assets = []

    fragment.css("img").each_with_index do |image, index|
      src = image["src"].to_s.strip
      next if src.blank?

      uploadable_asset = resolve_uploadable_asset(src, "asset-#{index + 1}")
      manifest << {
        source_url: src,
        source_type: uploadable_asset&.fetch(:source_type, nil) || source_type_for(src),
        filename: uploadable_asset&.fetch(:filename, nil) || derive_asset_filename(src, nil),
        mime_type: uploadable_asset&.fetch(:mime_type, nil),
        byte_size: uploadable_asset&.fetch(:byte_size, nil),
        sha256: uploadable_asset&.fetch(:sha256, nil),
        upload_reference: uploadable_asset&.fetch(:upload_reference, nil)
      }

      assets << uploadable_asset if uploadable_asset
    end

    [ manifest, assets ]
  end

  def decode_data_uri(value)
    match = value.match(DATA_URI_PATTERN)
    return nil unless match

    decoded_bytes = Base64.decode64(match[:data].to_s)

    {
      mime_type: match[:mime].to_s.downcase.presence,
      byte_size: decoded_bytes.bytesize,
      sha256: Digest::SHA256.hexdigest(decoded_bytes)
    }
  rescue ArgumentError
    nil
  end

  def resolve_uploadable_asset(source_url, upload_reference)
    decoded_data_uri = decode_data_uri(source_url)
    return build_data_uri_asset(source_url, decoded_data_uri, upload_reference) if decoded_data_uri

    local_preview_asset = resolve_local_preview_asset(source_url, upload_reference)
    return local_preview_asset if local_preview_asset

    nil
  end

  def build_data_uri_asset(source_url, decoded_asset, upload_reference)
    extension = MIME_EXTENSIONS[decoded_asset[:mime_type]] || "bin"

    {
      source_type: "data_uri",
      source_url: source_url,
      upload_reference: upload_reference,
      filename: "embedded-asset.#{extension}",
      mime_type: decoded_asset[:mime_type],
      byte_size: decoded_asset[:byte_size],
      sha256: decoded_asset[:sha256],
      content_base64: source_url.split(",", 2).last
    }
  end

  def resolve_local_preview_asset(source_url, upload_reference)
    match = source_url.match(LOCAL_PREVIEW_PATH)
    return nil unless match

    relative_path = CGI.unescape(match[:path].to_s)
    full_path = ImagesService.find_image(relative_path)
    return nil unless full_path

    file_bytes = full_path.binread
    mime_type = mime_type_for_path(full_path)
    return nil unless mime_type

    {
      source_type: "local_preview",
      source_url: source_url,
      upload_reference: upload_reference,
      filename: full_path.basename.to_s,
      mime_type: mime_type,
      byte_size: file_bytes.bytesize,
      sha256: Digest::SHA256.hexdigest(file_bytes),
      content_base64: Base64.strict_encode64(file_bytes)
    }
  end

  def source_type_for(source_url)
    return "data_uri" if source_url.match?(DATA_URI_PATTERN)
    return "local_preview" if source_url.match?(LOCAL_PREVIEW_PATH)
    return "external" if source_url.match?(%r{\Ahttps?://}i)

    "unknown"
  end

  def mime_type_for_path(path)
    case path.extname.downcase
    when ".avif" then "image/avif"
    when ".gif" then "image/gif"
    when ".jpg", ".jpeg" then "image/jpeg"
    when ".png" then "image/png"
    when ".webp" then "image/webp"
    else nil
    end
  end

  def derive_asset_filename(source_url, decoded_asset)
    parsed_path = URI.parse(source_url).path
    candidate = File.basename(parsed_path.to_s)
    return candidate if candidate.present? && candidate != "/"

    extension = MIME_EXTENSIONS[decoded_asset&.fetch(:mime_type, nil)] || "bin"
    "embedded-asset.#{extension}"
  rescue URI::InvalidURIError
    extension = MIME_EXTENSIONS[decoded_asset&.fetch(:mime_type, nil)] || "bin"
    "embedded-asset.#{extension}"
  end
end
