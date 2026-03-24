# frozen_string_literal: true

require "application_system_test_case"

class HelpLayoutTest < ApplicationSystemTestCase
  test "help dialog stays closed until opened and closes from its button" do
    create_test_note("close.md", "# Close")

    visit root_url

    assert_no_selector "[data-help-target='helpDialog'][open]"

    page.execute_script(<<~JS)
      (function() {
        const button = document.querySelector("button[title='Markdown Help (F1)']");
        if (button) button.click();
      })()
    JS

    assert_selector "[data-help-target='helpDialog'][open]", wait: 3

    page.execute_script(<<~JS)
      (function() {
        const closeButton = document.querySelector("[data-help-target='helpDialog'] button[data-action*='closeHelp']");
        if (closeButton) closeButton.click();
      })()
    JS

    assert_no_selector "[data-help-target='helpDialog'][open]", wait: 3
  end

  test "help dialog keeps one scroll container and collapses to one column on narrower widths" do
    create_test_note("layout.md", "# Layout")

    visit root_url
    page.current_window.resize_to(900, 700)

    page.execute_script(<<~JS)
      (function() {
        const button = document.querySelector("button[title='Markdown Help (F1)']");
        if (button) button.click();
      })()
    JS

    assert_selector "[data-help-target='helpDialog'][open]", wait: 3

    within "[data-help-target='helpDialog']" do
      assert_button "Editor Extras"
      click_button "Editor Extras"
      assert_text "Duplicate line down"
      assert_text "Toggle line comment"
      assert_text "Select next occurrence"
    end

    metrics = page.evaluate_script(<<~JS)
      (function() {
        const dialog = document.querySelector('[data-help-target="helpDialog"]');
        const layout = dialog.querySelector(':scope > div');
        const body = layout.querySelector(':scope > div:last-child');
        const grid = dialog.querySelector('[data-help-target="panelEditorExtras"] .grid');
        return {
          dialogDisplay: getComputedStyle(dialog).display,
          layoutDisplay: getComputedStyle(layout).display,
          layoutMaxHeight: getComputedStyle(layout).maxHeight,
          bodyOverflowY: getComputedStyle(body).overflowY,
          bodyFlex: getComputedStyle(body).flexGrow,
          gridColumns: getComputedStyle(grid).gridTemplateColumns
        };
      })()
    JS

    refute_equal "none", metrics["dialogDisplay"]
    assert_equal "flex", metrics["layoutDisplay"]
    assert_not_equal "none", metrics["layoutMaxHeight"]
    assert_equal "auto", metrics["bodyOverflowY"]
    assert_equal "1", metrics["bodyFlex"]
    assert_equal 1, metrics["gridColumns"].split(" ").length
  end
end
