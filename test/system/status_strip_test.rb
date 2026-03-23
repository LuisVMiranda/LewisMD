# frozen_string_literal: true

require "application_system_test_case"

class StatusStripTest < ApplicationSystemTestCase
  test "status strip is markdown-only and tracks mode transitions" do
    create_test_note("status_strip.md", "# Title\n\nAlpha\nBeta")

    visit root_url

    assert_selector "[data-status-strip-target='strip'].hidden", visible: :all

    find("[data-path='status_strip.md']").click

    assert_no_selector "[data-status-strip-target='strip'].hidden", wait: 2
    assert_selector "[data-status-strip-target='modeChip']", text: "Mode: Raw"
    assert_selector "[data-status-strip-target='saveChip']", text: "Saved"
    assert_no_selector "[data-status-strip-target='recoveryChip']", visible: true
    assert_selector "[data-status-strip-target='recoveryChip'].hidden", visible: :all
    assert_selector "[data-status-strip-target='lineMetric']", text: "Ln 1/4"

    click_app_target("previewToggle")
    assert_selector "[data-status-strip-target='modeChip']", text: "Mode: Preview"
    assert_selector "[data-status-strip-target='zoomMetric']", text: "Zoom 100%"

    click_app_target("readingModeToggle")
    assert_selector "[data-status-strip-target='modeChip']", text: "Mode: Reading"
    assert_selector "[data-status-strip-target='zoomMetric']", text: "Zoom 100%"

    page.execute_script("document.querySelector('[data-typewriter-mode-btn]').click()")
    assert_selector "[data-status-strip-target='modeChip']", text: "Mode: Typewriter"
    assert_selector "[data-status-strip-target='zoomMetric'].hidden", visible: :all

    find("[data-path='.fed']").click
    assert_selector "[data-status-strip-target='strip'].hidden", visible: :all
  end

  test "status strip reflects unsaved edits, live line totals, and selection length" do
    create_test_note("status_strip_metrics.md", "# Title\n\nAlpha")

    visit root_url
    find("[data-path='status_strip_metrics.md']").click

    assert_selector "[data-status-strip-target='saveChip']", text: "Saved"
    assert_selector "[data-status-strip-target='lineMetric']", text: "Ln 1/3"
    assert_selector "[data-status-strip-target='selectionMetric'].hidden", visible: :all
    assert_no_selector "[data-status-strip-target='recoveryChip']", visible: true

    page.execute_script(<<~JS)
      (function() {
        var el = document.querySelector('[data-controller~="codemirror"]');
        var ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'codemirror');
        ctrl.insertAt(ctrl.getValue().length, "\\nBeta\\nGamma");
      })()
    JS

    assert_selector "[data-status-strip-target='saveChip']", text: "Unsaved", wait: 2
    assert_text(/Ln \d+\/5/, wait: 2)

    page.execute_script(<<~JS)
      (function() {
        var el = document.querySelector('[data-controller~="codemirror"]');
        var ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'codemirror');
        ctrl.setSelection(0, 5);
      })()
    JS

    assert_selector "[data-status-strip-target='selectionMetric']", text: "Sel 5", wait: 2
  end
end
