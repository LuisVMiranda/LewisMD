import { describe, expect, it } from "vitest"
import {
  AVAILABLE_LOCALES,
  buildLocaleUrl,
  localeFlagMarkup,
  localeNameFor,
  renderLocaleMenuHtml
} from "../../../../app/javascript/lib/share_reader/locale_helpers.js"

describe("locale_helpers", () => {
  it("keeps the locale catalog intact", () => {
    expect(AVAILABLE_LOCALES[0].id).toBe("en")
    expect(AVAILABLE_LOCALES.map((locale) => locale.id)).toContain("pt-BR")
  })

  it("renders locale menu html with flags and a selected item", () => {
    const html = renderLocaleMenuHtml({
      locales: AVAILABLE_LOCALES.slice(0, 2),
      currentLocaleId: "pt-BR"
    })

    expect(html).toContain('data-locale="pt-BR"')
    expect(html).toContain("Portugu")
    expect(html).toContain("checkmark ")
  })

  it("returns locale helpers for labels, flags, and urls", () => {
    expect(localeNameFor("ja")).toBe("\u65e5\u672c\u8a9e")
    expect(localeFlagMarkup("us")).toContain("\ud83c\uddfa\ud83c\uddf8")
    expect(buildLocaleUrl("es", "https://example.com/share?theme=dark"))
      .toBe("https://example.com/share?theme=dark&locale=es")
  })
})
