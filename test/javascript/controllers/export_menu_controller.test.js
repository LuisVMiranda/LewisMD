/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import { setupJsdomGlobals } from "../helpers/jsdom_globals.js"
import ExportMenuController from "../../../app/javascript/controllers/export_menu_controller.js"

describe("ExportMenuController", () => {
  let application
  let controller
  let element
  let translations

  beforeEach(async () => {
    setupJsdomGlobals()

    translations = {
      "export_menu.copy_note": "Copy Note (Ctrl+C)",
      "export_menu.copy_markdown": "Copy Markdown",
      "export_menu.export_files": "Export files",
      "export_menu.export_html": "Export HTML",
      "export_menu.export_txt": "Export TXT",
      "export_menu.export_pdf": "Export PDF",
      "export_menu.create_share_link": "Create shared link",
      "export_menu.copy_share_link": "Copy shared link",
      "export_menu.refresh_share_link": "Refresh shared snapshot",
      "export_menu.disable_share_link": "Disable shared link",
      "export_menu.manage_api": "Manage API"
    }

    window.t = vi.fn((key) => translations[key] || key)

    document.body.innerHTML = `
      <div data-controller="export-menu">
        <button
          type="button"
          data-export-menu-target="button"
          aria-expanded="false"
        ></button>
        <div data-export-menu-target="menu" class="hidden"></div>
      </div>
    `

    element = document.querySelector('[data-controller="export-menu"]')
    application = Application.start()
    application.register("export-menu", ExportMenuController)

    await new Promise((resolve) => setTimeout(resolve, 0))
    controller = application.getControllerForElementAndIdentifier(element, "export-menu")
  })

  afterEach(() => {
    application.stop()
    vi.restoreAllMocks()
  })

  it("renders a compact top-level menu by default", () => {
    const buttons = controller.menuTarget.querySelectorAll("button")

    expect(buttons).toHaveLength(5)
    expect(buttons[0].dataset.actionId).toBe("copy-html")
    expect(buttons[1].dataset.actionId).toBe("copy-markdown")
    expect(buttons[2].dataset.actionId).toBeUndefined()
    expect(buttons[3].dataset.actionId).toBe("create-share-link")
    expect(buttons[4].dataset.actionId).toBe("manage-share-api")
    expect(controller.menuTarget.textContent).toContain("Copy Note (Ctrl+C)")
    expect(controller.menuTarget.textContent).toContain("Copy Markdown")
    expect(controller.menuTarget.textContent).toContain("Export files")
    expect(controller.menuTarget.textContent).toContain("Create shared link")
    expect(controller.menuTarget.textContent).toContain("Manage API")
    expect(controller.menuTarget.textContent).not.toContain("Export HTML")
  })

  it("switches to active share actions when a share exists", () => {
    controller.setShareState({
      shareable: true,
      active: true,
      url: "http://localhost:7591/s/abc123"
    })

    const buttons = Array.from(controller.menuTarget.querySelectorAll("button"))

    expect(buttons).toHaveLength(7)
    expect(buttons[3].dataset.actionId).toBe("copy-share-link")
    expect(buttons[5].dataset.actionId).toBe("disable-share-link")
    expect(buttons[6].dataset.actionId).toBe("manage-share-api")
    expect(controller.menuTarget.textContent).toContain("Copy shared link")
    expect(controller.menuTarget.textContent).toContain("Refresh shared snapshot")
    expect(controller.menuTarget.textContent).toContain("Disable shared link")
    expect(controller.menuTarget.textContent).toContain("Manage API")
    expect(controller.menuTarget.textContent).not.toContain("Create shared link")
  })

  it("hides share actions when the current file is not shareable", () => {
    controller.setShareState({ shareable: false, active: false })

    const buttons = controller.menuTarget.querySelectorAll("button")

    expect(buttons).toHaveLength(4)
    expect(controller.menuTarget.textContent).not.toContain("Create shared link")
    expect(controller.menuTarget.textContent).toContain("Manage API")
  })

  it("uses the shareable value on connect", async () => {
    application.stop()

    document.body.innerHTML = `
      <div data-controller="export-menu" data-export-menu-shareable-value="false" data-export-menu-markdown-copyable-value="false">
        <button
          type="button"
          data-export-menu-target="button"
          aria-expanded="false"
        ></button>
        <div data-export-menu-target="menu" class="hidden"></div>
      </div>
    `

    element = document.querySelector('[data-controller="export-menu"]')
    application = Application.start()
    application.register("export-menu", ExportMenuController)
    await new Promise((resolve) => setTimeout(resolve, 0))
    controller = application.getControllerForElementAndIdentifier(element, "export-menu")

    expect(controller.menuTarget.querySelectorAll("button")).toHaveLength(3)
    expect(controller.menuTarget.textContent).toContain("Copy Note (Ctrl+C)")
    expect(controller.menuTarget.textContent).not.toContain("Copy Markdown")
    expect(controller.menuTarget.textContent).not.toContain("Create shared link")
    expect(controller.menuTarget.textContent).toContain("Manage API")
  })

  it("expands and collapses file export actions inline", () => {
    controller.toggleExportGroup({ stopPropagation: vi.fn() })

    let buttons = Array.from(controller.menuTarget.querySelectorAll("button"))
    expect(buttons).toHaveLength(8)
    expect(buttons[3].dataset.actionId).toBe("export-html")
    expect(controller.menuTarget.textContent).toContain("Export HTML")
    expect(controller.menuTarget.textContent).toContain("Export PDF")
    expect(controller.menuTarget.textContent).toContain("Manage API")

    controller.toggleExportGroup({ stopPropagation: vi.fn() })

    buttons = Array.from(controller.menuTarget.querySelectorAll("button"))
    expect(buttons).toHaveLength(5)
    expect(controller.menuTarget.textContent).not.toContain("Export HTML")
  })

  it("toggles the menu and keeps aria-expanded in sync", () => {
    const event = { stopPropagation: vi.fn() }

    controller.toggle(event)
    expect(controller.menuTarget.classList.contains("hidden")).toBe(false)
    expect(controller.buttonTarget.getAttribute("aria-expanded")).toBe("true")

    controller.toggle(event)
    expect(controller.menuTarget.classList.contains("hidden")).toBe(true)
    expect(controller.buttonTarget.getAttribute("aria-expanded")).toBe("false")
  })

  it("opens the menu programmatically", () => {
    controller.openMenu()

    expect(controller.menuTarget.classList.contains("hidden")).toBe(false)
    expect(controller.buttonTarget.getAttribute("aria-expanded")).toBe("true")
  })

  it("dispatches the selected action id and closes the menu", () => {
    const selectedSpy = vi.fn()
    element.addEventListener("export-menu:selected", selectedSpy)
    controller.menuTarget.classList.remove("hidden")
    controller.toggleExportGroup({ stopPropagation: vi.fn() })

    controller.select({
      currentTarget: controller.menuTarget.querySelector("[data-action-id='copy-html']")
    })

    expect(controller.menuTarget.classList.contains("hidden")).toBe(true)
    expect(controller.menuTarget.textContent).not.toContain("Export HTML")
    expect(selectedSpy).toHaveBeenCalledTimes(1)
    expect(selectedSpy.mock.calls[0][0].detail).toEqual({ actionId: "copy-html" })
  })

  it("closes when clicking outside the menu", () => {
    controller.menuTarget.classList.remove("hidden")

    const outsideElement = document.createElement("div")
    document.body.appendChild(outsideElement)

    outsideElement.dispatchEvent(new window.MouseEvent("click", {
      bubbles: true,
      cancelable: true
    }))

    expect(controller.menuTarget.classList.contains("hidden")).toBe(true)
  })

  it("rerenders labels when translations reload", () => {
    translations["export_menu.export_files"] = "Download files"

    window.dispatchEvent(new CustomEvent("frankmd:translations-loaded"))

    expect(controller.menuTarget.textContent).toContain("Download files")
    expect(window.t).toHaveBeenCalledWith("export_menu.export_files")
  })
})
