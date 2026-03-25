# frozen_string_literal: true

require "test_helper"

class ShareProviderSelectorTest < ActiveSupport::TestCase
  def setup
    setup_test_notes_dir
    create_test_note("shared-note.md", "# Shared\n\nContent")
  end

  def teardown
    teardown_test_notes_dir
  end

  test "selects the local share provider by default" do
    provider = ShareProviderSelector.new(base_path: @test_notes_dir).provider

    assert_instance_of SharePublishers::LocalShareProvider, provider
  end

  test "selects the remote share provider when configured" do
    Config.new(base_path: @test_notes_dir).set(:share_backend, "remote")

    provider = ShareProviderSelector.new(base_path: @test_notes_dir).provider

    assert_instance_of SharePublishers::RemoteShareProvider, provider
  end

  test "falls back to local provider for unknown backends" do
    Config.new(base_path: @test_notes_dir).set(:share_backend, "unsupported")

    selector = ShareProviderSelector.new(base_path: @test_notes_dir)

    assert_equal "local", selector.backend
    assert_instance_of SharePublishers::LocalShareProvider, selector.provider
  end

  test "remote share provider is ready for remote registry-backed publishing" do
    Config.new(base_path: @test_notes_dir).set(:share_backend, "remote")
    provider = ShareProviderSelector.new(base_path: @test_notes_dir).provider

    assert_instance_of SharePublishers::RemoteShareProvider, provider
    assert_nil provider.active_share_for("shared-note.md")
  end
end
