# frozen_string_literal: true

require "test_helper"
require "yaml"

class ShareApiDeploymentArtifactsTest < ActiveSupport::TestCase
  test ".env example documents the monitoring contract" do
    env_example = deployment_file(".env.example")

    assert_includes env_example, "LEWISMD_SHARE_INSTANCE_NAME="
    assert_includes env_example, "LEWISMD_SHARE_HEALTHCHECKS_PING_URL="
    assert_includes env_example, "LEWISMD_SHARE_ALERT_WEBHOOK_KIND="
    assert_includes env_example, "LEWISMD_SHARE_ALERT_WEBHOOK_URL="
    assert_includes env_example, "LEWISMD_SHARE_ALERT_WEBHOOK_SECRET="
    assert_includes env_example, "LEWISMD_SHARE_MONITOR_INTERVAL_MINUTES="
    assert_includes env_example, "LEWISMD_SHARE_MONITOR_DISK_THRESHOLD_PERCENT="
  end

  test "compose file keeps share-api internal and caddy public" do
    compose = YAML.safe_load(deployment_file("compose.yml"))
    services = compose.fetch("services")
    share_api = services.fetch("share-api")
    caddy = services.fetch("caddy")

    assert_nil share_api["ports"]
    assert_equal [ "9292" ], share_api["expose"]
    assert_equal({ "condition" => "service_healthy" }, caddy.dig("depends_on", "share-api"))
    assert_equal [ "${LEWISMD_SHARE_HTTP_PORT:-80}:80", "${LEWISMD_SHARE_HTTPS_PORT:-443}:443" ], caddy["ports"]
  end

  test "installer summary and prompts cover the operator workflow" do
    installer = deployment_file("install_share_api.sh")

    assert_includes installer, "Install the host-level monitoring timer?"
    assert_includes installer, "Enable Healthchecks.io heartbeat pings?"
    assert_includes installer, "Enable outbound webhook alerts?"
    assert_includes installer, "upgrade_share_api.sh"
    assert_includes installer, "backup_share_api.sh"
    assert_includes installer, "uninstall_share_api.sh"
    assert_includes installer, "Operator guide: $REPO_ROOT/docs/remote_share_api.md"
    assert_includes installer, 'chown -R "${SHARE_API_UID}:${SHARE_API_GID}" "$STORAGE_HOST_PATH"'
    assert_includes installer, "logs --no-color --tail=200 share-api"
  end

  test "upgrade script creates a backup by default and emits deployment alerts" do
    script = deployment_file("upgrade_share_api.sh")

    assert_includes script, 'prompt_yes_no "Create a pre-upgrade backup before restarting the stack?" "y"'
    assert_includes script, 'notify_event "deploy_started"'
    assert_includes script, 'notify_event "deploy_succeeded"'
    assert_includes script, 'notify_event "deploy_failed"'
    assert_includes script, 'bash "$SCRIPT_DIR/backup_share_api.sh"'
  end

  test "backup script writes a tar archive and checksum" do
    script = deployment_file("backup_share_api.sh")

    assert_includes script, 'archive_name="lewismd-share-backup-${timestamp}.tar.gz"'
    assert_includes script, "sha256sum"
    assert_includes script, 'copy_if_present "$STORAGE_HOST_PATH" "$temp_dir/host-data/storage"'
    assert_includes script, 'copy_if_present "$CADDY_DATA_PATH" "$temp_dir/host-data/caddy-data"'
  end

  test "uninstall script preserves persisted data by default" do
    script = deployment_file("uninstall_share_api.sh")

    assert_includes script, 'DELETE_RUNTIME="false"'
    assert_includes script, 'DELETE_STORAGE="false"'
    assert_includes script, 'DELETE_CADDY_STATE="false"'
    assert_includes script, 'prompt_yes_no "Create a final backup before uninstalling anything?" "y"'
  end

  test "operator guide covers install, upgrade, backup, uninstall, and restore" do
    guide = Rails.root.join("docs", "remote_share_api.md").read

    assert_includes guide, "bash deploy/share_api/install_share_api.sh"
    assert_includes guide, "bash deploy/share_api/upgrade_share_api.sh"
    assert_includes guide, "bash deploy/share_api/backup_share_api.sh"
    assert_includes guide, "bash deploy/share_api/uninstall_share_api.sh"
    assert_includes guide, "There is no dedicated restore script yet."
    assert_includes guide, "lewismd-share-monitor.timer"
  end

  test "readme links the optional remote share api workflow" do
    readme = Rails.root.join("README.md").read

    assert_includes readme, "Optional: Remote Share API On A VPS"
    assert_includes readme, "docs/remote_share_api.md"
    assert_includes readme, "bash deploy/share_api/install_share_api.sh"
  end

  private

  def deployment_file(name)
    Rails.root.join("deploy", "share_api", name).read
  end
end
