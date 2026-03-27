import { describe, expect, it, vi } from "vitest"
import {
  buildExportMenuItems,
  renderExportMenuHtml
} from "../../../../app/javascript/lib/share_reader/export_menu_helpers.js"

describe("export_menu_helpers", () => {
  it("builds the compact default menu", () => {
    const items = buildExportMenuItems({
      markdownCopyable: true,
      shareState: { shareable: true, active: false },
      exportGroupExpanded: false
    })

    expect(items).toHaveLength(5)
    expect(items.at(-2).id).toBe("create-share-link")
    expect(items.at(-1).id).toBe("manage-share-api")
  })

  it("includes nested export actions when expanded and active share actions when needed", () => {
    const items = buildExportMenuItems({
      markdownCopyable: false,
      shareState: { shareable: true, active: true },
      exportGroupExpanded: true
    })

    expect(items.map((item) => item.id)).toContain("export-html")
    expect(items.map((item) => item.id)).toContain("disable-share-link")
  })

  it("renders menu html using the translation callback", () => {
    const translate = vi.fn((key) => key)
    const html = renderExportMenuHtml({
      items: buildExportMenuItems({
        markdownCopyable: true,
        shareState: { shareable: true, active: false },
        exportGroupExpanded: false
      }),
      translate
    })

    expect(html).toContain('data-action="click->export-menu#toggleExportGroup"')
    expect(html).toContain("export_menu.create_share_link")
    expect(translate).toHaveBeenCalled()
  })
})
