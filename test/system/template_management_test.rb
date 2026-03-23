# frozen_string_literal: true

require "application_system_test_case"

class TemplateManagementTest < ApplicationSystemTestCase
  test "template manager creates a new template from the picker flow" do
    visit root_url
    assert_selector "[data-app-target='fileTree']"

    page.execute_script("document.querySelector('button[title=\"New Note (Ctrl+N)\"]').click()")
    assert_selector "[data-file-operations-target='noteTypeDialog'][open]", wait: 3

    within "[data-file-operations-target='noteTypeDialog']" do
      click_button "Template", exact_text: true
    end
    assert_selector "[data-file-operations-target='templateDialog'][open]", wait: 3

    within "[data-file-operations-target='templateDialog']" do
      click_button "Manage Templates"
    end

    assert_selector "[data-file-operations-target='templateManagerDialog'][open]", wait: 3

    within "[data-file-operations-target='templateManagerDialog']" do
      click_button "New Template"
      fill_in placeholder: "e.g. team/retro", with: "team/retro"
      fill_in placeholder: "Write your template markdown here...", with: "# Retro Template\n\n## Wins\n\n- Great release"
      click_button "Save"
    end

    within "[data-file-operations-target='templateManagerDialog']" do
      assert_text "Template saved"
    end

    assert_eventually do
      File.exist?(@test_notes_dir.join(".frankmd/templates/team/retro.md"))
    end
    assert_includes File.read(@test_notes_dir.join(".frankmd/templates/team/retro.md")), "Great release"
  end

  test "template manager edits and deletes an existing template" do
    TemplatesService.new(base_path: @test_notes_dir).write("team/retro.md", "# Retro\n\n## Wins")

    visit root_url
    assert_selector "[data-app-target='fileTree']"

    page.execute_script("document.querySelector('button[title=\"New Note (Ctrl+N)\"]').click()")
    assert_selector "[data-file-operations-target='noteTypeDialog'][open]", wait: 3

    within "[data-file-operations-target='noteTypeDialog']" do
      click_button "Template", exact_text: true
    end
    assert_selector "[data-file-operations-target='templateDialog'][open]", wait: 3

    within "[data-file-operations-target='templateDialog']" do
      click_button "Manage Templates"
    end

    assert_selector "[data-file-operations-target='templateManagerDialog'][open]", wait: 3

    within "[data-file-operations-target='templateManagerDialog']" do
      click_button "Retro"
      fill_in placeholder: "Write your template markdown here...", with: "# Retro\n\n## Wins\n\n- Updated"
      click_button "Save"
    end

    assert_eventually do
      File.read(@test_notes_dir.join(".frankmd/templates/team/retro.md")).include?("- Updated")
    end

    assert_eventually do
      page.evaluate_script(<<~JS) == "team/retro.md"
        (function() {
          var input = document.querySelector('[data-file-operations-target="templatePathInput"]')
          return input ? input.value : null
        })()
      JS
    end

    accept_confirm do
      within "[data-file-operations-target='templateManagerDialog']" do
        click_button "Delete"
      end
    end

    within "[data-file-operations-target='templateManagerDialog']" do
      assert_text "Template deleted"
    end

    assert_eventually do
      !File.exist?(@test_notes_dir.join(".frankmd/templates/team/retro.md"))
    end
  end

  test "template manager preserves accented names when listing templates" do
    TemplatesService.new(base_path: @test_notes_dir).write("reunião wise up", "# Reunião")

    visit root_url
    assert_selector "[data-app-target='fileTree']"

    page.execute_script("document.querySelector('button[title=\"New Note (Ctrl+N)\"]').click()")
    assert_selector "[data-file-operations-target='noteTypeDialog'][open]", wait: 3

    within "[data-file-operations-target='noteTypeDialog']" do
      click_button "Template", exact_text: true
    end
    assert_selector "[data-file-operations-target='templateDialog'][open]", wait: 3

    within "[data-file-operations-target='templateDialog']" do
      click_button "Manage Templates"
    end

    assert_selector "[data-file-operations-target='templateManagerDialog'][open]", wait: 3
    within "[data-file-operations-target='templateManagerDialog']" do
      assert_text "Reunião Wise Up"
      assert_no_text "ReuniãO Wise Up"
    end
  end
end
