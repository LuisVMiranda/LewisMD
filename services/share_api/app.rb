# frozen_string_literal: true

require "cgi"
require "json"
require "rack"
require_relative "lib/share_api/authenticator"
require_relative "lib/share_api/configuration"
require_relative "lib/share_api/fragment_sanitizer"
require_relative "lib/share_api/storage"

module ShareAPI
  class App
    TOKEN_PATTERN = /\A[a-zA-Z0-9\-_]{8,}\z/
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
      if request.get? && (match = request.path_info.match(%r{\A/s/([^/]+)\z}))
        return render_public_share(match[1])
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

    def render_public_share(token)
      validate_token!(token)
      share = storage.fetch_share(token)
      fragment_html = storage.read_fragment(token)
      title = CGI.escapeHTML(share["title"].to_s)
      html = <<~HTML
        <!doctype html>
        <html lang="#{CGI.escapeHTML(non_blank(share["locale"]) || "en")}" data-theme="#{CGI.escapeHTML(share["theme_id"].to_s)}">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="robots" content="noindex,nofollow,noarchive">
            <title>#{title}</title>
          </head>
          <body>
            <header>
              <p>LewisMD Share</p>
              <h1>#{title}</h1>
            </header>
            <main class="share-api__content" aria-label="Shared note content">
              #{fragment_html}
            </main>
            <footer>
              <p>Read-only snapshot</p>
            </footer>
          </body>
        </html>
      HTML

      html_response(200, html, cache_control: "public, max-age=60")
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
        "plain_text" => payload["plain_text"],
        "theme_id" => payload["theme_id"],
        "locale" => payload["locale"],
        "content_hash" => payload["content_hash"],
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
        "public_url" => public_url_for(request, share["token"])
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
          asset_uploads: true
        },
        max_payload_bytes: config.max_payload_bytes,
        max_asset_bytes: config.max_asset_bytes,
        max_asset_count: config.max_asset_count
      }
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
      return html_response(404, PUBLIC_NOT_FOUND_HTML, cache_control: "public, max-age=60") if request.get? && request.path_info.start_with?("/s/")
      return [ 404, asset_headers(content_type: "text/plain; charset=utf-8"), [ "Not found" ] ] if request.get? && request.path_info.start_with?("/assets/")

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

    def asset_headers(content_type:)
      {
        "Content-Type" => content_type,
        "Cache-Control" => "public, max-age=300",
        "X-Content-Type-Options" => "nosniff",
        "Cross-Origin-Resource-Policy" => "same-origin"
      }
    end

    def public_content_security_policy
      [
        "default-src 'none'",
        "base-uri 'none'",
        "connect-src 'none'",
        "font-src 'none'",
        "form-action 'none'",
        "frame-ancestors 'none'",
        "frame-src 'none'",
        "img-src 'self' data: https:",
        "manifest-src 'none'",
        "media-src 'self' data: https:",
        "object-src 'none'",
        "script-src 'none'",
        "style-src 'none'",
        "worker-src 'none'"
      ].join("; ")
    end
  end
end
