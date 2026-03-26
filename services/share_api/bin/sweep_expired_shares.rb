#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/share_api/configuration"
require_relative "../lib/share_api/storage"

begin
  config = ShareAPI::Configuration.new
  storage = ShareAPI::Storage.new(
    storage_path: config.storage_path,
    max_asset_bytes: config.max_asset_bytes,
    max_asset_count: config.max_asset_count
  )
  checked_at = Time.now.utc.iso8601

  removed_tokens = storage.sweep_expired_shares!
  storage.write_sweeper_report!(
    checked_at: checked_at,
    status: "ok",
    removed_tokens: removed_tokens
  )

  $stdout.puts(
    JSON.generate(
      checked_at: checked_at,
      removed_count: removed_tokens.length,
      removed_tokens: removed_tokens
    )
  )
rescue StandardError => e
  begin
    storage&.write_sweeper_report!(
      checked_at: checked_at || Time.now.utc.iso8601,
      status: "failed",
      removed_tokens: [],
      error: e.message
    )
  rescue StandardError
    nil
  end

  raise
end
