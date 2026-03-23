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

  beforeEach(async () => {
    setupJsdomGlobals()
    window.t = vi.fn((key) => ({
      "status.copied_to_clipboard": "Copied",
      "status.copy_failed": "Copy failed",
      "status.export_failed": "Export failed"
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

    document.body.innerHTML = `
      <div
        data-controller="share-view"
        data-share-view-default-width-value="72"
        data-share-view-default-zoom-value="100"
        data-share-view-title-value="Shared Snapshot"
      >
        <iframe data-share-view-target="frame"></iframe>
        <output data-share-view-target="zoomValue"></output>
        <output data-share-view-target="widthValue"></output>
        <select data-share-view-target="fontSelect">
          <option value="default">Default</option>
          <option value="sans">Sans</option>
          <option value="serif">Serif</option>
          <option value="mono">Mono</option>
        </select>
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
    vi.restoreAllMocks()
  })

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
})
