/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import { setupJsdomGlobals } from "../helpers/jsdom_globals.js"
import ShareViewController from "../../../app/javascript/controllers/share_view_controller.js"

describe("ShareViewController", () => {
  let application
  let element
  let controller
  let frame
  let article
  let frameDocument
  let originalInnerWidth
  let originalInnerHeight

  beforeEach(async () => {
    setupJsdomGlobals()
    window.t = vi.fn((key) => ({
      "status.copied_to_clipboard": "Copied",
      "status.copy_failed": "Copy failed",
      "status.export_failed": "Export failed",
      "status.private_note_link_unavailable": "Private note unavailable"
    }[key] || key))

    document.documentElement.setAttribute("data-theme", "dark")
    document.documentElement.classList.add("dark")
    document.documentElement.style.setProperty("--theme-bg-primary", "#101418")
    document.documentElement.style.setProperty("--theme-bg-secondary", "#162029")
    document.documentElement.style.setProperty("--theme-text-primary", "#f3f4f6")
    document.documentElement.style.setProperty("--theme-text-secondary", "#d1d5db")
    document.documentElement.style.setProperty("--theme-border", "#334155")
    document.documentElement.style.setProperty("--font-sans", "Inter, sans-serif")
    document.documentElement.style.setProperty("--font-mono", "JetBrains Mono, monospace")
    originalInnerWidth = window.innerWidth
    originalInnerHeight = window.innerHeight

    document.body.innerHTML = `
      <div
        data-controller="share-view"
        data-share-view-default-width-value="72"
        data-share-view-default-zoom-value="100"
        data-share-view-title-value="Shared Snapshot"
        data-share-view-show-controls-label-value="Show reading controls"
        data-share-view-hide-controls-label-value="Hide reading controls"
      >
        <button
          type="button"
          data-share-view-target="displayToggle"
          aria-expanded="true"
        >Display</button>
        <div data-share-view-target="displayPanel">
          <output data-share-view-target="zoomValue"></output>
          <output data-share-view-target="widthValue"></output>
          <select data-share-view-target="fontSelect">
            <option value="default">Default</option>
            <option value="sans">Sans</option>
            <option value="serif">Serif</option>
            <option value="mono">Mono</option>
          </select>
        </div>
        <iframe data-share-view-target="frame"></iframe>
      </div>
    `

    frame = document.querySelector("iframe")
    frameDocument = document.implementation.createHTMLDocument("Shared")
    frameDocument.documentElement.setAttribute("data-theme", "light")
    article = frameDocument.createElement("article")
    article.className = "export-article"
    article.innerHTML = "<h1>Shared Snapshot</h1><p>Body</p>"
    article.style.fontSize = "16px"
    article.style.maxWidth = "72ch"
    frameDocument.body.appendChild(article)

    Object.defineProperty(frame, "contentDocument", {
      configurable: true,
      value: frameDocument
    })

    Object.defineProperty(frame, "contentWindow", {
      configurable: true,
      value: { getComputedStyle: window.getComputedStyle.bind(window) }
    })

    element = document.querySelector('[data-controller="share-view"]')
    application = Application.start()
    application.register("share-view", ShareViewController)

    await new Promise((resolve) => setTimeout(resolve, 0))
    controller = application.getControllerForElementAndIdentifier(element, "share-view")
  })

  afterEach(() => {
    application.stop()
    window.innerWidth = originalInnerWidth
    window.innerHeight = originalInnerHeight
    vi.restoreAllMocks()
  })

  function setViewport(width, height) {
    Object.defineProperty(window, "innerWidth", {
      configurable: true,
      writable: true,
      value: width
    })
    Object.defineProperty(window, "innerHeight", {
      configurable: true,
      writable: true,
      value: height
    })
  }

  it("applies initial defaults and syncs the outer theme into the embedded snapshot", () => {
    controller.onFrameLoad()

    expect(controller.zoomValueTarget.textContent).toBe("100%")
    expect(controller.widthValueTarget.textContent).toBe("72ch")
    expect(article.style.maxWidth).toBe("72ch")
    expect(article.style.fontSize).toBe("16px")
    expect(frameDocument.documentElement.getAttribute("data-theme")).toBe("dark")
    expect(frameDocument.documentElement.style.getPropertyValue("--theme-bg-primary")).toBe("#101418")
  })

  it("updates zoom and width controls in the embedded snapshot", () => {
    controller.onFrameLoad()
    controller.zoomIn()
    controller.increaseWidth()

    expect(controller.zoomValueTarget.textContent).toBe("110%")
    expect(controller.widthValueTarget.textContent).toBe("76ch")
    expect(article.style.fontSize).toBe("17.6px")
    expect(article.style.maxWidth).toBe("76ch")
  })

  it("switches font families through the select control", () => {
    controller.onFrameLoad()

    controller.changeFontFamily({ target: { value: "serif" } })
    expect(article.style.fontFamily).toContain("Georgia")

    controller.changeFontFamily({ target: { value: "default" } })
    expect(article.style.fontFamily).toBe("")
  })

  it("collapses the display panel by default on mobile-sized viewports", () => {
    setViewport(390, 844)

    controller.syncResponsiveDisplayPanel()

    expect(controller.displayPanelTarget.classList.contains("hidden")).toBe(true)
    expect(controller.displayToggleTarget.getAttribute("aria-expanded")).toBe("false")
    expect(controller.displayToggleTarget.getAttribute("title")).toBe("Show reading controls")
  })

  it("keeps the display panel expanded by default on desktop-sized viewports", () => {
    setViewport(1280, 900)

    controller.syncResponsiveDisplayPanel()

    expect(controller.displayPanelTarget.classList.contains("hidden")).toBe(false)
    expect(controller.displayToggleTarget.getAttribute("aria-expanded")).toBe("true")
    expect(controller.displayToggleTarget.getAttribute("title")).toBe("Hide reading controls")
  })

  it("toggles the display panel from the display button state", () => {
    setViewport(1280, 900)
    controller.syncResponsiveDisplayPanel()

    controller.toggleDisplayPanel()
    expect(controller.displayPanelTarget.classList.contains("hidden")).toBe(true)
    expect(controller.displayToggleTarget.getAttribute("aria-expanded")).toBe("false")
    expect(controller.displayToggleTarget.getAttribute("title")).toBe("Show reading controls")

    controller.toggleDisplayPanel()
    expect(controller.displayPanelTarget.classList.contains("hidden")).toBe(false)
    expect(controller.displayToggleTarget.getAttribute("aria-expanded")).toBe("true")
    expect(controller.displayToggleTarget.getAttribute("title")).toBe("Hide reading controls")
  })

  it("routes export menu selections to the matching controller actions", async () => {
    controller.copyToClipboard = vi.fn().mockResolvedValue(true)
    controller.printDocument = vi.fn()
    controller.exportHtmlDocument = vi.fn()
    controller.exportTextDocument = vi.fn()

    await controller.onExportMenuSelected({ detail: { actionId: "copy-html" } })
    await controller.onExportMenuSelected({ detail: { actionId: "print-pdf" } })
    await controller.onExportMenuSelected({ detail: { actionId: "export-html" } })
    await controller.onExportMenuSelected({ detail: { actionId: "export-txt" } })

    expect(controller.copyToClipboard).toHaveBeenCalledTimes(1)
    expect(controller.printDocument).toHaveBeenCalledTimes(1)
    expect(controller.exportHtmlDocument).toHaveBeenCalledTimes(1)
    expect(controller.exportTextDocument).toHaveBeenCalledTimes(1)
  })

  it("copies the current article HTML and plain text to the clipboard", async () => {
    controller.onFrameLoad()

    const clipboardWrite = vi.fn().mockResolvedValue(undefined)
    navigator.clipboard = { write: clipboardWrite }
    global.ClipboardItem = class ClipboardItem {
      constructor(data) {
        this.data = data
      }
    }
    controller.showTemporaryMessage = vi.fn()

    await expect(controller.copyToClipboard()).resolves.toBe(true)

    expect(clipboardWrite).toHaveBeenCalledTimes(1)
    const clipboardItem = clipboardWrite.mock.calls[0][0][0]
    expect(clipboardItem.data["text/html"]).toBeInstanceOf(Blob)
    expect(clipboardItem.data["text/plain"]).toBeInstanceOf(Blob)
    expect(controller.showTemporaryMessage).toHaveBeenCalledWith("Copied")
  })

  it("blocks private note links inside the shared snapshot iframe", () => {
    controller.onFrameLoad()
    controller.showTemporaryMessage = vi.fn()

    const blockedLink = frameDocument.createElement("a")
    blockedLink.setAttribute("data-shared-link-kind", "internal-note")
    blockedLink.textContent = "Private note"
    article.appendChild(blockedLink)

    const clickEvent = new MouseEvent("click", { bubbles: true, cancelable: true, button: 0 })
    blockedLink.dispatchEvent(clickEvent)

    expect(clickEvent.defaultPrevented).toBe(true)
    expect(controller.showTemporaryMessage).toHaveBeenCalledWith("Private note unavailable")
  })
})
