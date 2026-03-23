# frozen_string_literal: true

require "application_system_test_case"

class PreviewTypographyTest < ApplicationSystemTestCase
  test "preview font setting is shared with reading mode and persists" do
    create_test_note("typography.md", "# Typography\n\nA paragraph for reading.")

    visit root_url
    find("[data-path='typography.md']").click

    click_app_target("previewToggle")
    assert_preview_font_matches("sans")

    open_customize_dialog
    within "dialog[open]" do
      find('[data-customize-target="previewFontSelect"] option[value="serif"]').select_option
      click_button "Apply"
    end

    assert_no_selector "dialog[open]", wait: 2
    assert_preview_font_matches("serif")

    click_app_target("readingModeToggle")
    assert reading_mode_enabled?, "Reading mode should activate"
    assert_preview_font_matches("serif")

    sleep 0.8
    assert_includes @test_notes_dir.join(".fed").read, "preview_font_family = serif"

    visit root_url
    find("[data-path='typography.md']").click
    click_app_target("previewToggle")

    assert_preview_font_matches("serif")
  end

  private

  def open_customize_dialog
    page.execute_script("document.querySelectorAll('[data-action=\"click->app#openCustomize\"]')[0].click()")
    assert_selector "dialog[open]", wait: 2
  end

  def assert_preview_font_matches(expected)
    font_family = page.evaluate_script(<<~JS)
      getComputedStyle(document.querySelector('[data-app-target="previewContent"]')).fontFamily
    JS

    case expected
    when "sans"
      assert_match(/Inter|sans/i, font_family)
    when "serif"
      assert_match(/Georgia|Times|serif/i, font_family)
    when "mono"
      assert_match(/JetBrains|monospace/i, font_family)
    else
      flunk("Unknown expected preview font: #{expected}")
    end
  end
end
