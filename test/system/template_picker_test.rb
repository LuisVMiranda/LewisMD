# frozen_string_literal: true

require "application_system_test_case"

class TemplatePickerTest < ApplicationSystemTestCase
  test "creating a note from a built-in template uses the template content" do
    expected_content = TemplatesService.new(base_path: @test_notes_dir).read("article-draft.md")

    visit root_url
    assert_selector "[data-app-target='fileTree']"

    page.execute_script("document.querySelector('button[title=\"New Note (Ctrl+N)\"]').click()")
    assert_selector "[data-file-operations-target='noteTypeDialog'][open]", wait: 3

    within "[data-file-operations-target='noteTypeDialog']" do
      click_button "Template", exact_text: true
    end
    assert_selector "[data-file-operations-target='templateDialog'][open]", wait: 3

    within "[data-file-operations-target='templateDialog']" do
      click_button "Article Draft"
    end

    assert_selector "[data-file-operations-target='newItemDialog'][open]", wait: 2

    within "[data-file-operations-target='newItemDialog']" do
      assert_equal "article-draft", find("[data-file-operations-target='newItemInput']").value
      click_button "Create"
    end

    assert_selector "[data-path='article-draft.md']", wait: 3
    assert_equal expected_content, File.read(@test_notes_dir.join("article-draft.md"))
  end

  test "user-added markdown templates appear in the picker and create notes" do
    service = TemplatesService.new(base_path: @test_notes_dir)
    service.write("team/retro.md", "# Retro\n\n## Wins\n\n- Great release")

    visit root_url
    assert_selector "[data-app-target='fileTree']"

    page.execute_script("document.querySelector('button[title=\"New Note (Ctrl+N)\"]').click()")
    assert_selector "[data-file-operations-target='noteTypeDialog'][open]", wait: 3

    within "[data-file-operations-target='noteTypeDialog']" do
      click_button "Template", exact_text: true
    end
    assert_selector "[data-file-operations-target='templateDialog'][open]", wait: 3

    within "[data-file-operations-target='templateDialog']" do
      assert_text "Retro"
      click_button "Retro"
    end

    assert_selector "[data-file-operations-target='newItemDialog'][open]", wait: 2

    within "[data-file-operations-target='newItemDialog']" do
      assert_equal "retro", find("[data-file-operations-target='newItemInput']").value
      click_button "Create"
    end

    assert_selector "[data-path='retro.md']", wait: 3
    assert_equal "# Retro\n\n## Wins\n\n- Great release", File.read(@test_notes_dir.join("retro.md"))
  end
end
