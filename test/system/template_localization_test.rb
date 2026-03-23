# frozen_string_literal: true

require "application_system_test_case"

class TemplateLocalizationTest < ApplicationSystemTestCase
  test "template UI follows the active locale for server and JavaScript labels" do
    @test_notes_dir.join(".fed").write("locale = es\n")
    create_test_note("ideas.md", "# Ideas")

    visit root_url
    assert_selector "[data-app-target='fileTree']"

    assert_selector "button[title='Guardar como Plantilla']", visible: :all

    page.execute_script("document.querySelector('button[title=\"Nueva Nota (Ctrl+N)\"]').click()")
    assert_selector "[data-file-operations-target='noteTypeDialog'][open]", wait: 3

    within "[data-file-operations-target='noteTypeDialog']" do
      assert_text "Plantilla"
      assert_text "Comenzar desde una plantilla markdown guardada"
      click_button "Cancelar"
    end

    find("[data-path='ideas.md']").right_click
    assert_selector "[data-app-target='contextMenu']:not(.hidden)", wait: 3
    within "[data-app-target='contextMenu']" do
      assert_text "Guardar como Plantilla"
    end
  end
end
