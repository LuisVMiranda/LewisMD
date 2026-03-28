# frozen_string_literal: true

class ShareManagementController < ApplicationController
  wrap_parameters false

  SECURITY_WARNING_SEVERITIES = %w[info warning danger].freeze

  before_action :set_config

  def show
    render json: share_management_payload
  end

  def update
    updates = permitted_share_management_updates
    if updates.empty?
      render json: { error: t("errors.no_valid_settings") }, status: :unprocessable_entity
      return
    end

    updates["share_remote_verify_tls"] = true

    if @config.update(updates)
      @config = Config.new(base_path: @config.base_path)
      render json: share_management_payload(message: t("share_management.settings_saved", default: "Share API settings saved."))
    else
      render json: { error: t("errors.failed_to_save") }, status: :unprocessable_entity
    end
  end

  def recheck
    render json: share_management_payload(
      message: t("share_management.recheck_complete", default: "Share API status refreshed.")
    )
  end

  def published
    render json: {
      published_shares: published_shares_overview.list
    }
  end

  def destroy_published
    row = published_shares_overview.find(params[:token])
    return render json: { error: t("errors.share_not_found", default: "Share not found") }, status: :not_found unless row

    deletion_result = delete_published_share(row)

    render json: {
      deleted: true,
      token: row[:token],
      backend: row[:backend],
      path: row[:path],
      note_identifier: row[:note_identifier],
      remote_missing: deletion_result[:remote_missing] == true,
      message: deletion_result[:message]
    }
  rescue ShareService::NotFoundError
    render json: { error: t("errors.share_not_found", default: "Share not found") }, status: :not_found
  rescue ShareService::InvalidShareError, RemoteShareClient::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    unless remote_backend?
      render json: {
        error: t(
          "errors.share_management_remote_only",
          default: "Delete all shared notes is only available when remote sharing is enabled."
        )
      }, status: :unprocessable_entity
      return
    end

    remote_result = remote_client.delete_all_shares
    deleted_count = remote_registry.delete_all

    render json: share_management_payload(
      message: t(
        "share_management.bulk_delete_success",
        count: remote_result["deleted_count"] || deleted_count,
        default: "Deleted %{count} shared notes from the remote API."
      ),
      deleted: true,
      deleted_count: remote_result["deleted_count"] || deleted_count,
      cleanup: remote_result["cleanup"]
    )
  rescue RemoteShareClient::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_config
    @config = Config.new
  end

  def share_management_payload(message: nil, deleted: false, deleted_count: nil, cleanup: nil)
    payload = {
      settings: @config.share_management_settings,
      status: share_management_status
    }
    payload[:message] = message if message.present?
    payload[:deleted] = deleted if deleted
    payload[:deleted_count] = deleted_count if deleted_count
    payload[:cleanup] = cleanup if cleanup.is_a?(Hash) && cleanup.present?
    payload
  end

  def share_management_status
    backend = share_provider_selector.backend
    status = {
      backend: backend,
      remote_enabled: backend == "remote",
      public_base: @config.get("share_remote_public_base"),
      local_default_expiration_days: configured_expiration_days,
      remote_max_expiration_days: nil,
      capabilities: {},
      reachable: nil,
      admin_enabled: false,
      remote_share_count: nil,
      storage_writable: nil,
      checked_at: Time.current.iso8601,
      message: t("share_management.local_mode_message", default: "Local sharing stores snapshots on this machine."),
      warnings: []
    }

    return append_share_management_warnings(status) unless backend == "remote"

    capabilities = remote_client.fetch_capabilities
    feature_flags = capabilities["feature_flags"].is_a?(Hash) ? capabilities["feature_flags"] : {}
    status[:capabilities] = feature_flags
    status[:remote_max_expiration_days] = positive_integer(capabilities["max_expiration_days"])
    status[:max_payload_bytes] = positive_integer(capabilities["max_payload_bytes"])
    status[:max_asset_bytes] = positive_integer(capabilities["max_asset_bytes"])
    status[:max_asset_count] = positive_integer(capabilities["max_asset_count"])
    status[:reachable] = true
    status[:message] = t("share_management.remote_reachable", default: "Remote share API is reachable.")

    return append_share_management_warnings(status) unless feature_flags["admin_status"]

    admin_status = remote_client.fetch_admin_status
    status[:admin_enabled] = true
    status[:remote_share_count] = admin_status["share_count"]
    status[:storage_writable] = admin_status["storage_writable"]
    status[:checked_at] = admin_status["checked_at"] || status[:checked_at]
    status[:instance_name] = admin_status["instance_name"] if admin_status["instance_name"].present?
    append_share_management_warnings(status)
  rescue RemoteShareClient::Error => e
    status[:reachable] = false
    status[:error] = e.message
    status[:message] = t("share_management.remote_unreachable", default: "Remote share API couldn't be reached.")
    append_share_management_warnings(status)
  end

  def permitted_share_management_updates
    params
      .permit(*Config::SHARE_MANAGEMENT_KEYS)
      .to_h
      .reject { |key, value| Config::SENSITIVE_KEYS.include?(key) && value.to_s.strip.empty? }
  end

  def append_share_management_warnings(status)
    status[:warnings] = build_share_management_warnings(status)
    status
  end

  def build_share_management_warnings(status)
    warnings = []

    if @config.get("share_remote_verify_tls") == false
      warnings << security_warning(
        id: "legacy_insecure_tls_config",
        severity: "danger",
        title: t("share_management.warnings.legacy_tls_title", default: "Legacy insecure TLS setting detected"),
        message: t(
          "share_management.warnings.legacy_tls_message",
          default: "This config still contains share_remote_verify_tls = false from an older setup. LewisMD now always verifies HTTPS certificates and ignores the insecure legacy value."
        ),
        remediation: t(
          "share_management.warnings.legacy_tls_remediation",
          default: "Save the Manage API form once to rewrite the stored setting back to the secure default."
        )
      )
    end

    if remote_backend?
      unless https_value?(@config.get("share_remote_public_base")) && https_scheme?
        warnings << security_warning(
          id: "remote_endpoint_not_https",
          severity: "danger",
          title: t("share_management.warnings.https_title", default: "Remote share traffic is not fully HTTPS"),
          message: t(
            "share_management.warnings.https_message",
            default: "The remote share API scheme and public base should both use HTTPS for production publishing."
          ),
          remediation: t(
            "share_management.warnings.https_remediation",
            default: "Use an HTTPS public base and, with Cloudflare, set SSL/TLS mode to Full (strict)."
          )
        )
      end

      if status[:reachable] && !(status.dig(:capabilities, "admin_status") && status.dig(:capabilities, "admin_bulk_delete"))
        warnings << security_warning(
          id: "remote_admin_features_unavailable",
          severity: "warning",
          title: t("share_management.warnings.admin_title", default: "Remote admin features are unavailable"),
          message: t(
            "share_management.warnings.admin_message",
            default: "The remote share API is reachable, but it does not advertise the admin endpoints needed for status checks and bulk cleanup."
          ),
          remediation: t(
            "share_management.warnings.admin_remediation",
            default: "Upgrade the VPS share-api image so it exposes admin_status and admin_bulk_delete capabilities."
          )
        )
      end

      if status[:local_default_expiration_days] && status[:remote_max_expiration_days] &&
          status[:local_default_expiration_days] > status[:remote_max_expiration_days]
        warnings << security_warning(
          id: "remote_expiration_clamped",
          severity: "warning",
          title: t("share_management.warnings.expiry_title", default: "Local expiry exceeds the server maximum"),
          message: t(
            "share_management.warnings.expiry_message",
            default: "This LewisMD client is configured to request a longer default expiry than the remote share API allows."
          ),
          remediation: t(
            "share_management.warnings.expiry_remediation",
            default: "Lower the local default expiration days or raise the server maximum if that policy change is intentional."
          )
        )
      end

      if status[:max_payload_bytes] && status[:max_asset_bytes] &&
          status[:max_asset_bytes] > status[:max_payload_bytes] &&
          @config.get("share_remote_upload_assets") != false
        warnings << security_warning(
          id: "payload_limit_inconsistent",
          severity: "warning",
          title: t("share_management.warnings.payload_title", default: "Payload and asset size limits are inconsistent"),
          message: t(
            "share_management.warnings.payload_message",
            default: "The remote API reports a smaller overall payload cap than its per-asset limit, so large uploads may still be rejected."
          ),
          remediation: t(
            "share_management.warnings.payload_remediation",
            default: "Keep the total payload limit above the largest allowed asset size, or lower the asset cap to match."
          )
        )
      end

      warnings << security_warning(
        id: "cloudflare_edge_checklist",
        severity: "info",
        title: t("share_management.warnings.cloudflare_title", default: "Cloudflare edge hardening still needs operator confirmation"),
        message: t(
          "share_management.warnings.cloudflare_message",
          default: "This deployment expects a Cloudflare-proxied share hostname in front of Caddy. Cloudflare rate limiting and strict TLS are not configured from inside LewisMD."
        ),
        remediation: t(
          "share_management.warnings.cloudflare_remediation",
          default: "Confirm the hostname is orange-cloud proxied, set SSL/TLS mode to Full (strict), add the documented rate-limit rules, and restrict direct-origin access when possible."
        )
      )
    end

    warnings
  end

  def security_warning(id:, severity:, title:, message:, remediation:)
    raise ArgumentError, "Unsupported security warning severity" unless SECURITY_WARNING_SEVERITIES.include?(severity)

    {
      id: id,
      severity: severity,
      title: title,
      message: message,
      remediation: remediation
    }
  end

  def configured_expiration_days
    positive_integer(@config.get("share_remote_expiration_days"))
  end

  def positive_integer(value)
    integer = value.to_i
    integer.positive? ? integer : nil
  end

  def https_scheme?
    @config.get("share_remote_api_scheme").to_s.casecmp("https").zero?
  end

  def https_value?(value)
    value.to_s.strip.downcase.start_with?("https://")
  end

  def remote_backend?
    share_provider_selector.backend == "remote"
  end

  def remote_client
    @remote_client ||= RemoteShareClient.new(config: @config)
  end

  def remote_registry
    @remote_registry ||= RemoteShareRegistryService.new(base_path: @config.base_path)
  end

  def local_share_service
    @local_share_service ||= ShareService.new(base_path: @config.base_path)
  end

  def published_shares_overview
    @published_shares_overview ||= PublishedSharesOverviewService.new(base_path: @config.base_path)
  end

  def share_provider_selector
    @share_provider_selector ||= ShareProviderSelector.new(config: @config)
  end

  def delete_published_share(row)
    case row[:backend]
    when "local"
      local_share_service.revoke_by_token(row[:token])
      {
        message: t("share_management.published_deleted", default: "Published note deleted.")
      }
    when "remote"
      remote_missing = false

      begin
        remote_client.revoke_share(token: row[:token])
      rescue RemoteShareClient::RequestError => e
        if e.status == 404
          remote_missing = true
        else
          raise
        end
      end

      remote_registry.delete_by_token(row[:token])
      {
        remote_missing: remote_missing,
        message: if remote_missing
          t("share_management.published_deleted_stale_remote", default: "Published note was already gone remotely, so the local share record was cleaned up.")
        else
          t("share_management.published_deleted", default: "Published note deleted.")
        end
      }
    else
      raise ShareService::InvalidShareError, t("errors.share_not_found", default: "Share not found")
    end
  end
end
