import { describe, expect, it, vi } from "vitest"
import {
  dispatchTranslationsLoaded,
  installGlobalTranslationHelper,
  lookupTranslation,
  setGlobalTranslations,
  translateKey
} from "../../../../app/javascript/lib/share_reader/translation_helpers.js"
import { setupJsdomGlobals } from "../../helpers/jsdom_globals.js"

describe("translation_helpers", () => {
  it("looks up and interpolates nested translation keys", () => {
    const translations = {
      export_menu: {
        copy_note: "Copy %{kind}"
      }
    }

    expect(lookupTranslation(translations, "export_menu.copy_note")).toBe("Copy %{kind}")
    expect(translateKey("export_menu.copy_note", { kind: "HTML" }, translations)).toBe("Copy HTML")
  })

  it("installs the global translation helper and dispatches updates", () => {
    setupJsdomGlobals()

    const eventSpy = vi.fn()
    window.addEventListener("frankmd:translations-loaded", eventSpy)

    installGlobalTranslationHelper(window)
    setGlobalTranslations({
      locale: "en",
      translations: {
        share_view: {
          label: "Shared note"
        }
      },
      globalObject: window
    })
    dispatchTranslationsLoaded({
      locale: "en",
      translations: window.frankmdTranslations,
      globalObject: window
    })

    expect(window.t("share_view.label")).toBe("Shared note")
    expect(eventSpy).toHaveBeenCalled()
  })
})
