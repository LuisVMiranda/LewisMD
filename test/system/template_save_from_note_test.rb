# frozen_string_literal: true

require "application_system_test_case"

class TemplateSaveFromNoteTest < ApplicationSystemTestCase
  test "saving the current note as a template from the header creates a linked template" do
    create_test_note("project-plan.md", "# Project Plan\n\n## Goals")
    service = TemplatesService.new(base_path: @test_notes_dir)

    visit root_url
    find("[data-path='project-plan.md']").click
    assert_selector "[data-app-target='currentPath']", text: "project-plan", wait: 3

    click_app_target("saveTemplateButton")
    assert_selector "[data-file-operations-target='saveTemplateDialog'][open]", wait: 3

    within "[data-file-operations-target='saveTemplateDialog']" do
      assert_text "project-plan.md"
      fill_in placeholder: "e.g. team/retro", with: "project-plan-template"
      click_button "Save"
    end

    assert_no_selector "[data-file-operations-target='saveTemplateDialog'][open]", wait: 3
    assert_eventually do
      service.template_linked?("project-plan.md") &&
        File.exist?(@test_notes_dir.join(".frankmd/templates/project-plan-template.md"))
    end
    assert_equal "project-plan-template.md", service.linked_template_path_for("project-plan.md")
  end

  test "right-clicking an unlinked markdown note offers save as template" do
    create_test_note("brainstorm.md", "# Brainstorm")

    visit root_url
    find("[data-path='brainstorm.md']").right_click

    assert_selector "[data-app-target='contextMenu']:not(.hidden)", wait: 3
    within "[data-app-target='contextMenu']" do
      assert_text "Save as Template"
      click_button "Save as Template"
    end

    assert_selector "[data-file-operations-target='saveTemplateDialog'][open]", wait: 3
    within "[data-file-operations-target='saveTemplateDialog']" do
      assert_text "brainstorm.md"
      click_button "Cancel"
    end
  end

  test "right-clicking a linked markdown note offers delete template and removes the link" do
    create_test_note("linked-note.md", "# Linked")
    service = TemplatesService.new(base_path: @test_notes_dir)
    linked_path = service.save_from_note(note_path: "linked-note.md", template_path: "linked-template")

    visit root_url
    find("[data-path='linked-note.md']").right_click

    assert_selector "[data-app-target='contextMenu']:not(.hidden)", wait: 3
    accept_confirm do
      within "[data-app-target='contextMenu']" do
        assert_text "Delete Template"
        click_button "Delete Template"
      end
    end

    assert_eventually do
      !service.template_linked?("linked-note.md") &&
        !File.exist?(@test_notes_dir.join(".frankmd/templates/#{linked_path}"))
    end
  end
end
