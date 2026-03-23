# frozen_string_literal: true

require "application_system_test_case"

class ExportMenuTest < ApplicationSystemTestCase
  def setup
    super
    setup_test_images_dir
  end

  def teardown
    teardown_test_images_dir
    super
  end

  test "export menu exports standalone HTML from the current preview payload" do
    create_test_note("export_menu.md", "# Export Menu\n\nBody")

    visit root_url
    find("[data-path='export_menu.md']").click

    install_download_capture
    open_export_menu

    within "[data-export-menu-target='menu']" do
      assert_text "Copy Note (Ctrl+C)"
      assert_text "Copy Markdown"
      assert_text "Export files"
      assert_text "Create shared link"
      assert_no_text "Export HTML"
    end

    click_button "Export files"
    click_button "Export HTML"
    download = wait_for_captured_download

    refute_nil download
    assert_equal "export_menu.html", download["download"]
    assert_includes download["type"], "text/html"
    assert_includes download["text"], "<!DOCTYPE html>"
    assert_includes download["text"], "<h1>Export Menu</h1>"
    assert_no_text "This action is planned for the next export/share phase."
  ensure
    restore_download_capture
  end

  test "export menu inlines local preview images into standalone HTML" do
    create_test_image("portable-export.png")
    create_test_note("export_local_image.md", <<~MD)
      # Local Image Export

      ![Portable image](/images/preview/portable-export.png)
    MD

    visit root_url
    find("[data-path='export_local_image.md']").click

    install_download_capture
    open_export_menu
    click_button "Export files"
    click_button "Export HTML"

    download = wait_for_captured_download

    refute_nil download
    assert_equal "export_local_image.html", download["download"]
    assert_includes download["text"], "<h1>Local Image Export</h1>"
    assert_includes download["text"], 'src="data:image/png;base64,'
    refute_includes download["text"], "/images/preview/portable-export.png"
  ensure
    restore_download_capture
  end

  test "export menu exports plain text from the current preview payload" do
    create_test_note("export_plain_text.md", "# Export Plain Text\n\nSecond line")

    visit root_url
    find("[data-path='export_plain_text.md']").click

    install_download_capture
    open_export_menu
    click_button "Export files"
    click_button "Export TXT"

    download = wait_for_captured_download

    refute_nil download
    assert_equal "export_plain_text.txt", download["download"]
    assert_includes download["type"], "text/plain"
    assert_includes download["text"], "Export Plain Text"
    assert_includes download["text"], "Second line"
  ensure
    restore_download_capture
  end

  test "export menu builds a populated standalone document for PDF output and inlines local images" do
    create_test_image("export-pdf-image.png")
    create_test_note("export_pdf.md", <<~MD)
      # Export PDF

      Body with a [link](https://example.com/docs).

      | Column | Value |
      | --- | --- |
      | One | Two |

      ![Example image](/images/preview/export-pdf-image.png)
    MD

    visit root_url
    find("[data-path='export_pdf.md']").click

    install_pdf_capture
    open_export_menu
    within "[data-export-menu-target='menu']" do
      click_button "Export files"
      click_button "Export PDF"
    end

    captured_pdf = wait_for_captured_pdf

    refute_nil captured_pdf
    assert_includes captured_pdf["type"], "text/html"
    assert_includes captured_pdf["text"], "<!DOCTYPE html>"
    assert_includes captured_pdf["text"], "<h1>Export PDF</h1>"
    assert_includes captured_pdf["text"], "Body with a"
    assert_includes captured_pdf["text"], 'href="https://example.com/docs"'
    assert_includes captured_pdf["text"], "<table>"
    assert_includes captured_pdf["text"], 'src="data:image/png;base64,'
    refute_includes captured_pdf["text"], "/images/preview/export-pdf-image.png"
    assert_includes captured_pdf["text"], "background: #ffffff !important;"
    assert_includes captured_pdf["text"], "color: #111827 !important;"
  ensure
    restore_pdf_capture
  end

  test "export menu closes when clicking outside" do
    create_test_note("export_menu_close.md", "# Export Menu\n\nBody")

    visit root_url
    find("[data-path='export_menu_close.md']").click

    open_export_menu

    page.execute_script("document.body.click()")

    assert_selector "[data-export-menu-target='menu'].hidden", visible: :all
  end

  test "export menu manages snapshot sharing with a stable link" do
    create_test_note("share_from_menu.md", "# Shared Snapshot\n\nVersion one")

    visit root_url
    find("[data-path='share_from_menu.md']").click

    open_export_menu
    click_button "Create shared link"

    first_share = wait_for_share("share_from_menu.md")
    first_share_url = share_snapshot_url(token: first_share[:token])

    assert_match(%r{/s/[a-f0-9]{32}$}, first_share_url)

    open_export_menu
    within "[data-export-menu-target='menu']" do
      assert_text "Copy shared link"
      assert_text "Refresh shared snapshot"
      assert_text "Disable shared link"
      assert_no_text "Create shared link"
    end

    replace_editor_content("# Shared Snapshot\n\nVersion two")

    click_button "Refresh shared snapshot"

    second_share = wait_for_share("share_from_menu.md")
    assert_equal first_share[:token], second_share[:token]

    visit first_share_url
    assert_text "Shared note"
    within_frame(find("iframe[data-share-view-target='frame']", wait: 2)) do
      assert_text "Version two"
    end

    visit root_url
    find("[data-path='share_from_menu.md']").click

    open_export_menu
    click_button "Disable shared link"

    open_export_menu
    within "[data-export-menu-target='menu']" do
      assert_text "Create shared link"
      assert_no_text "Copy shared link"
    end
  end

  private

  def open_export_menu
    find("button[title='Open share, export, and copy actions']").click
    assert_selector "[data-export-menu-target='menu']:not(.hidden)", wait: 2
  end

  def install_download_capture
    page.execute_script(<<~JS)
      window.__exportCapture = { blob: null, download: null, href: null };
      window.__originalCreateObjectURL = window.URL.createObjectURL;
      window.__originalRevokeObjectURL = window.URL.revokeObjectURL;
      window.__originalAnchorClick = HTMLAnchorElement.prototype.click;

      window.URL.createObjectURL = function(blob) {
        window.__exportCapture.blob = blob;
        return "blob:frankmd-export";
      };

      window.URL.revokeObjectURL = function(url) {
        window.__exportCapture.revokedUrl = url;
      };

      HTMLAnchorElement.prototype.click = function() {
        window.__exportCapture.download = this.download;
        window.__exportCapture.href = this.href;
      };
    JS
  end

  def wait_for_captured_download
    page.evaluate_async_script(<<~JS)
      const done = arguments[0];
      const startedAt = Date.now();

      (function poll() {
        const capture = window.__exportCapture;
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

  def install_pdf_capture
    page.execute_script(<<~JS)
      window.__pdfCapture = { blob: null };
      window.__originalCreateObjectURL = window.URL.createObjectURL;

      window.URL.createObjectURL = function(blob) {
        if (!window.__pdfCapture.blob && blob.type && blob.type.indexOf("text/html") !== -1) {
          window.__pdfCapture.blob = blob;
        }
        return "blob:frankmd-pdf";
      };
    JS
  end

  def wait_for_captured_pdf
    page.evaluate_async_script(<<~JS)
      const done = arguments[0];
      const startedAt = Date.now();

      (function poll() {
        const capture = window.__pdfCapture;
        if (capture && capture.blob) {
          capture.blob.text().then((text) => {
            done({
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

  def replace_editor_content(markdown)
    page.execute_script(<<~JS, markdown)
      const nextContent = arguments[0];
      const appElement = document.querySelector('[data-controller~="app"]');
      const codemirrorElement = document.querySelector('[data-controller~="codemirror"]');
      const appController = window.Stimulus.getControllerForElementAndIdentifier(appElement, 'app');
      const codemirrorController = window.Stimulus.getControllerForElementAndIdentifier(codemirrorElement, 'codemirror');

      codemirrorController.setValue(nextContent);
      appController.onEditorChange({ detail: { docChanged: true } });
    JS
  end

  def wait_for_share(path, timeout: 3)
    service = ShareService.new(base_path: @test_notes_dir)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      share = service.active_share_for(path)
      return share if share

      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.05
    end

    flunk("Timed out waiting for share metadata for #{path}")
  end

  def restore_pdf_capture
    page.execute_script(<<~JS)
      if (window.__originalCreateObjectURL) {
        window.URL.createObjectURL = window.__originalCreateObjectURL;
      }
    JS
  rescue StandardError
    nil
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

  def setup_test_images_dir
    @test_images_dir = Rails.root.join("tmp", "test_export_images_#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@test_images_dir)

    @original_images_path = ENV["IMAGES_PATH"]
    ENV["IMAGES_PATH"] = @test_images_dir.to_s
  end

  def teardown_test_images_dir
    FileUtils.rm_rf(@test_images_dir) if @test_images_dir&.exist?
    ENV["IMAGES_PATH"] = @original_images_path
  end

  def create_test_image(name)
    path = @test_images_dir.join(name)
    FileUtils.mkdir_p(path.dirname)
    png_data = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
      0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
      0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xE7, 0x00, 0x00,
      0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ].pack("C*")
    File.binwrite(path, png_data)
    path
  end
end
