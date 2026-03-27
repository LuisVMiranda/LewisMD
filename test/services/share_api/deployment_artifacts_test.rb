# frozen_string_literal: true

require "test_helper"
require "json"
require "yaml"

class ShareApiDeploymentArtifactsTest < ActiveSupport::TestCase
  test ".env example documents reverse proxy, monitoring, and expiry settings" do
    env_example = deployment_file(".env.example")

    assert_includes env_example, "LEWISMD_SHARE_EDGE_MODE="
    assert_includes env_example, "LEWISMD_SHARE_PUBLIC_SCHEME="
    assert_includes env_example, "LEWISMD_SHARE_PUBLIC_HOST="
    assert_includes env_example, "LEWISMD_SHARE_INTERNAL_PORT="
    assert_includes env_example, "LEWISMD_SHARE_INSTANCE_NAME="
    assert_includes env_example, "LEWISMD_SHARE_HEALTHCHECKS_PING_URL="
    assert_includes env_example, "LEWISMD_SHARE_ALERT_WEBHOOK_KIND="
    assert_includes env_example, "LEWISMD_SHARE_ALERT_WEBHOOK_URL="
    assert_includes env_example, "LEWISMD_SHARE_ALERT_WEBHOOK_SECRET="
    assert_includes env_example, "LEWISMD_SHARE_MONITOR_INTERVAL_MINUTES="
    assert_includes env_example, "LEWISMD_SHARE_MONITOR_DISK_THRESHOLD_PERCENT="
    assert_includes env_example, "LEWISMD_SHARE_MONITOR_SWEEPER_STALE_MINUTES="
    assert_includes env_example, "LEWISMD_SHARE_MONITOR_STORAGE_GROWTH_MB="
    assert_includes env_example, "LEWISMD_SHARE_MAX_EXPIRATION_DAYS="
    assert_includes env_example, "LEWISMD_SHARE_EXPIRY_SWEEP_MINUTES="
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

  test "installer summary and prompts cover managed caddy and external reverse proxy workflows" do
    installer = deployment_file("install_share_api.sh")

    assert_includes installer, 'EDGE_MODE="managed_caddy"'
    assert_includes installer, "Existing reverse proxy (for example Nginx)"
    assert_includes installer, "Localhost port the share-api should bind to"
    assert_includes installer, "write_runtime_nginx_file"
    assert_includes installer, "write_runtime_sweeper_units"
    assert_includes installer, "install_sweeper_timer"
    assert_includes installer, "share_remote_expiration_days = $LOCAL_SHARE_EXPIRATION_DAYS"
    assert_includes installer, "Install the host-level monitoring timer?"
    assert_includes installer, "Minutes before the expiry sweeper is considered stale"
    assert_includes installer, "Alert if share storage grows by at least this many MB between monitor runs"
    assert_includes installer, "Enable Healthchecks.io heartbeat pings?"
    assert_includes installer, "Enable outbound webhook alerts?"
    assert_includes installer, "upgrade_share_api.sh"
    assert_includes installer, "backup_share_api.sh"
    assert_includes installer, "uninstall_share_api.sh"
    assert_includes installer, "bin/verify_storage_write.rb"
    assert_includes installer, "Operator guide: $REPO_ROOT/docs/remote_share_api.md"
    assert_includes installer, 'chown -R "${SHARE_API_UID}:${SHARE_API_GID}" "$STORAGE_HOST_PATH"'
    assert_includes installer, "logs --no-color --tail=200 share-api"
  end

  test "upgrade script creates a backup by default and handles managed caddy separately" do
    script = deployment_file("upgrade_share_api.sh")

    assert_includes script, 'prompt_yes_no "Create a pre-upgrade backup before restarting the stack?" "y"'
    assert_includes script, 'notify_event "deploy_started"'
    assert_includes script, 'notify_event "deploy_succeeded"'
    assert_includes script, 'notify_event "deploy_failed"'
    assert_includes script, 'bash "$SCRIPT_DIR/backup_share_api.sh"'
    assert_includes script, 'if [[ "$EDGE_MODE" == "managed_caddy" ]]; then'
    assert_includes script, 'chown -R "${SHARE_API_UID}:${SHARE_API_GID}" "$STORAGE_HOST_PATH"'
    assert_includes script, "bundle exec ruby bin/verify_storage_write.rb"
  end

  test "backup script writes a tar archive and checksum with optional edge assets" do
    script = deployment_file("backup_share_api.sh")

    assert_includes script, 'TEMP_DIR=""'
    assert_includes script, "cleanup_temp_dir()"
    assert_includes script, "trap cleanup_temp_dir EXIT"
    assert_includes script, 'archive_name="lewismd-share-backup-${timestamp}.tar.gz"'
    assert_includes script, "sha256sum"
    assert_includes script, 'copy_if_present "$STORAGE_HOST_PATH" "$TEMP_DIR/host-data/storage"'
    assert_includes script, 'copy_if_present "$CADDY_DATA_PATH" "$TEMP_DIR/host-data/caddy-data"'
    assert_includes script, 'copy_if_present "$RUNTIME_DIR/nginx-lewismd-share.conf"'
    assert_includes script, "edge_mode=$EDGE_MODE"
  end

  test "uninstall script preserves persisted data by default and removes sweeper units" do
    script = deployment_file("uninstall_share_api.sh")

    assert_includes script, 'DELETE_RUNTIME="false"'
    assert_includes script, 'DELETE_STORAGE="false"'
    assert_includes script, 'DELETE_CADDY_STATE="false"'
    assert_includes script, 'prompt_yes_no "Create a final backup before uninstalling anything?" "y"'
    assert_includes script, "lewismd-share-sweeper.timer"
  end

  test "operator guide covers install, reverse proxy mode, expiry sweep, upgrade, backup, uninstall, and restore" do
    guide = Rails.root.join("docs", "remote_share_api.md").read

    assert_includes guide, "bash deploy/share_api/install_share_api.sh"
    assert_includes guide, "bash deploy/share_api/upgrade_share_api.sh"
    assert_includes guide, "bash deploy/share_api/backup_share_api.sh"
    assert_includes guide, "bash deploy/share_api/uninstall_share_api.sh"
    assert_includes guide, "There is no dedicated restore script yet."
    assert_includes guide, "lewismd-share-monitor.timer"
    assert_includes guide, "external reverse proxy"
    assert_includes guide, "nginx-lewismd-share.conf"
    assert_includes guide, "lewismd-share-sweeper.timer"
    assert_includes guide, "share_remote_expiration_days"
    assert_includes guide, "different notes get different public links"
    assert_includes guide, "same note keeps one active public link"
    assert_includes guide, "legacy fragment-only shares continue to work"
    assert_includes guide, "refreshing an existing legacy share republishes it as the newer snapshot"
    assert_includes guide, "cleanup_failed"
    assert_includes guide, "storage-growth anomalies"
    assert_includes guide, "Invalid share request"
    assert_includes guide, "bin/verify_storage_write.rb"
    assert_includes guide, "sudo chown -R 10001:10001 /var/lib/lewismd-share/storage"
    assert_includes guide, "undefined method `presence'"
  end

  test "monitor script covers cleanup health and storage growth alerts" do
    script = deployment_file("monitor_share_api.sh")

    assert_includes script, "LEWISMD_SHARE_MONITOR_SWEEPER_STALE_MINUTES"
    assert_includes script, "LEWISMD_SHARE_MONITOR_STORAGE_GROWTH_MB"
    assert_includes script, "cleanup_failed"
    assert_includes script, "cleanup_stale"
    assert_includes script, "cleanup_recovered"
    assert_includes script, "storage_growth_high"
    assert_includes script, "sweeper-state.json"
  end

  test "standalone share api files avoid active support blank helpers" do
    standalone_source = Rails.root.join("services", "share_api", "app.rb").read

    refute_includes standalone_source, ".presence"
    refute_includes standalone_source, ".blank?"
    refute_includes standalone_source, ".present?"
  end

  test "standalone reader asset copies stay in sync with the main share ui sources" do
    assert_equal(
      Rails.root.join("app", "assets", "tailwind", "components", "share_view.css").read,
      Rails.root.join("services", "share_api", "public", "reader", "share_view.css").read
    )
    assert_equal(
      Rails.root.join("app", "assets", "tailwind", "components", "outline.css").read,
      Rails.root.join("services", "share_api", "public", "reader", "outline.css").read
    )

    %w[
      theme_helpers.js
      locale_helpers.js
      translation_helpers.js
      export_menu_helpers.js
      outline_helpers.js
    ].each do |filename|
      assert_equal(
        Rails.root.join("app", "javascript", "lib", "share_reader", filename).read,
        Rails.root.join("services", "share_api", "public", "reader", filename).read,
        "#{filename} drifted from the standalone reader copy"
      )
    end

    Dir.glob(Rails.root.join("app", "assets", "tailwind", "themes", "*.css")).each do |source_theme_path|
      filename = File.basename(source_theme_path)
      assert_equal(
        Pathname.new(source_theme_path).read,
        Rails.root.join("services", "share_api", "public", "reader", "themes", filename).read,
        "#{filename} drifted from the standalone reader theme copy"
      )
    end

    %w[
      icon.svg
      favicon-32x32.png
      favicon-16x16.png
      apple-touch-icon.png
    ].each do |filename|
      assert_equal(
        Rails.root.join("public", filename).binread,
        Rails.root.join("services", "share_api", "public", "reader", filename).binread,
        "#{filename} drifted from the standalone reader icon copy"
      )
    end
  end

  test "standalone reader translation bundle stays in sync with the main locale keys" do
    translation_bundle = JSON.parse(
      Rails.root.join("services", "share_api", "public", "reader", "remote_reader_translations.json").read
    )

    translation_keys = {
      "header" => %w[change_theme change_language outline share open_share_menu],
      "sidebar" => %w[outline no_headings_yet],
      "share_view" => %w[
        label
        display
        display_controls
        show_controls
        hide_controls
        show_toolbar
        hide_toolbar
        collapse_outline
        expand_outline
        zoom
        zoom_in
        zoom_out
        width
        width_narrower
        width_wider
        font_family
        font_default
        font_sans
        font_serif
        font_mono
        iframe_title
      ],
      "export_menu" => %w[
        copy_note
        copy_markdown
        export_files
        export_html
        export_txt
        export_pdf
        create_share_link
        copy_share_link
        refresh_share_link
        disable_share_link
      ],
      "status" => %w[copied_to_clipboard copy_failed export_failed print_failed private_note_link_unavailable]
    }

    %w[en pt-BR pt-PT es he ja ko].each do |locale|
      locale_source = YAML.load_file(Rails.root.join("config", "locales", "#{locale}.yml")).fetch(locale)
      expected_locale_payload = translation_keys.each_with_object({}) do |(namespace, keys), memo|
        source_namespace = locale_source.fetch(namespace)
        memo[namespace] = keys.each_with_object({}) do |key, namespace_memo|
          namespace_memo[key] = source_namespace.fetch(key)
        end
      end

      assert_equal(
        expected_locale_payload,
        translation_bundle.fetch(locale),
        "#{locale} drifted from the standalone remote reader translation bundle"
      )
    end
  end

  test "readme links the optional remote share api workflow" do
    readme = Rails.root.join("README.md").read

    assert_includes readme, "Optional: Remote Share API On A VPS"
    assert_includes readme, "docs/remote_share_api.md"
    assert_includes readme, "bash deploy/share_api/install_share_api.sh"
    assert_includes readme, "different notes get different remote public links"
    assert_includes readme, "same note keeps one active remote link"
    assert_includes readme, "share_remote_expiration_days"
  end

  private

  def deployment_file(name)
    Rails.root.join("deploy", "share_api", name).read
  end
end
