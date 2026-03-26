#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/share_api/configuration"
require_relative "../lib/share_api/storage"

config = ShareAPI::Configuration.new
storage = ShareAPI::Storage.new(
  storage_path: config.storage_path,
  max_asset_bytes: config.max_asset_bytes,
  max_asset_count: config.max_asset_count
)

storage.verify_write_access!

$stdout.puts(
  JSON.generate(
    status: "ok",
    storage_path: config.storage_path
  )
)
