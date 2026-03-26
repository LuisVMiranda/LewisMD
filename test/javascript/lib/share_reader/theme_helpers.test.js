import { describe, expect, it } from "vitest"
import {
  BUILTIN_THEMES,
  applyThemeToRoot,
  buildThemeUrl,
  renderThemeMenuHtml,
  resolvedThemeId,
  themeNameFor
} from "../../../../app/javascript/lib/share_reader/theme_helpers.js"
import { setupJsdomGlobals } from "../../helpers/jsdom_globals.js"

describe("theme_helpers", () => {
  it("keeps the built-in theme catalog intact", () => {
    expect(BUILTIN_THEMES[0].id).toBe("light")
    expect(BUILTIN_THEMES[1].id).toBe("dark")
  })

  it("renders theme menu html with the current checkmark", () => {
    const html = renderThemeMenuHtml({
      themes: BUILTIN_THEMES.slice(0, 2),
      currentThemeId: "dark"
    })

    expect(html).toContain('data-theme="dark"')
    expect(html).toContain("checkmark ")
    expect(html).toContain("Dark")
  })

  it("applies theme state to the root element", () => {
    setupJsdomGlobals()

    const result = applyThemeToRoot("dark")

    expect(document.documentElement.getAttribute("data-theme")).toBe("dark")
    expect(document.documentElement.classList.contains("dark")).toBe(true)
    expect(result).toEqual({ themeId: "dark", colorScheme: "dark" })
  })

  it("builds a theme URL without dropping existing params", () => {
    const url = buildThemeUrl("nord", "https://example.com/share?locale=ja")
    expect(url).toBe("https://example.com/share?locale=ja&theme=nord")
  })

  it("resolves names and fallback themes", () => {
    expect(themeNameFor("nord")).toBe("Nord")
    expect(resolvedThemeId(null, true)).toBe("dark")
    expect(resolvedThemeId(null, false)).toBe("light")
  })
})
