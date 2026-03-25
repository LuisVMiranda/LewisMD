# frozen_string_literal: true

require "json"
require "openssl"
require "rack/utils"

module ShareAPI
  class Authenticator
    class UnauthorizedError < StandardError; end
    class ReplayError < StandardError; end

    def initialize(config:, storage:)
      @config = config
      @storage = storage
    end

    def authenticate!(request:, body:)
      token = bearer_token(request)
      raise UnauthorizedError, "Missing bearer token" if token.empty?
      raise UnauthorizedError, "Invalid bearer token" unless secure_compare(token, config.api_token)

      timestamp = request.get_header("HTTP_X_LEWISMD_TIMESTAMP").to_s
      request_id = request.get_header("HTTP_X_LEWISMD_REQUEST_ID").to_s
      signature = request.get_header("HTTP_X_LEWISMD_SIGNATURE").to_s

      raise UnauthorizedError, "Missing signature headers" if timestamp.empty? || request_id.empty? || signature.empty?

      timestamp_i = Integer(timestamp, exception: false)
      raise UnauthorizedError, "Invalid timestamp" unless timestamp_i

      now = Time.now.to_i
      raise UnauthorizedError, "Request timestamp is outside the allowed window" if (now - timestamp_i).abs > config.replay_window_seconds

      storage.prune_nonces!(before: now - config.replay_window_seconds)
      raise ReplayError, "Request has already been processed" if storage.nonce_seen?(request_id: request_id)

      expected_signature = OpenSSL::HMAC.hexdigest(
        "SHA256",
        config.signing_secret,
        [
          timestamp,
          request_id,
          request.request_method.upcase,
          request.path_info,
          body.to_s
        ].join("\n")
      )

      raise UnauthorizedError, "Invalid request signature" unless secure_compare(signature, expected_signature)

      storage.remember_nonce!(request_id: request_id, timestamp: timestamp_i)
    end

    private

    attr_reader :config, :storage

    def bearer_token(request)
      header = request.get_header("HTTP_AUTHORIZATION").to_s
      header.start_with?("Bearer ") ? header.delete_prefix("Bearer ").strip : ""
    end

    def secure_compare(left, right)
      return false if left.to_s.empty? || right.to_s.empty?
      return false unless left.bytesize == right.bytesize

      Rack::Utils.secure_compare(left, right)
    end
  end
end
