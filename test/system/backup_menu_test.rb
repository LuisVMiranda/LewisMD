# frozen_string_literal: true

require "application_system_test_case"

class BackupMenuTest < ApplicationSystemTestCase
  test "right-clicking a note offers back up note and targets the note backup endpoint" do
    create_test_note("backup note.md", "# Backup Note")

    visit root_url
    install_backup_capture

    find("[data-path='backup note.md'][data-type='file']", match: :first).right_click

    within "[data-app-target='contextMenu']" do
      assert_text "Back up note"
      click_button "Back up note"
    end

    backup = wait_for_captured_backup

    refute_nil backup
    assert_includes backup["fetchUrl"], "/backup/note/backup%20note.md"
    assert_equal "backup note-backup.zip", backup["download"]
    assert_text "Backup download started"
  ensure
    restore_backup_capture
  end

  test "right-clicking a folder offers back up folder and targets the folder backup endpoint" do
    create_test_folder("archive folder")

    visit root_url
    install_backup_capture

    find("[data-path='archive folder'][data-type='folder']", match: :first).right_click

    within "[data-app-target='contextMenu']" do
      assert_text "Back up folder"
      click_button "Back up folder"
    end

    backup = wait_for_captured_backup

    refute_nil backup
    assert_includes backup["fetchUrl"], "/backup/folder/archive%20folder"
    assert_equal "archive folder-backup.zip", backup["download"]
  ensure
    restore_backup_capture
  end

  test "backup failures surface a visible error message" do
    create_test_note("broken backup.md", "# Broken Backup")

    visit root_url
    install_backup_capture(fail_with: "Note not found")

    find("[data-path='broken backup.md'][data-type='file']", match: :first).right_click

    within "[data-app-target='contextMenu']" do
      click_button "Back up note"
    end

    assert_text "Note not found"
  ensure
    restore_backup_capture
  end

  private

  def install_backup_capture(fail_with: nil)
    script = <<~JS
      window.__backupCapture = { fetchUrl: null, href: null, download: null };
      window.__originalFetch = window.fetch.bind(window);
      window.__originalBackupAnchorClick = HTMLAnchorElement.prototype.click;
      window.__originalCreateObjectURL = URL.createObjectURL;

      window.fetch = function(input, init) {
        const url = typeof input === "string" ? input : input.url;
        if (url.includes("/backup/")) {
          window.__backupCapture.fetchUrl = url;
        }

        const failingMessage = #{fail_with.to_json};
        if (failingMessage && url.includes("/backup/")) {
          return Promise.resolve(new Response(JSON.stringify({ error: failingMessage }), {
            status: 404,
            headers: { "Content-Type": "application/json" }
          }));
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

    page.execute_script(script)
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
