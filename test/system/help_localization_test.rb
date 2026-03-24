# frozen_string_literal: true

require "application_system_test_case"

class HelpLocalizationTest < ApplicationSystemTestCase
  test "editor extras help tab follows the active locale" do
    @test_notes_dir.join(".fed").write("locale = es\n")
    create_test_note("ideas.md", "# Ideas")

    visit root_url
    assert_selector "[data-app-target='fileTree']"

    page.execute_script(<<~JS)
      (function() {
        const button = document.querySelector("button[title='Ayuda de Markdown (F1)']");
        if (button) button.click();
      })()
    JS
    assert_selector "[data-help-target='helpDialog'][open]", wait: 3

    within "[data-help-target='helpDialog']" do
      click_button "Extras del Editor"
      assert_text "EDICIÓN"
      assert_text "SELECCIÓN Y COMENTARIOS"
      assert_text "Duplicar línea abajo"
      assert_text "Alternar comentario de línea"
      assert_text "Seleccionar siguiente coincidencia"
    end
  end
end
