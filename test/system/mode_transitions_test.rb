# frozen_string_literal: true

require "application_system_test_case"

class ModeTransitionsTest < ApplicationSystemTestCase
  test "closing preview returns to the raw editor without enabling typewriter" do
    create_test_note("preview_mode_reset.md", "# Preview Test\n\nSome **bold** text")

    visit root_url
    find("[data-path='preview_mode_reset.md']").click

    sleep 0.3

    preview_panel = find("[data-app-target='previewPanel']", visible: :all)
    editor_panel = find("[data-app-target='editorPanel']", visible: :all)

    assert preview_panel[:class].include?("hidden"), "Preview should start hidden"
    refute typewriter_mode_enabled?, "Typewriter should start disabled"

    click_app_target("previewToggle")

    sleep 0.2
    refute preview_panel[:class].include?("hidden"), "Preview should open on first toggle"
    refute typewriter_mode_enabled?, "Opening preview should not enable typewriter"

    click_app_target("previewToggle")

    sleep 0.2
    assert preview_panel[:class].include?("hidden"), "Preview should close on second toggle"
    refute editor_panel[:class].include?("hidden"), "Editor should stay visible in raw mode"
    refute typewriter_mode_enabled?, "Closing preview should return to raw mode"
    assert_equal "false", typewriter_toggle_button["aria-pressed"]
  end

  test "preview toggle exits reading mode without forcing typewriter" do
    create_test_note("reading_mode_reset.md", "# Reading\n\nBody copy")

    visit root_url
    find("[data-path='reading_mode_reset.md']").click

    sleep 0.3

    preview_panel = find("[data-app-target='previewPanel']", visible: :all)
    editor_panel = find("[data-app-target='editorPanel']", visible: :all)

    click_app_target("readingModeToggle")

    sleep 0.2
    assert reading_mode_enabled?, "Reading mode should activate"
    refute preview_panel[:class].include?("hidden"), "Preview should be visible in reading mode"
    assert editor_panel[:class].include?("hidden"), "Editor should be hidden in reading mode"
    refute typewriter_mode_enabled?, "Reading mode should not implicitly enable typewriter"

    click_app_target("previewToggle")

    sleep 0.2
    refute reading_mode_enabled?, "Preview toggle should exit reading mode first"
    assert preview_panel[:class].include?("hidden"), "Preview should be hidden after leaving reading mode"
    refute editor_panel[:class].include?("hidden"), "Editor should return when reading mode ends"
    refute typewriter_mode_enabled?, "Leaving reading mode should return to raw mode"
    assert_equal "false", typewriter_toggle_button["aria-pressed"]
  end

  test "opening preview while typewriter is active disables typewriter first" do
    create_test_note("typewriter_preview_exclusive.md", "# Exclusive\n\nBody copy")

    visit root_url
    find("[data-path='typewriter_preview_exclusive.md']").click

    sleep 0.3

    preview_panel = find("[data-app-target='previewPanel']", visible: :all)

    page.execute_script("document.querySelector('[data-typewriter-mode-btn]').click()")

    sleep 0.2
    assert typewriter_mode_enabled?, "Typewriter should activate"
    assert preview_panel[:class].include?("hidden"), "Preview should stay hidden in typewriter mode"

    click_app_target("previewToggle")

    sleep 0.2
    refute typewriter_mode_enabled?, "Opening preview should disable typewriter"
    refute preview_panel[:class].include?("hidden"), "Preview should be visible after toggle"
    assert_equal "false", typewriter_toggle_button["aria-pressed"]
  end

  test "entering reading mode while typewriter is active disables typewriter first" do
    create_test_note("typewriter_reading_exclusive.md", "# Exclusive\n\nBody copy")

    visit root_url
    find("[data-path='typewriter_reading_exclusive.md']").click

    sleep 0.3

    preview_panel = find("[data-app-target='previewPanel']", visible: :all)
    editor_panel = find("[data-app-target='editorPanel']", visible: :all)

    page.execute_script("document.querySelector('[data-typewriter-mode-btn]').click()")

    sleep 0.2
    assert typewriter_mode_enabled?, "Typewriter should activate"
    refute reading_mode_enabled?, "Reading mode should start disabled"

    click_app_target("readingModeToggle")

    sleep 0.2
    refute typewriter_mode_enabled?, "Reading mode should disable typewriter"
    assert reading_mode_enabled?, "Reading mode should activate"
    refute preview_panel[:class].include?("hidden"), "Preview should be visible in reading mode"
    assert editor_panel[:class].include?("hidden"), "Editor should be hidden in reading mode"
    assert_equal "false", typewriter_toggle_button["aria-pressed"]
  end

  test "preview mode and preview width survive a refresh" do
    create_test_note("preview_refresh_persistence.md", "# Preview Persist\n\nBody copy")

    visit root_url
    find("[data-path='preview_refresh_persistence.md']").click

    sleep 0.3

    click_app_target("previewToggle")
    set_preview_width(55)
    sleep 0.8

    visit current_url

    assert preview_visible?, "Preview should still be visible after refresh"
    assert_equal 55, preview_width_value
    refute reading_mode_enabled?, "Preview restore should not enter reading mode"
    refute typewriter_mode_enabled?, "Preview restore should not enable typewriter"
  end

  test "reading mode survives a refresh without bouncing back to typewriter" do
    create_test_note("reading_refresh_persistence.md", "# Reading Persist\n\nBody copy")

    visit root_url
    find("[data-path='reading_refresh_persistence.md']").click

    sleep 0.3

    click_app_target("readingModeToggle")
    sleep 0.8

    visit current_url

    assert reading_mode_enabled?, "Reading mode should restore after refresh"
    assert preview_visible?, "Preview should be visible after restoring reading mode"
    refute typewriter_mode_enabled?, "Reading restore should not bounce to typewriter"
  end
end
