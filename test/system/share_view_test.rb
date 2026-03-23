# frozen_string_literal: true

require "application_system_test_case"

class ShareViewTest < ApplicationSystemTestCase
  test "shared snapshot page renders in a read-only shell with controls" do
    share = create_shared_snapshot("Shared Snapshot")

    visit share_snapshot_url(token: share[:token])

    assert_text "Shared note"
    assert_text "Shared Snapshot"
    assert_selector "iframe[data-share-view-target='frame']", wait: 2
    assert_selector "[data-share-view-target='zoomValue']", text: "100%"
    assert_selector "[data-share-view-target='widthValue']", text: "72ch"

    within_share_frame do
      assert_text "Shared Snapshot"
      assert_text "Body"
    end
  end

  test "share controls update zoom width and font family inside the embedded snapshot" do
    share = create_shared_snapshot("Formatting Snapshot")

    visit share_snapshot_url(token: share[:token])
    assert_selector "iframe[data-share-view-target='frame']", wait: 2
    within_share_frame { assert_text "Formatting Snapshot" }

    click_button_with_title("Zoom in")
    click_button_with_title("Make text column wider")
    find("[data-share-view-target='fontSelect']", visible: :all).select("Serif")

    assert_selector "[data-share-view-target='zoomValue']", text: "110%"
    assert_selector "[data-share-view-target='widthValue']", text: "76ch"

    metrics = share_snapshot_metrics

    assert_equal "17.6px", metrics["fontSize"]
    assert_equal "76ch", metrics["maxWidth"]
    assert_includes metrics["fontFamily"], "Georgia"
  end

  test "shared reader exposes export actions without share management actions" do
    share = create_shared_snapshot("Export Snapshot")

    visit share_snapshot_url(token: share[:token])
    assert_selector "iframe[data-share-view-target='frame']", wait: 2

    install_download_capture
    open_share_export_menu

    within "[data-export-menu-target='menu']" do
      assert_text "Copy Note (Ctrl+C)"
      assert_text "Export files"
      assert_no_text "Copy Markdown"
      assert_no_text "Export HTML"
      assert_no_text "Create shared link"
      assert_no_text "Copy shared link"
      click_button "Export files"
      click_button "Export HTML"
    end

    download = wait_for_captured_download

    refute_nil download
    assert_equal "Export-Snapshot.html", download["download"]
    assert_includes download["text"], "<h1>Export Snapshot</h1>"
    assert_includes download["text"], "<article class=\"export-article\""
  ensure
    restore_download_capture
  end

  test "share page locale picker reloads the UI in the selected language" do
    share = create_shared_snapshot("Localized Snapshot")

    visit share_snapshot_url(token: share[:token])
    assert_text "Shared note"

    find("button[title='Change Language']").click
    within "[data-locale-target='menu']" do
      click_button "Español"
    end

    assert_text "Nota compartida", wait: 2
    assert_includes page.current_url, "locale=es"
  end

  test "share page theme picker updates the shell and embedded snapshot theme" do
    share = create_shared_snapshot("Themed Snapshot")

    visit share_snapshot_url(token: share[:token])
    assert_selector "iframe[data-share-view-target='frame']", wait: 2

    find("button[title='Change Theme']").click
    within "[data-theme-target='menu']" do
      click_button "Dark"
    end

    theme_data = page.evaluate_script(<<~JS)
      (function() {
        const frame = document.querySelector('[data-share-view-target="frame"]');
        return {
          pageTheme: document.documentElement.getAttribute('data-theme'),
          frameTheme: frame.contentDocument.documentElement.getAttribute('data-theme')
        };
      })()
    JS

    assert_equal "dark", theme_data["pageTheme"]
    assert_equal "dark", theme_data["frameTheme"]
  end

  private

  def create_shared_snapshot(title)
    create_test_note("#{title.parameterize}.md", "# #{title}\n\nBody")

    ShareService.new(base_path: @test_notes_dir).create_or_find(
      path: "#{title.parameterize}.md",
      title: title,
      snapshot_html: standalone_snapshot_html(title)
    )
  end

  def standalone_snapshot_html(title)
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root {
            --font-sans: "Inter", ui-sans-serif, system-ui, sans-serif;
            --font-mono: "JetBrains Mono", ui-monospace, monospace;
            --export-font-size: 16px;
            --theme-bg-primary: #ffffff;
            --theme-bg-secondary: #f8fafc;
            --theme-text-primary: #111827;
            --theme-text-secondary: #1f2937;
            --theme-border: #d1d5db;
          }

          body {
            margin: 0;
            background: var(--theme-bg-primary);
          }

          .export-shell {
            min-height: 100vh;
            padding: 3rem 1.5rem;
            background: linear-gradient(180deg, var(--theme-bg-secondary) 0%, var(--theme-bg-primary) 18rem);
          }

          .export-article {
            max-width: 72ch;
            margin: 0 auto;
            font-size: 16px;
            line-height: 1.75;
            color: var(--theme-text-secondary);
            font-family: var(--font-sans);
          }

          .export-article h1 {
            color: var(--theme-text-primary);
            margin-top: 0;
          }
        </style>
      </head>
      <body>
        <main class="export-shell">
          <article class="export-article">
            <h1>#{title}</h1>
            <p>Body</p>
          </article>
        </main>
      </body>
      </html>
    HTML
  end

  def within_share_frame(&block)
    within_frame(find("iframe[data-share-view-target='frame']", wait: 2), &block)
  end

  def click_button_with_title(title)
    find("button[title='#{title}']").click
  end

  def open_share_export_menu
    find("button[title='Open export actions']").click
    assert_selector "[data-export-menu-target='menu']:not(.hidden)", wait: 2
  end

  def install_download_capture
    page.execute_script(<<~JS)
      window.__shareExportCapture = { blob: null, download: null, href: null };
      window.__originalCreateObjectURL = window.URL.createObjectURL;
      window.__originalRevokeObjectURL = window.URL.revokeObjectURL;
      window.__originalAnchorClick = HTMLAnchorElement.prototype.click;

      window.URL.createObjectURL = function(blob) {
        window.__shareExportCapture.blob = blob;
        return "blob:share-export";
      };

      window.URL.revokeObjectURL = function(url) {
        window.__shareExportCapture.revokedUrl = url;
      };

      HTMLAnchorElement.prototype.click = function() {
        window.__shareExportCapture.download = this.download;
        window.__shareExportCapture.href = this.href;
      };
    JS
  end

  def wait_for_captured_download
    page.evaluate_async_script(<<~JS)
      const done = arguments[0];
      const startedAt = Date.now();

      (function poll() {
        const capture = window.__shareExportCapture;
        if (capture && capture.blob) {
          capture.blob.text().then((text) => {
            done({
              download: capture.download,
              href: capture.href,
              type: capture.blob.type,
              text: text
            });
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

  def restore_download_capture
    page.execute_script(<<~JS)
      if (window.__originalCreateObjectURL) {
        window.URL.createObjectURL = window.__originalCreateObjectURL;
      }
      if (window.__originalRevokeObjectURL) {
        window.URL.revokeObjectURL = window.__originalRevokeObjectURL;
      }
      if (window.__originalAnchorClick) {
        HTMLAnchorElement.prototype.click = window.__originalAnchorClick;
      }
    JS
  rescue StandardError
    nil
  end

  def share_snapshot_metrics
    page.evaluate_script(<<~JS)
      (function() {
        const frame = document.querySelector('[data-share-view-target="frame"]');
        const article = frame.contentDocument.querySelector('.export-article');
        return {
          fontSize: article.style.fontSize,
          maxWidth: article.style.maxWidth,
          fontFamily: article.style.fontFamily
        };
      })()
    JS
  end
end
