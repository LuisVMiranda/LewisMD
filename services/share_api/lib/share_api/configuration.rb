# frozen_string_literal: true

module ShareAPI
  class Configuration
    DEFAULT_REPLAY_WINDOW_SECONDS = 300
    DEFAULT_MAX_PAYLOAD_BYTES = 200_000
    DEFAULT_MAX_ASSET_BYTES = 5_000_000
    DEFAULT_MAX_ASSET_COUNT = 16

    def initialize(env: ENV, root: File.expand_path("../..", __dir__))
      @env = env
      @root = root
    end

    def storage_path
      env.fetch("LEWISMD_SHARE_STORAGE_PATH", File.join(root, "tmp", "share_api_storage"))
    end

    def api_token
      env["LEWISMD_SHARE_API_TOKEN"].to_s
    end

    def signing_secret
      env["LEWISMD_SHARE_SIGNING_SECRET"].to_s
    end

    def public_base
      env["LEWISMD_SHARE_PUBLIC_BASE"].to_s
    end

    def instance_name
      env["LEWISMD_SHARE_INSTANCE_NAME"].to_s
    end

    def replay_window_seconds
      integer_env("LEWISMD_SHARE_REPLAY_WINDOW_SECONDS", DEFAULT_REPLAY_WINDOW_SECONDS)
    end

    def max_payload_bytes
      integer_env("LEWISMD_SHARE_MAX_PAYLOAD_BYTES", DEFAULT_MAX_PAYLOAD_BYTES)
    end

    def max_asset_bytes
      integer_env("LEWISMD_SHARE_MAX_ASSET_BYTES", DEFAULT_MAX_ASSET_BYTES)
    end

    def max_asset_count
      integer_env("LEWISMD_SHARE_MAX_ASSET_COUNT", DEFAULT_MAX_ASSET_COUNT)
    end

    private

    attr_reader :env, :root

    def integer_env(key, default)
      value = env[key].to_i
      value.positive? ? value : default
    end
  end
end
