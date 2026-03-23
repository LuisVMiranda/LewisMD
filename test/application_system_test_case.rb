# frozen_string_literal: true

require "test_helper"
require "capybara/rails"
require "capybara/minitest"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Disable parallelization for system tests to avoid race conditions
  parallelize(workers: 1)

  Capybara.register_driver :frankmd_headless_chrome do |app|
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument("--headless=new")
    options.add_argument("--disable-gpu")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--window-size=1400,900")

    chrome_binary = ENV["CHROME_BIN"]
    chrome_binary ||= "/usr/bin/chromium" if File.exist?("/usr/bin/chromium")
    options.binary = chrome_binary if chrome_binary.present?

    Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
  end

  driven_by :frankmd_headless_chrome

  # Increase default wait time for slower CI environments
  Capybara.default_max_wait_time = 5

  def setup
    setup_test_notes_dir
  end

  def teardown
    teardown_test_notes_dir
  end

  private

  # Helper to get the CodeMirror editor content via Stimulus controller
  def editor_content
    page.evaluate_script(<<~JS)
      (function() {
        var el = document.querySelector('[data-controller~="codemirror"]');
        if (!el) return null;
        var ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'codemirror');
        return ctrl ? ctrl.getValue() : null;
      })()
    JS
  end

  def click_app_target(target)
    page.execute_script("document.querySelector('[data-app-target=\"#{target}\"]').click()")
  end

  def typewriter_mode_enabled?
    page.evaluate_script("document.body.classList.contains('typewriter-mode')")
  end

  def reading_mode_enabled?
    page.evaluate_script("document.body.classList.contains('reading-mode-active')")
  end

  def preview_visible?
    page.evaluate_script(<<~JS)
      (function() {
        var panel = document.querySelector('[data-app-target="previewPanel"]');
        return !!panel && !panel.classList.contains('hidden');
      })()
    JS
  end

  def preview_width_value
    page.evaluate_script(<<~JS)
      (function() {
        var panel = document.querySelector('[data-app-target="previewPanel"]');
        if (!panel) return null;
        var width = panel.style.getPropertyValue('--preview-width');
        return width ? parseInt(width, 10) : null;
      })()
    JS
  end

  def set_preview_width(percentage)
    page.execute_script(<<~JS)
      (function() {
        var pane = document.querySelector('[data-controller~="split-pane"]');
        var ctrl = window.Stimulus.getControllerForElementAndIdentifier(pane, 'split-pane');
        ctrl.applyWidth(#{percentage});
        ctrl.dispatch('width-changed', { detail: { width: #{percentage} } });
      })()
    JS
  end

  def typewriter_toggle_button
    find("[data-typewriter-mode-btn]", visible: :all)
  end

  def assert_eventually(timeout: Capybara.default_max_wait_time, interval: 0.05, message: nil)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      return assert(true) if yield

      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep interval
    end

    flunk(message || "Condition was not met within #{timeout} seconds")
  end
end
