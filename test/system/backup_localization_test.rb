# frozen_string_literal: true

require "application_system_test_case"

class BackupLocalizationTest < ApplicationSystemTestCase
  test "backup menu label and status message follow the active locale" do
    @test_notes_dir.join(".fed").write("locale = es\n")
    create_test_note("respaldo.md", "# Respaldo")

    visit root_url
    install_backup_capture

    find("[data-path='respaldo.md'][data-type='file']", match: :first).right_click

    within "[data-app-target='contextMenu']" do
      assert_text "Respaldar nota"
      click_button "Respaldar nota"
    end

    backup = wait_for_captured_backup

    refute_nil backup
    assert_includes backup["fetchUrl"], "/backup/note/respaldo.md"
    assert_equal "respaldo-backup.zip", backup["download"]
    assert_text "Descarga de respaldo iniciada"
  ensure
    restore_backup_capture
  end

  private

  def install_backup_capture
    page.execute_script(<<~JS)
      window.__backupCapture = { fetchUrl: null, href: null, download: null };
      window.__originalFetch = window.fetch.bind(window);
      window.__originalBackupAnchorClick = HTMLAnchorElement.prototype.click;
      window.__originalCreateObjectURL = URL.createObjectURL;

      window.fetch = function(input, init) {
        const url = typeof input === "string" ? input : input.url;
        if (url.includes("/backup/")) {
          window.__backupCapture.fetchUrl = url;
        }

        return window.__originalFetch(input, init);
      };

      URL.createObjectURL = function(blob) {
        window.__backupCapture.blobType = blob.type;
        return "blob:backup-test";
      };

      HTMLAnchorElement.prototype.click = function() {
        window.__backupCapture.href = this.href;
        window.__backupCapture.download = this.download;
      };
    JS
  end

  def wait_for_captured_backup
    page.evaluate_async_script(<<~JS)
      const done = arguments[0];
      const startedAt = Date.now();

      (function poll() {
        const capture = window.__backupCapture;
        if (capture && capture.fetchUrl && capture.download) {
          done({
            fetchUrl: capture.fetchUrl,
            href: capture.href,
            download: capture.download
          });
          return;
        }

        if (Date.now() - startedAt > 3000) {
          done(null);
          return;
        }

        setTimeout(poll, 25);
      })();
    JS
  end

  def restore_backup_capture
    page.execute_script(<<~JS)
      if (window.__originalFetch) {
        window.fetch = window.__originalFetch;
      }

      if (window.__originalCreateObjectURL) {
        URL.createObjectURL = window.__originalCreateObjectURL;
      }

      if (window.__originalBackupAnchorClick) {
        HTMLAnchorElement.prototype.click = window.__originalBackupAnchorClick;
      }
    JS
  rescue StandardError
    nil
  end
end
