# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "securerandom"
require "uri"

class RemoteShareClient
  CLIENT_VERSION = 1

  class Error < StandardError; end
  class ConfigurationError < Error; end
  class CompatibilityError < Error; end

  class RequestError < Error
    attr_reader :status

    def initialize(message, status: nil)
      super(message)
      @status = status
    end
  end

  def initialize(config: Config.new)
    @config = config
    @last_capabilities = nil
  end

  attr_reader :last_capabilities

  def fetch_capabilities
    response = perform_request(
      method: :get,
      path: "/api/v1/capabilities",
      body: nil,
      authenticated: false
    )

    parsed = parse_json(response)
    api_version = parsed["api_version"].to_s.strip
    raise CompatibilityError, "Remote share API did not report an api_version" if api_version.blank?

    minimum_client_version = parsed["minimum_client_version"] || parsed["min_client_version"]
    if minimum_client_version.present? && minimum_client_version.to_i > CLIENT_VERSION
      raise CompatibilityError, "Remote share API requires a newer LewisMD client"
    end

    @last_capabilities = parsed
  end

  def create_share(payload)
    ensure_capabilities!
    parsed = perform_json_request(
      method: :post,
      path: "/api/v1/shares",
      body: payload
    )

    normalize_share_response(parsed)
  end

  def update_share(token:, payload:)
    ensure_capabilities!
    parsed = perform_json_request(
      method: :put,
      path: "/api/v1/shares/#{URI.encode_uri_component(token)}",
      body: payload
    )

    normalize_share_response(parsed, fallback_token: token)
  end

  def revoke_share(token:)
    ensure_capabilities!
    perform_request(
      method: :delete,
      path: "/api/v1/shares/#{URI.encode_uri_component(token)}",
      body: nil
    )

    true
  end

  def fetch_admin_status
    ensure_capabilities!
    perform_json_request(
      method: :get,
      path: "/api/v1/admin/status",
      body: nil
    )
  end

  def delete_all_shares
    ensure_capabilities!
    perform_json_request(
      method: :delete,
      path: "/api/v1/admin/shares",
      body: nil
    )
  end

  private

  attr_reader :config

  def ensure_capabilities!
    last_capabilities || fetch_capabilities
  end

  def perform_json_request(method:, path:, body:)
    response = perform_request(method: method, path: path, body: body)
    parse_json(response)
  end

  def perform_request(method:, path:, body:, authenticated: true)
    uri = endpoint_uri(path)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = timeout_seconds
    http.read_timeout = timeout_seconds
    http.verify_mode = verify_tls? ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE

    request_class = case method.to_sym
    when :get then Net::HTTP::Get
    when :post then Net::HTTP::Post
    when :put then Net::HTTP::Put
    when :delete then Net::HTTP::Delete
    else
      raise ConfigurationError, "Unsupported remote share request method: #{method}"
    end

    request = request_class.new(uri)
    request["Accept"] = "application/json"
    body_json = body.nil? ? nil : JSON.generate(body)
    request["Content-Type"] = "application/json" if body_json
    request.body = body_json if body_json

    apply_auth_headers!(request:, method:, path:, body_json:) if authenticated

    response = http.request(request)
    return response if response.is_a?(Net::HTTPSuccess)

    message = parse_error_message(response)
    raise RequestError.new(message, status: response.code.to_i)
  rescue SocketError, SystemCallError, Timeout::Error, IOError, OpenSSL::SSL::SSLError => e
    raise RequestError, "Remote share API request failed: #{e.message}"
  end

  def apply_auth_headers!(request:, method:, path:, body_json:)
    token = config.get("share_remote_api_token").to_s.strip
    signing_secret = config.get("share_remote_signing_secret").to_s

    raise ConfigurationError, "Remote share API token is not configured" if token.blank?
    raise ConfigurationError, "Remote share signing secret is not configured" if signing_secret.blank?

    timestamp = Time.current.to_i.to_s
    request_id = SecureRandom.uuid
    signature_payload = [
      timestamp,
      request_id,
      method.to_s.upcase,
      path,
      body_json.to_s
    ].join("\n")

    signature = OpenSSL::HMAC.hexdigest("SHA256", signing_secret, signature_payload)

    request["Authorization"] = "Bearer #{token}"
    request["X-LewisMD-Timestamp"] = timestamp
    request["X-LewisMD-Request-Id"] = request_id
    request["X-LewisMD-Signature"] = signature
    request["X-LewisMD-Client-Version"] = CLIENT_VERSION.to_s
  end

  def parse_json(response)
    JSON.parse(response.body.presence || "{}")
  rescue JSON::ParserError
    raise RequestError.new("Remote share API returned invalid JSON", status: response.code.to_i)
  end

  def parse_error_message(response)
    parsed = JSON.parse(response.body.presence || "{}")
    parsed["error"].presence || non_json_error_message(response)
  rescue JSON::ParserError
    non_json_error_message(response)
  end

  def non_json_error_message(response)
    body_text = response.body.to_s.gsub(%r{<[^>]+>}, " ").gsub(/\s+/, " ").strip
    return "Remote share API request failed with status #{response.code}: #{body_text[0, 160]}" if body_text.present?

    if response.code.to_i >= 500
      "Remote share API request failed with status #{response.code}. Check the share-api container logs on the VPS. A common cause is share storage write permissions."
    else
      "Remote share API request failed with status #{response.code}"
    end
  end

  def normalize_share_response(parsed, fallback_token: nil)
    token = parsed["token"].presence || fallback_token
    raise RequestError, "Remote share API response did not include a token" if token.blank?

    {
      token: token,
      url: parsed["public_url"].presence || parsed["url"].presence || derive_public_url(token),
      title: parsed["title"],
      created_at: parsed["created_at"],
      updated_at: parsed["updated_at"],
      expires_at: parsed["expires_at"]
    }
  end

  def derive_public_url(token)
    public_base = config.get("share_remote_public_base").to_s.strip
    raise ConfigurationError, "Remote share public base is not configured" if public_base.blank?

    "#{public_base.chomp('/')}/s/#{token}"
  end

  def endpoint_uri(path)
    scheme = config.get("share_remote_api_scheme").to_s.strip.presence || "https"
    host = config.get("share_remote_api_host").to_s.strip
    raise ConfigurationError, "Remote share API host is not configured" if host.blank?

    port = config.get("share_remote_api_port").to_i
    port = 443 if port <= 0 && scheme == "https"
    port = 80 if port <= 0 && scheme == "http"

    base = URI::Generic.build(scheme: scheme, host: host, port: port)
    URI.join("#{base}/", path.delete_prefix("/"))
  rescue URI::InvalidComponentError, URI::InvalidURIError => e
    raise ConfigurationError, "Remote share API configuration is invalid: #{e.message}"
  end

  def timeout_seconds
    timeout = config.get("share_remote_timeout_seconds").to_i
    timeout.positive? ? timeout : 10
  end

  def verify_tls?
    config.get("share_remote_verify_tls") != false
  end
end
