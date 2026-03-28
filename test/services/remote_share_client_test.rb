# frozen_string_literal: true

require "test_helper"

class RemoteShareClientTest < ActiveSupport::TestCase
  def setup
    setup_test_notes_dir
    @config = Config.new(base_path: @test_notes_dir)
    @config.update(
      share_remote_api_host: "shares.example.com",
      share_remote_api_port: 443,
      share_remote_public_base: "https://shares.example.com",
      share_remote_api_token: "token-123",
      share_remote_signing_secret: "signing-secret"
    )
    @client = RemoteShareClient.new(config: @config)
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def teardown
    WebMock.reset!
    WebMock.allow_net_connect!
    teardown_test_notes_dir
  end

  test "fetch_capabilities caches the capabilities payload" do
    stub_request(:get, "https://shares.example.com/api/v1/capabilities")
      .to_return(status: 200, body: { api_version: "1", feature_flags: { asset_uploads: true, full_share_shell: true }, max_expiration_days: 365 }.to_json)

    capabilities = @client.fetch_capabilities

    assert_equal "1", capabilities["api_version"]
    assert_equal 365, capabilities["max_expiration_days"]
    assert_equal capabilities, @client.last_capabilities
  end

  test "fetch_capabilities always verifies tls even when the legacy setting is false" do
    @config.update(share_remote_verify_tls: false)

    http = mock("http")
    request = mock("request")
    response = stub(body: { api_version: "1" }.to_json, code: "200")

    Net::HTTP.expects(:new).with("shares.example.com", 443).returns(http)
    http.expects(:use_ssl=).with(true)
    http.expects(:open_timeout=).with(10)
    http.expects(:read_timeout=).with(10)
    http.expects(:use_ssl?).returns(true)
    http.expects(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
    Net::HTTP::Get.expects(:new).returns(request)
    request.stubs(:[]=)
    http.expects(:request).with(request).returns(response)
    response.stubs(:is_a?).with(Net::HTTPSuccess).returns(true)

    capabilities = @client.fetch_capabilities

    assert_equal "1", capabilities["api_version"]
  end

  test "create_share sends signed authenticated requests and returns the public url" do
    stub_request(:get, "https://shares.example.com/api/v1/capabilities")
      .to_return(status: 200, body: { api_version: "1" }.to_json)

    stub_request(:post, "https://shares.example.com/api/v1/shares")
      .with do |request|
        body = JSON.parse(request.body)

        request.headers["Authorization"] == "Bearer token-123" &&
          request.headers["X-Lewismd-Signature"].present? &&
          request.headers["X-Lewismd-Request-Id"].present? &&
          request.headers["X-Lewismd-Timestamp"].present? &&
          body["title"] == "Shared Note" &&
          body["snapshot_document_html"].include?("export-article") &&
          body["expires_at"] == "2026-04-08T12:00:00Z"
      end
      .to_return(
        status: 201,
        body: {
          token: "remote-share-1234",
          public_url: "https://shares.example.com/s/remote-share-1234",
          title: "Shared Note",
          created_at: "2026-03-25T12:00:00Z",
          updated_at: "2026-03-25T12:00:00Z"
        }.to_json
      )

    share = @client.create_share(
      title: "Shared Note",
      html_fragment: "<p>Hello</p>",
      snapshot_document_html: "<!DOCTYPE html><html><body><main class=\"export-shell\"><article class=\"export-article\"><p>Hello</p></article></main></body></html>",
      shell_payload: { title: "Shared Note", locale: "en", theme_id: "dark" },
      expires_at: "2026-04-08T12:00:00Z"
    )

    assert_equal "remote-share-1234", share[:token]
    assert_equal "https://shares.example.com/s/remote-share-1234", share[:url]
    assert_equal "Shared Note", share[:title]
  end

  test "update_share derives the public url when the API omits it" do
    stub_request(:get, "https://shares.example.com/api/v1/capabilities")
      .to_return(status: 200, body: { api_version: "1" }.to_json)

    stub_request(:put, "https://shares.example.com/api/v1/shares/remote-share-1234")
      .to_return(
        status: 200,
        body: {
          token: "remote-share-1234",
          title: "Shared Note",
          updated_at: "2026-03-25T12:05:00Z"
        }.to_json
      )

    share = @client.update_share(
      token: "remote-share-1234",
      payload: {
        title: "Shared Note",
        html_fragment: "<p>Hello</p>",
        snapshot_document_html: "<!DOCTYPE html><html><body><article class=\"export-article\"><p>Hello</p></article></body></html>"
      }
    )

    assert_equal "https://shares.example.com/s/remote-share-1234", share[:url]
  end

  test "fetch_capabilities raises when the API requires a newer client" do
    stub_request(:get, "https://shares.example.com/api/v1/capabilities")
      .to_return(status: 200, body: { api_version: "1", minimum_client_version: 2 }.to_json)

    error = assert_raises(RemoteShareClient::CompatibilityError) do
      @client.fetch_capabilities
    end

    assert_includes error.message, "newer LewisMD client"
  end

  test "revoke_share surfaces API errors with status codes" do
    stub_request(:get, "https://shares.example.com/api/v1/capabilities")
      .to_return(status: 200, body: { api_version: "1" }.to_json)

    stub_request(:delete, "https://shares.example.com/api/v1/shares/remote-share-1234")
      .to_return(status: 403, body: { error: "Forbidden" }.to_json)

    error = assert_raises(RemoteShareClient::RequestError) do
      @client.revoke_share(token: "remote-share-1234")
    end

    assert_equal 403, error.status
    assert_equal "Forbidden", error.message
  end

  test "fetch_admin_status returns share counts and storage writability" do
    stub_request(:get, "https://shares.example.com/api/v1/capabilities")
      .to_return(status: 200, body: { api_version: "1", feature_flags: { admin_status: true } }.to_json)

    stub_request(:get, "https://shares.example.com/api/v1/admin/status")
      .with do |request|
        request.headers["Authorization"] == "Bearer token-123" &&
          request.headers["X-Lewismd-Signature"].present?
      end
      .to_return(
        status: 200,
        body: {
          share_count: 4,
          storage_writable: true,
          checked_at: "2026-03-27T12:00:00Z"
        }.to_json
      )

    status = @client.fetch_admin_status

    assert_equal 4, status["share_count"]
    assert_equal true, status["storage_writable"]
  end

  test "delete_all_shares returns deleted metadata" do
    stub_request(:get, "https://shares.example.com/api/v1/capabilities")
      .to_return(status: 200, body: { api_version: "1", feature_flags: { admin_bulk_delete: true } }.to_json)

    stub_request(:delete, "https://shares.example.com/api/v1/admin/shares")
      .to_return(
        status: 200,
        body: {
          deleted: true,
          deleted_count: 7,
          cleanup: {
            removed_tokens: [ "remote-share-1234" ],
            orphan_snapshot_dirs_deleted: 1,
            orphan_asset_dirs_deleted: 1
          }
        }.to_json
      )

    result = @client.delete_all_shares

    assert_equal true, result["deleted"]
    assert_equal 7, result["deleted_count"]
    assert_equal 1, result.dig("cleanup", "orphan_snapshot_dirs_deleted")
  end

  test "create_share surfaces actionable guidance when the VPS returns an empty 500" do
    stub_request(:get, "https://shares.example.com/api/v1/capabilities")
      .to_return(status: 200, body: { api_version: "1" }.to_json)

    stub_request(:post, "https://shares.example.com/api/v1/shares")
      .to_return(status: 500, body: "")

    error = assert_raises(RemoteShareClient::RequestError) do
      @client.create_share(
        title: "Shared Note",
        html_fragment: "<p>Hello</p>",
        snapshot_document_html: "<!DOCTYPE html><html><body><main class=\"export-shell\"><article class=\"export-article\"><p>Hello</p></article></main></body></html>"
      )
    end

    assert_equal 500, error.status
    assert_includes error.message, "Check the share-api container logs on the VPS"
    assert_includes error.message, "storage write permissions"
  end
end
