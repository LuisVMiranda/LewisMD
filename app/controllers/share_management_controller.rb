# frozen_string_literal: true

class ShareManagementController < ApplicationController
  wrap_parameters false

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
      capabilities: {},
      reachable: nil,
      admin_enabled: false,
      remote_share_count: nil,
      storage_writable: nil,
      checked_at: Time.current.iso8601,
      message: t("share_management.local_mode_message", default: "Local sharing stores snapshots on this machine.")
    }

    return status unless backend == "remote"

    capabilities = remote_client.fetch_capabilities
    feature_flags = capabilities["feature_flags"].is_a?(Hash) ? capabilities["feature_flags"] : {}
    status[:capabilities] = feature_flags
    status[:reachable] = true
    status[:message] = t("share_management.remote_reachable", default: "Remote share API is reachable.")

    return status unless feature_flags["admin_status"]

    admin_status = remote_client.fetch_admin_status
    status[:admin_enabled] = true
    status[:remote_share_count] = admin_status["share_count"]
    status[:storage_writable] = admin_status["storage_writable"]
    status[:checked_at] = admin_status["checked_at"] || status[:checked_at]
    status[:instance_name] = admin_status["instance_name"] if admin_status["instance_name"].present?
    status
  rescue RemoteShareClient::Error => e
    status[:reachable] = false
    status[:error] = e.message
    status[:message] = t("share_management.remote_unreachable", default: "Remote share API couldn't be reached.")
    status
  end

  def permitted_share_management_updates
    params
      .permit(*Config::SHARE_MANAGEMENT_KEYS)
      .to_h
      .reject { |key, value| Config::SENSITIVE_KEYS.include?(key) && value.to_s.strip.empty? }
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

  def share_provider_selector
    @share_provider_selector ||= ShareProviderSelector.new(config: @config)
  end
end
