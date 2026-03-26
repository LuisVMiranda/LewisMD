# frozen_string_literal: true

require "cgi"
require "json"
require "pathname"
require "rack"
require "nokogiri"
require_relative "lib/share_api/authenticator"
require_relative "lib/share_api/configuration"
require_relative "lib/share_api/fragment_sanitizer"
require_relative "lib/share_api/storage"

module ShareAPI
  class App
    REMOTE_READER_THEME_NAMES = {
      "light" => "Light",
      "dark" => "Dark",
      "catppuccin" => "Catppuccin",
      "catppuccin-latte" => "Catppuccin Latte",
      "ethereal" => "Ethereal",
      "everforest" => "Everforest",
      "flexoki-light" => "Flexoki Light",
      "gruvbox" => "Gruvbox",
      "hackerman" => "Hackerman",
      "kanagawa" => "Kanagawa",
      "matte-black" => "Matte Black",
      "nord" => "Nord",
      "osaka-jade" => "Osaka Jade",
      "ristretto" => "Ristretto",
      "rose-pine" => "Rose Pine",
      "solarized-dark" => "Solarized Dark",
      "solarized-light" => "Solarized Light",
      "tokyo-night" => "Tokyo Night"
    }.freeze
    REMOTE_READER_LOCALE_NAMES = {
      "en" => "English",
      "pt-BR" => "Português (Brasil)",
      "pt-PT" => "Português (Portugal)",
      "es" => "Español",
      "he" => "עברית",
      "ja" => "日本語",
      "ko" => "한국어"
    }.freeze
    LIGHT_THEME_IDS = %w[light solarized-light catppuccin-latte rose-pine flexoki-light].freeze
    TOKEN_PATTERN = /\A[a-zA-Z0-9\-_]{8,}\z/
    REMOTE_READER_TRANSLATIONS_PATH = Pathname.new(__dir__).join("public", "reader", "remote_reader_translations.json")
    READER_ASSETS = {
      "/reader/assets/remote_reader_bundle.js" => {
        content_type: "text/javascript; charset=utf-8",
        path: -> { Pathname.new(__dir__).join("public", "reader", "remote_reader_bundle.js") }
      },
      "/reader/assets/remote_reader_bundle.css" => {
        content_type: "text/css; charset=utf-8",
        path: -> { Pathname.new(__dir__).join("public", "reader", "remote_reader_bundle.css") }
      },
      "/reader/assets/theme_helpers.js" => {
        content_type: "text/javascript; charset=utf-8",
        path: -> { reader_public_path("theme_helpers.js") }
      },
      "/reader/assets/locale_helpers.js" => {
        content_type: "text/javascript; charset=utf-8",
        path: -> { reader_public_path("locale_helpers.js") }
      },
      "/reader/assets/translation_helpers.js" => {
        content_type: "text/javascript; charset=utf-8",
        path: -> { reader_public_path("translation_helpers.js") }
      },
      "/reader/assets/export_menu_helpers.js" => {
        content_type: "text/javascript; charset=utf-8",
        path: -> { reader_public_path("export_menu_helpers.js") }
      },
      "/reader/assets/outline_helpers.js" => {
        content_type: "text/javascript; charset=utf-8",
        path: -> { reader_public_path("outline_helpers.js") }
      },
      "/reader/assets/share_view.css" => {
        content_type: "text/css; charset=utf-8",
        path: -> { reader_public_path("share_view.css") }
      },
      "/reader/assets/outline.css" => {
        content_type: "text/css; charset=utf-8",
        path: -> { reader_public_path("outline.css") }
      },
      "/reader/assets/icon.svg" => {
        content_type: "image/svg+xml",
        path: -> { reader_public_path("icon.svg") }
      },
      "/reader/assets/favicon-32x32.png" => {
        content_type: "image/png",
        path: -> { reader_public_path("favicon-32x32.png") }
      },
      "/reader/assets/favicon-16x16.png" => {
        content_type: "image/png",
        path: -> { reader_public_path("favicon-16x16.png") }
      },
      "/reader/assets/apple-touch-icon.png" => {
        content_type: "image/png",
        path: -> { reader_public_path("apple-touch-icon.png") }
      }
    }.freeze
    PUBLIC_NOT_FOUND_HTML = <<~HTML.freeze
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="robots" content="noindex,nofollow,noarchive">
          <title>LewisMD Share</title>
        </head>
        <body>
          <main>
            <h1>LewisMD Share</h1>
            <p>This shared note is not available.</p>
          </main>
        </body>
      </html>
    HTML

    def initialize(config: Configuration.new, storage: nil, sanitizer: FragmentSanitizer.new)
      @config = config
      @storage = storage || Storage.new(
        storage_path: config.storage_path,
        max_asset_bytes: config.max_asset_bytes,
        max_asset_count: config.max_asset_count
      )
      @sanitizer = sanitizer
      @authenticator = Authenticator.new(config: config, storage: @storage)
    end

    def call(env)
      request = Rack::Request.new(env)

      case [ request.request_method, request.path_info ]
      in [ "GET", "/up" ]
        json_response(200, { status: "ok" })
      in [ "GET", "/api/v1/capabilities" ]
        json_response(200, capabilities_payload)
      else
        route_dynamic(request)
      end
    rescue Authenticator::UnauthorizedError => e
      json_response(401, { error: e.message })
    rescue Authenticator::ReplayError => e
      json_response(409, { error: e.message })
    rescue FragmentSanitizer::SanitizationError, Storage::ValidationError => e
      json_response(422, { error: e.message })
    rescue Storage::NotFoundError
      not_found_response(request)
    rescue JSON::ParserError
      json_response(400, { error: "Invalid JSON payload" })
    end

    private

    attr_reader :config, :storage, :sanitizer, :authenticator

    def route_dynamic(request)
      if request.get? && request.path_info == "/reader/assets/remote_reader_bundle.css"
        return render_remote_reader_bundle_css
      end

      if request.get? && (reader_asset = reader_asset_for(request.path_info))
        return render_reader_asset(reader_asset)
      end

      if request.get? && (match = request.path_info.match(%r{\A/s/([^/]+)\z}))
        return render_public_share(request, match[1])
      end

      if request.get? && (match = request.path_info.match(%r{\A/snapshots/([^/]+)\z}))
        return render_snapshot_document(match[1])
      end

      if request.get? && (match = request.path_info.match(%r{\A/assets/([^/]+)/(.+)\z}))
        return render_asset(match[1], match[2])
      end

      if request.post? && request.path_info == "/api/v1/shares"
        return create_share(request)
      end

      if (match = request.path_info.match(%r{\A/api/v1/shares/([^/]+)\z}))
        token = match[1]
        return update_share(request, token) if request.put?
        return revoke_share(request, token) if request.delete?
      end

      not_found_response(request)
    end

    def create_share(request)
      body = request.body.read
      authenticate_write!(request, body)
      payload = parse_payload(body)
      sanitized_fragment = sanitize_payload_fragment(payload.fetch("html_fragment"))
      identity_key = identity_key_for(payload)
      created, share = storage.upsert_share(
        identity_key: identity_key,
        share: share_attributes_from(payload),
        fragment_html: sanitized_fragment,
        snapshot_document_html: build_snapshot_document(payload, sanitized_fragment),
        assets: extract_upload_assets(payload)
      )

      json_response(created ? 201 : 200, share_response(request, share))
    end

    def update_share(request, token)
      validate_token!(token)
      body = request.body.read
      authenticate_write!(request, body)
      payload = parse_payload(body)
      sanitized_fragment = sanitize_payload_fragment(payload.fetch("html_fragment"))
      share = storage.update_share(
        token: token,
        share: share_attributes_from(payload),
        fragment_html: sanitized_fragment,
        snapshot_document_html: build_snapshot_document(payload, sanitized_fragment),
        assets: extract_upload_assets(payload)
      )

      json_response(200, share_response(request, share))
    end

    def revoke_share(request, token)
      validate_token!(token)
      body = request.body.read
      authenticate_write!(request, body)
      share = storage.delete_share(token: token)

      json_response(200, share_response(request, share).merge("revoked" => true))
    end

    def render_public_share(request, token)
      validate_token!(token)
      share = storage.fetch_share(token)
      html_response(200, build_reader_shell_html(request: request, share: share), cache_control: "no-store")
    end

    def render_asset(token, asset_name)
      validate_token!(token)
      asset_path = storage.asset_path(token: token, asset_name: asset_name)
      raise Storage::NotFoundError unless asset_path.file?

      [
        200,
        asset_headers(content_type: Rack::Mime.mime_type(asset_path.extname, "application/octet-stream")),
        [ asset_path.binread ]
      ]
    end

    def render_snapshot_document(token)
      validate_token!(token)
      share = storage.fetch_share(token)
      snapshot_document_html = read_snapshot_document_with_fallback(token: token, share: share)

      snapshot_html_response(200, snapshot_document_html, cache_control: "no-store")
    end

    def authenticate_write!(request, body)
      raise Storage::ValidationError, "Payload exceeds configured size limit" if body.bytesize > config.max_payload_bytes

      authenticator.authenticate!(request: request, body: body)
    end

    def parse_payload(body)
      payload = JSON.parse(body.to_s.strip.empty? ? "{}" : body)
      raise Storage::ValidationError, "Payload must be a JSON object" unless payload.is_a?(Hash)

      payload
    end

    def sanitize_payload_fragment(fragment_html)
      sanitizer.sanitize(fragment_html)
    end

    def share_attributes_from(payload)
      {
        "source" => payload["source"],
        "note_identifier" => non_blank(payload["note_identifier"]) || payload["path"],
        "path" => payload["path"],
        "title" => payload["title"],
        "snapshot_version" => payload["snapshot_version"],
        "shell_version" => payload["shell_version"],
        "shell_payload" => payload["shell_payload"].is_a?(Hash) ? payload["shell_payload"] : {},
        "plain_text" => payload["plain_text"],
        "theme_id" => payload["theme_id"],
        "locale" => payload["locale"],
        "content_hash" => payload["content_hash"],
        "expires_at" => payload["expires_at"],
        "asset_manifest" => Array(payload["asset_manifest"]),
        "instance_name" => payload["instance_name"]
      }
    end

    def share_response(request, share)
      {
        "token" => share["token"],
        "title" => share["title"],
        "created_at" => share["created_at"],
        "updated_at" => share["updated_at"],
        "public_url" => public_url_for(request, share["token"]),
        "expires_at" => share["expires_at"]
      }
    end

    def public_url_for(request, token)
      [ non_blank(config.public_base) || request.base_url.delete_suffix("/"), "s", token ].join("/")
    end

    def capabilities_payload
      {
        api_version: "1",
        minimum_client_version: 1,
        feature_flags: {
          asset_uploads: true,
          full_share_shell: true
        },
        max_payload_bytes: config.max_payload_bytes,
        max_asset_bytes: config.max_asset_bytes,
        max_asset_count: config.max_asset_count
      }
    end

    def build_reader_shell_html(request:, share:)
      shell_payload = share["shell_payload"].is_a?(Hash) ? share["shell_payload"] : {}
      display_payload = shell_payload["display"].is_a?(Hash) ? shell_payload["display"] : {}
      title = non_blank(share["title"]) || "LewisMD Share"
      current_theme = current_theme_for(request, share: share, shell_payload: shell_payload)
      current_locale = current_locale_for(request, share: share, shell_payload: shell_payload)
      translations_json = CGI.escapeHTML(JSON.generate(reader_translations_for(current_locale)))
      snapshot_url = "#{public_base_for(request)}/snapshots/#{CGI.escapeHTML(share.fetch("token"))}"
      default_zoom = integer_or_default(display_payload["default_zoom"], 100)
      default_width = integer_or_default(display_payload["default_width"], 72)
      default_font_family = non_blank(display_payload["font_family"]) || "default"
      current_color_scheme = inferred_light_theme?(current_theme) ? "light" : "dark"
      show_controls_label = reader_translate(current_locale, "share_view.show_controls", default: "Show reading controls")
      hide_controls_label = reader_translate(current_locale, "share_view.hide_controls", default: "Hide reading controls")
      shared_note_label = reader_translate(current_locale, "share_view.label", default: "Shared note")
      outline_label = reader_translate(current_locale, "sidebar.outline", default: "Outline")
      no_headings_label = reader_translate(current_locale, "sidebar.no_headings_yet", default: "No headings yet")
      collapse_outline_label = reader_translate(current_locale, "share_view.collapse_outline", default: "Collapse outline")
      iframe_title = reader_translate(current_locale, "share_view.iframe_title", default: "Shared note preview")

      <<~HTML
        <!doctype html>
        <html lang="#{CGI.escapeHTML(current_locale)}" data-theme="#{CGI.escapeHTML(current_theme)}"#{current_color_scheme == "dark" ? ' class="dark"' : ""}>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="robots" content="noindex,nofollow,noarchive">
            <meta name="color-scheme" content="#{CGI.escapeHTML(current_color_scheme)}">
            <title>#{CGI.escapeHTML(title)} | LewisMD Share</title>
            <link rel="icon" type="image/svg+xml" href="/reader/assets/icon.svg">
            <link rel="icon" type="image/png" sizes="32x32" href="/reader/assets/favicon-32x32.png">
            <link rel="icon" type="image/png" sizes="16x16" href="/reader/assets/favicon-16x16.png">
            <link rel="apple-touch-icon" sizes="180x180" href="/reader/assets/apple-touch-icon.png">
            <link rel="stylesheet" href="/reader/assets/remote_reader_bundle.css">
            <script type="module" src="/reader/assets/remote_reader_bundle.js"></script>
          </head>
          <body>
            <div
              class="share-view share-view--remote"
              data-remote-reader
              data-title="#{CGI.escapeHTML(title)}"
              data-locale="#{CGI.escapeHTML(current_locale)}"
              data-theme="#{CGI.escapeHTML(current_theme)}"
              data-default-zoom="#{default_zoom}"
              data-default-width="#{default_width}"
              data-default-font-family="#{CGI.escapeHTML(default_font_family)}"
              data-translations="#{translations_json}"
              data-show-controls-label="#{CGI.escapeHTML(show_controls_label)}"
              data-hide-controls-label="#{CGI.escapeHTML(hide_controls_label)}"
            >
              <header class="share-view__toolbar">
                <div class="share-view__toolbar-top">
                  <div class="share-view__identity">
                    <p class="share-view__eyebrow">#{CGI.escapeHTML(shared_note_label)}</p>
                    <h1 class="share-view__title">#{CGI.escapeHTML(title)}</h1>
                  </div>

                  #{reader_toolbar_actions_html(
                    current_theme:,
                    current_locale:,
                    ui_locale: current_locale,
                    outline_label:,
                    no_headings_label:
                  )}
                </div>

                #{reader_display_panel_html(default_font_family:, ui_locale: current_locale)}
              </header>

              <main class="share-view__content">
                <aside
                  class="share-view__outline-shell hidden"
                  data-role="outline-section"
                  data-collapsed="false"
                  aria-label="#{CGI.escapeHTML(outline_label)}"
                >
                  <div class="share-view__outline-card outline-panel">
                    <div class="share-view__outline-header">
                      <h2 class="share-view__outline-title">#{CGI.escapeHTML(outline_label)}</h2>
                      <button
                        type="button"
                        class="share-view__outline-toggle share-view__button"
                        data-role="outline-toggle"
                        aria-expanded="true"
                        aria-controls="share-view-outline-body"
                        title="#{CGI.escapeHTML(collapse_outline_label)}"
                        aria-label="#{CGI.escapeHTML(collapse_outline_label)}"
                      >
                        #{caret_icon_markup}
                      </button>
                    </div>
                    <div
                      id="share-view-outline-body"
                      class="share-view__outline-body"
                      data-role="outline-body"
                    >
                      <div class="outline-panel__scroll">
                        <div class="outline-list" data-role="outline-list"></div>
                        <p class="outline-empty hidden" data-role="outline-empty">#{CGI.escapeHTML(no_headings_label)}</p>
                      </div>
                    </div>
                  </div>
                </aside>

                <iframe
                  src="#{snapshot_url}"
                  class="share-view__frame"
                  title="#{CGI.escapeHTML(iframe_title)}"
                  loading="eager"
                  data-role="frame"
                ></iframe>
              </main>
            </div>
          </body>
        </html>
      HTML
    end

    def reader_toolbar_actions_html(current_theme:, current_locale:, ui_locale:, outline_label:, no_headings_label:)
      change_theme_label = reader_translate(ui_locale, "header.change_theme", default: "Change theme")
      change_language_label = reader_translate(ui_locale, "header.change_language", default: "Change language")
      open_share_menu_label = reader_translate(ui_locale, "header.open_share_menu", default: "Open share menu")
      toolbar_outline_label = reader_translate(ui_locale, "header.outline", default: outline_label)
      share_label = reader_translate(ui_locale, "header.share", default: "Share")
      display_label = reader_translate(ui_locale, "share_view.display", default: "Display")
      show_controls_label = reader_translate(ui_locale, "share_view.show_controls", default: "Show reading controls")

      <<~HTML
        <div class="share-view__toolbar-actions">
          <div class="share-view__menu-anchor share-view__outline-menu-anchor hidden" data-role="outline-menu-anchor">
            <button
              type="button"
              class="share-view__toolbar-button share-view__toolbar-button--outline"
              title="#{CGI.escapeHTML(toolbar_outline_label)}"
              aria-label="#{CGI.escapeHTML(toolbar_outline_label)}"
              aria-haspopup="menu"
              aria-expanded="false"
              data-role="outline-menu-toggle"
            >
              #{outline_icon_markup}
              <span class="share-view__toolbar-label">#{CGI.escapeHTML(toolbar_outline_label)}</span>
              #{caret_icon_markup}
            </button>
            <div class="share-view__picker-menu share-view__outline-menu hidden" data-role="outline-menu">
              <div class="outline-panel__scroll">
                <div class="outline-list" data-role="outline-menu-list"></div>
                <p class="outline-empty hidden" data-role="outline-menu-empty">#{CGI.escapeHTML(no_headings_label)}</p>
              </div>
            </div>
          </div>

          <div class="share-view__menu-anchor">
            <button
              type="button"
              class="share-view__toolbar-button"
              title="#{CGI.escapeHTML(change_theme_label)}"
              aria-haspopup="menu"
              aria-expanded="false"
              data-role="theme-toggle"
            >
              #{palette_icon_markup}
              <span class="share-view__toolbar-label" data-role="theme-current-label">#{CGI.escapeHTML(theme_name_for(current_theme))}</span>
              #{caret_icon_markup}
            </button>
            <div class="share-view__picker-menu hidden" data-role="theme-menu"></div>
          </div>

          <div class="share-view__menu-anchor">
            <button
              type="button"
              class="share-view__toolbar-button"
              title="#{CGI.escapeHTML(change_language_label)}"
              aria-haspopup="menu"
              aria-expanded="false"
              data-role="locale-toggle"
            >
              #{language_icon_markup}
              <span class="share-view__toolbar-label" data-role="locale-current-label">#{CGI.escapeHTML(locale_name_for(current_locale))}</span>
              #{caret_icon_markup}
            </button>
            <div class="share-view__picker-menu hidden" data-role="locale-menu"></div>
          </div>

          <div class="share-view__menu-anchor">
            <button
              type="button"
              class="share-view__toolbar-button"
              title="#{CGI.escapeHTML(open_share_menu_label)}"
              aria-haspopup="menu"
              aria-expanded="false"
              data-role="export-toggle"
            >
              #{share_icon_markup}
              <span class="share-view__toolbar-label">#{CGI.escapeHTML(share_label)}</span>
              #{caret_icon_markup}
            </button>
            <div class="share-view__export-menu hidden" data-role="export-menu"></div>
          </div>

          <button
            type="button"
            class="share-view__toolbar-button"
            data-role="display-toggle"
            aria-expanded="false"
            aria-controls="share-view-display-panel"
            title="#{CGI.escapeHTML(show_controls_label)}"
            aria-label="#{CGI.escapeHTML(show_controls_label)}"
          >
            #{display_icon_markup}
            <span class="share-view__toolbar-label">#{CGI.escapeHTML(display_label)}</span>
          </button>
        </div>
      HTML
    end

    def reader_display_panel_html(default_font_family:, ui_locale:)
      default_selected = default_font_family == "default" ? ' selected="selected"' : ""
      sans_selected = default_font_family == "sans" ? ' selected="selected"' : ""
      serif_selected = default_font_family == "serif" ? ' selected="selected"' : ""
      mono_selected = default_font_family == "mono" ? ' selected="selected"' : ""
      display_controls_label = reader_translate(ui_locale, "share_view.display_controls", default: "Reading controls")
      zoom_label = reader_translate(ui_locale, "share_view.zoom", default: "Zoom")
      zoom_in_label = reader_translate(ui_locale, "share_view.zoom_in", default: "Zoom in")
      zoom_out_label = reader_translate(ui_locale, "share_view.zoom_out", default: "Zoom out")
      width_label = reader_translate(ui_locale, "share_view.width", default: "Width")
      width_narrower_label = reader_translate(ui_locale, "share_view.width_narrower", default: "Make text column narrower")
      width_wider_label = reader_translate(ui_locale, "share_view.width_wider", default: "Make text column wider")
      font_family_label = reader_translate(ui_locale, "share_view.font_family", default: "Font")
      font_default_label = reader_translate(ui_locale, "share_view.font_default", default: "Default")
      font_sans_label = reader_translate(ui_locale, "share_view.font_sans", default: "Sans")
      font_serif_label = reader_translate(ui_locale, "share_view.font_serif", default: "Serif")
      font_mono_label = reader_translate(ui_locale, "share_view.font_mono", default: "Mono")

      <<~HTML
        <div
          id="share-view-display-panel"
          class="share-view__display-panel hidden"
          data-role="display-panel"
          aria-label="#{CGI.escapeHTML(display_controls_label)}"
        >
          <div class="share-view__group">
            <span class="share-view__group-label">#{CGI.escapeHTML(zoom_label)}</span>
            <button type="button" class="share-view__button" title="#{CGI.escapeHTML(zoom_out_label)}" data-role="zoom-out">-</button>
            <output class="share-view__value" data-role="zoom-value">100%</output>
            <button type="button" class="share-view__button" title="#{CGI.escapeHTML(zoom_in_label)}" data-role="zoom-in">+</button>
          </div>

          <div class="share-view__group">
            <span class="share-view__group-label">#{CGI.escapeHTML(width_label)}</span>
            <button type="button" class="share-view__button" title="#{CGI.escapeHTML(width_narrower_label)}" data-role="width-decrease">-</button>
            <output class="share-view__value" data-role="width-value">72ch</output>
            <button type="button" class="share-view__button" title="#{CGI.escapeHTML(width_wider_label)}" data-role="width-increase">+</button>
          </div>

          <label class="share-view__group share-view__font-group">
            <span class="share-view__group-label">#{CGI.escapeHTML(font_family_label)}</span>
            <select class="share-view__select" data-role="font-select">
              <option value="default"#{default_selected}>#{CGI.escapeHTML(font_default_label)}</option>
              <option value="sans"#{sans_selected}>#{CGI.escapeHTML(font_sans_label)}</option>
              <option value="serif"#{serif_selected}>#{CGI.escapeHTML(font_serif_label)}</option>
              <option value="mono"#{mono_selected}>#{CGI.escapeHTML(font_mono_label)}</option>
            </select>
          </label>
        </div>
      HTML
    end

    def current_theme_for(request, share:, shell_payload:)
      requested_theme = non_blank(request.params["theme"])
      return requested_theme if requested_theme && REMOTE_READER_THEME_NAMES.key?(requested_theme)

      shell_theme = non_blank(shell_payload["theme_id"])
      return shell_theme if shell_theme && REMOTE_READER_THEME_NAMES.key?(shell_theme)

      share_theme = non_blank(share["theme_id"])
      return share_theme if share_theme && REMOTE_READER_THEME_NAMES.key?(share_theme)

      "light"
    end

    def current_locale_for(request, share:, shell_payload:)
      requested_locale = non_blank(request.params["locale"])
      return requested_locale if requested_locale && REMOTE_READER_LOCALE_NAMES.key?(requested_locale)

      shell_locale = non_blank(shell_payload["locale"])
      return shell_locale if shell_locale && REMOTE_READER_LOCALE_NAMES.key?(shell_locale)

      share_locale = non_blank(share["locale"])
      return share_locale if share_locale && REMOTE_READER_LOCALE_NAMES.key?(share_locale)

      "en"
    end

    def public_base_for(request)
      non_blank(config.public_base) || request.base_url.delete_suffix("/")
    end

    def theme_name_for(theme_id)
      REMOTE_READER_THEME_NAMES.fetch(theme_id.to_s, "Light")
    end

    def locale_name_for(locale)
      REMOTE_READER_LOCALE_NAMES.fetch(locale.to_s, "English")
    end

    def reader_translations_for(locale)
      reader_translations_bundle.fetch(locale.to_s, reader_translations_bundle.fetch("en", {}))
    end

    def reader_translate(locale, key, default:)
      value = key.to_s.split(".").reduce(reader_translations_for(locale)) do |memo, segment|
        memo.is_a?(Hash) ? memo[segment] : nil
      end

      value.is_a?(String) && !value.empty? ? value : default
    end

    def reader_translations_bundle
      @reader_translations_bundle ||= JSON.parse(REMOTE_READER_TRANSLATIONS_PATH.read)
    end

    def integer_or_default(value, default)
      integer = value.to_i
      integer.positive? ? integer : default
    end

    def identity_key_for(payload)
      identifier = non_blank(payload["note_identifier"]) || non_blank(payload["path"])
      raise Storage::ValidationError, "note_identifier or path is required" if identifier.nil?

      [ non_blank(payload["instance_name"]), identifier.to_s.strip ].compact.join(":")
    end

    def validate_token!(token)
      raise Storage::NotFoundError unless token.to_s.match?(TOKEN_PATTERN)
    end

    def json_response(status, payload)
      [
        status,
        json_headers,
        [ JSON.generate(payload) ]
      ]
    end

    def not_found_response(request)
      return snapshot_html_response(404, PUBLIC_NOT_FOUND_HTML, cache_control: "no-store") if request.get? && request.path_info.start_with?("/snapshots/")
      return html_response(404, PUBLIC_NOT_FOUND_HTML, cache_control: "no-store") if request.get? && request.path_info.start_with?("/s/")
      return [ 404, missing_asset_headers, [ "Not found" ] ] if request.get? && request.path_info.start_with?("/assets/")

      json_response(404, { error: "Not found" })
    end

    def non_blank(value)
      stripped = value.to_s.strip
      stripped.empty? ? nil : stripped
    end

    def extract_upload_assets(payload)
      Array(payload["assets"]).map do |asset|
        raise Storage::ValidationError, "Each asset must be a JSON object" unless asset.is_a?(Hash)

        asset
      end
    end

    def html_response(status, html, cache_control:)
      [
        status,
        public_html_headers(cache_control: cache_control),
        [ html ]
      ]
    end

    def snapshot_html_response(status, html, cache_control:)
      [
        status,
        snapshot_html_headers(cache_control: cache_control),
        [ html ]
      ]
    end

    def json_headers
      {
        "Content-Type" => "application/json; charset=utf-8",
        "Cache-Control" => "no-store",
        "X-Content-Type-Options" => "nosniff"
      }
    end

    def public_html_headers(cache_control:)
      {
        "Content-Type" => "text/html; charset=utf-8",
        "Cache-Control" => cache_control,
        "Content-Security-Policy" => public_content_security_policy,
        "Permissions-Policy" => "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()",
        "Referrer-Policy" => "no-referrer",
        "X-Content-Type-Options" => "nosniff",
        "X-Frame-Options" => "DENY",
        "X-Robots-Tag" => "noindex, nofollow, noarchive",
        "Cross-Origin-Resource-Policy" => "same-origin"
      }
    end

    def snapshot_html_headers(cache_control:)
      {
        "Content-Type" => "text/html; charset=utf-8",
        "Cache-Control" => cache_control,
        "Content-Security-Policy" => snapshot_content_security_policy,
        "Permissions-Policy" => "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()",
        "Referrer-Policy" => "no-referrer",
        "X-Content-Type-Options" => "nosniff",
        "X-Frame-Options" => "SAMEORIGIN",
        "X-Robots-Tag" => "noindex, nofollow, noarchive",
        "Cross-Origin-Resource-Policy" => "same-origin"
      }
    end

    def asset_headers(content_type:)
      {
        "Content-Type" => content_type,
        "Cache-Control" => "public, max-age=300",
        "X-Content-Type-Options" => "nosniff",
        "Cross-Origin-Resource-Policy" => "same-origin"
      }
    end

    def missing_asset_headers
      {
        "Content-Type" => "text/plain; charset=utf-8",
        "Cache-Control" => "no-store",
        "X-Content-Type-Options" => "nosniff",
        "Cross-Origin-Resource-Policy" => "same-origin"
      }
    end

    def reader_asset_for(path_info)
      READER_ASSETS[path_info] || theme_reader_asset_for(path_info)
    end

    def render_reader_asset(reader_asset)
      asset_path = instance_exec(&reader_asset[:path])
      raise Storage::NotFoundError unless asset_path.file?

      [
        200,
        asset_headers(content_type: reader_asset[:content_type]),
        [ asset_path.read ]
      ]
    end

    def render_remote_reader_bundle_css
      [
        200,
        asset_headers(content_type: "text/css; charset=utf-8"),
        [ remote_reader_bundle_css_source ]
      ]
    end

    def remote_reader_bundle_css_source
      bundle_source = reader_public_path("remote_reader_bundle.css").read

      bundle_source
        .sub(
          '@import "/reader/assets/share_view.css"; /* inlined by the share-api asset server */',
          share_view_css_source
        )
        .sub(
          '@import "/reader/assets/outline.css"; /* inlined by the share-api asset server */',
          outline_css_source
        )
    end

    def share_view_css_source
      reader_public_path("share_view.css").read
    end

    def outline_css_source
      reader_public_path("outline.css").read
    end

    def reader_public_path(*parts)
      Pathname.new(__dir__).join("public", "reader", *parts)
    end

    def public_content_security_policy
      [
        "default-src 'none'",
        "base-uri 'none'",
        "connect-src 'none'",
        "font-src 'self' data:",
        "form-action 'none'",
        "frame-ancestors 'none'",
        "frame-src 'self'",
        "img-src 'self' data: https:",
        "manifest-src 'none'",
        "media-src 'self' data: https:",
        "object-src 'none'",
        "script-src 'self'",
        "style-src 'self' 'unsafe-inline'",
        "worker-src 'none'"
      ].join("; ")
    end

    def snapshot_content_security_policy
      [
        "default-src 'none'",
        "base-uri 'none'",
        "connect-src 'none'",
        "font-src 'self' data:",
        "form-action 'none'",
        "frame-ancestors 'self'",
        "img-src 'self' data: https:",
        "manifest-src 'none'",
        "media-src 'self' data: https:",
        "object-src 'none'",
        "script-src 'none'",
        "style-src 'unsafe-inline'",
        "worker-src 'none'"
      ].join("; ")
    end

    def build_snapshot_document(payload, sanitized_fragment)
      snapshot_document_html = payload["snapshot_document_html"].to_s
      return legacy_snapshot_document(payload: payload, fragment_html: sanitized_fragment) if snapshot_document_html.strip.empty?

      document = parse_snapshot_document(snapshot_document_html)
      style_blocks = document.css("head style").map { |node| node.text.to_s }.reject { |css| css.to_s.strip.empty? }
      title = non_blank(payload["title"]) || "LewisMD Share"
      locale = non_blank(payload["locale"]) || non_blank(document.at_css("html")&.[]("lang")) || "en"
      theme_id = non_blank(payload["theme_id"]) || non_blank(document.at_css("html")&.[]("data-theme"))
      color_scheme = extract_snapshot_color_scheme(document, theme_id)

      snapshot_document_markup(
        title: title,
        locale: locale,
        theme_id: theme_id,
        color_scheme: color_scheme,
        style_blocks: style_blocks,
        fragment_html: sanitized_fragment
      )
    end

    def read_snapshot_document_with_fallback(token:, share:)
      storage.read_snapshot_document(token)
    rescue Storage::NotFoundError
      legacy_snapshot_document(payload: share, fragment_html: storage.read_fragment(token))
    end

    def parse_snapshot_document(snapshot_document_html)
      if defined?(Nokogiri::HTML5)
        Nokogiri::HTML5(snapshot_document_html)
      else
        Nokogiri::HTML.parse(snapshot_document_html)
      end
    rescue StandardError
      Nokogiri::HTML.parse(snapshot_document_html)
    end

    def extract_snapshot_color_scheme(document, theme_id)
      declared = document.at_css('meta[name="color-scheme"]')&.[]("content").to_s.strip.downcase
      return declared if %w[light dark].include?(declared)

      inferred_light_theme?(theme_id) ? "light" : "dark"
    end

    def inferred_light_theme?(theme_id)
      %w[light solarized-light catppuccin-latte rose-pine flexoki-light].include?(theme_id.to_s)
    end

    def legacy_snapshot_document(payload:, fragment_html:)
      snapshot_document_markup(
        title: non_blank(payload["title"]) || "LewisMD Share",
        locale: non_blank(payload["locale"]) || "en",
        theme_id: non_blank(payload["theme_id"]),
        color_scheme: inferred_light_theme?(payload["theme_id"]) ? "light" : "dark",
        style_blocks: [],
        fragment_html: fragment_html
      )
    end

    def snapshot_document_markup(title:, locale:, theme_id:, color_scheme:, style_blocks:, fragment_html:)
      theme_attribute = theme_id.to_s.strip.empty? ? "" : %( data-theme="#{CGI.escapeHTML(theme_id)}")
      combined_style_blocks = Array(style_blocks) + [ remote_snapshot_layout_overrides_css ]
      style_markup = combined_style_blocks.map { |css| "<style>\n#{css.to_s.gsub(%r{</style}i, '<\\/style')}\n</style>" }.join("\n    ")
      head_parts = [
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        %(<meta name="color-scheme" content="#{CGI.escapeHTML(color_scheme)}">),
        %(<title>#{CGI.escapeHTML(title)}</title>)
      ]
      head_parts << style_markup unless style_markup.empty?

      <<~HTML
        <!doctype html>
        <html lang="#{CGI.escapeHTML(locale)}"#{theme_attribute}>
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

    def remote_snapshot_layout_overrides_css
      <<~CSS
        html {
          min-height: 100%;
        }

        *,
        *::before,
        *::after {
          box-sizing: border-box;
        }

        body {
          min-height: 100vh;
          overflow-wrap: anywhere;
        }

        .export-shell {
          padding:
            clamp(1.25rem, 2vw + 0.9rem, 3rem)
            clamp(0.95rem, 1.6vw + 0.65rem, 1.5rem);
        }

        .export-article {
          width: min(100%, 72ch);
          max-width: min(100%, 72ch);
          overflow-wrap: break-word;
        }

        .export-article img,
        .export-article video,
        .export-article iframe {
          max-width: 100%;
        }

        @media (max-width: 1023px) {
          .export-shell {
            padding:
              clamp(1.1rem, 1.5vw + 0.9rem, 1.8rem)
              clamp(0.9rem, 1.3vw + 0.7rem, 1.2rem);
          }
        }

        @media (max-width: 768px) {
          .export-shell {
            padding: 1.15rem 0.9rem 1.8rem;
          }

          .export-article {
            line-height: 1.65;
          }

          .export-article table {
            display: block;
            overflow-x: auto;
            -webkit-overflow-scrolling: touch;
            font-size: 0.8125em;
          }
        }
      CSS
    end

    def theme_reader_asset_for(path_info)
      match = path_info.match(%r{\A/reader/assets/themes/([a-z0-9-]+\.css)\z})
      return nil unless match

      filename = match[1]
      path = reader_public_path("themes", filename)
      return nil unless path.file?

      {
        content_type: "text/css; charset=utf-8",
        path: -> { path }
      }
    end

    def palette_icon_markup
      <<~SVG.chomp
        <svg class="share-view__toolbar-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zm0 0h12a2 2 0 002-2v-4a2 2 0 00-2-2h-2.343M11 7.343l1.657-1.657a2 2 0 012.828 0l2.829 2.829a2 2 0 010 2.828l-8.486 8.485M7 17h.01" />
        </svg>
      SVG
    end

    def language_icon_markup
      <<~SVG.chomp
        <svg class="share-view__toolbar-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 5h12M9 3v2m1.048 9.5A18.022 18.022 0 016.412 9m6.088 9h7M11 21l5-10 5 10M12.751 5C11.783 10.77 8.07 15.61 3 18.129" />
        </svg>
      SVG
    end

    def share_icon_markup
      <<~SVG.chomp
        <svg class="share-view__toolbar-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.684 13.342C9.886 12.511 11.36 12 13 12c1.64 0 3.114.511 4.316 1.342m-8.632 0A8.966 8.966 0 004 21h18a8.966 8.966 0 00-4.684-7.658m-8.632 0a5.002 5.002 0 118.632 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
        </svg>
      SVG
    end

    def outline_icon_markup
      <<~SVG.chomp
        <svg class="share-view__toolbar-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.75" d="M6.75 6.75h10.5M6.75 12h8.5M6.75 17.25h6.5" />
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.75" d="M4.5 6.75h.01M4.5 12h.01M4.5 17.25h.01" />
        </svg>
      SVG
    end

    def display_icon_markup
      <<~SVG.chomp
        <svg class="share-view__toolbar-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h10M4 18h7" />
        </svg>
      SVG
    end

    def caret_icon_markup
      <<~SVG.chomp
        <svg class="share-view__toolbar-caret" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
        </svg>
      SVG
    end
  end
end
