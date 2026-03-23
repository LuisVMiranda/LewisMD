/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import StatusStripController from "../../../app/javascript/controllers/status_strip_controller.js"

describe("StatusStripController", () => {
  let application
  let controller
  let element

  beforeEach(async () => {
    window.t = vi.fn((key) => {
      const translations = {
        "status_strip.mode_prefix": "Mode",
        "status_strip.modes.raw": "Raw",
        "status_strip.modes.preview": "Preview",
        "status_strip.modes.reading": "Reading",
        "status_strip.modes.typewriter": "Typewriter",
        "status_strip.save.saved": "Saved",
        "status_strip.save.unsaved": "Unsaved",
        "status_strip.save.offline": "Offline",
        "status_strip.save.error": "Save error",
        "status_strip.recovery_available": "Recovery available",
        "status_strip.metrics.line": "Ln",
        "status_strip.metrics.selection": "Sel",
        "status_strip.metrics.zoom": "Zoom"
      }

      return translations[key] || key
    })

    document.body.innerHTML = `
      <div data-controller="status-strip">
        <div data-status-strip-target="strip" class="hidden">
          <span data-status-strip-target="modeChip"></span>
          <span data-status-strip-target="saveChip" class="hidden"></span>
          <span data-status-strip-target="recoveryChip" class="hidden"></span>
          <span data-status-strip-target="lineMetric" class="hidden"></span>
          <span data-status-strip-target="selectionMetric" class="hidden"></span>
          <span data-status-strip-target="zoomMetric" class="hidden"></span>
        </div>
      </div>
    `

    element = document.querySelector('[data-controller="status-strip"]')
    application = Application.start()
    application.register("status-strip", StatusStripController)

    await new Promise((resolve) => setTimeout(resolve, 0))
    controller = application.getControllerForElementAndIdentifier(element, "status-strip")
  })

  afterEach(() => {
    application.stop()
    vi.restoreAllMocks()
  })

  it("starts hidden until a markdown note state is available", () => {
    expect(controller.stripTarget.classList.contains("hidden")).toBe(true)

    controller.onStateChanged({
      detail: {
        state: {
          path: null,
          isMarkdown: false
        }
      }
    })

    expect(controller.stripTarget.classList.contains("hidden")).toBe(true)
  })

  it("renders mode, save, line, selection, and zoom details for markdown notes", () => {
    controller.onAutosaveStatus({
      detail: {
        status: "unsaved",
        currentFile: "notes/test.md",
        hasUnsavedChanges: true
      }
    })

    controller.onStateChanged({
      detail: {
        state: {
          path: "notes/test.md",
          isMarkdown: true,
          mode: "preview",
          previewVisible: true,
          previewZoom: 125,
          cursorLine: 4,
          totalLines: 12,
          selectionLength: 8,
          hasSelection: true,
          recoveryAvailable: false
        }
      }
    })

    expect(controller.stripTarget.classList.contains("hidden")).toBe(false)
    expect(controller.modeChipTarget.textContent).toBe("Mode: Preview")
    expect(controller.modeChipTarget.dataset.tone).toBe("accent")
    expect(controller.saveChipTarget.textContent).toBe("Unsaved")
    expect(controller.saveChipTarget.dataset.tone).toBe("accent")
    expect(controller.lineMetricTarget.textContent).toBe("Ln 4/12")
    expect(controller.selectionMetricTarget.textContent).toBe("Sel 8")
    expect(controller.zoomMetricTarget.textContent).toBe("Zoom 125%")
  })

  it("shows saved for idle autosave state and ignores stale autosave events from another file", () => {
    controller.onAutosaveStatus({
      detail: {
        status: "offline",
        currentFile: "notes/other.md",
        hasUnsavedChanges: true
      }
    })

    controller.onStateChanged({
      detail: {
        state: {
          path: "notes/test.md",
          isMarkdown: true,
          mode: "raw",
          previewVisible: false,
          previewZoom: 100,
          cursorLine: 1,
          totalLines: 1,
          selectionLength: 0,
          hasSelection: false,
          recoveryAvailable: false
        }
      }
    })

    expect(controller.saveChipTarget.textContent).toBe("Saved")
    expect(controller.saveChipTarget.dataset.tone).toBe("muted")
    expect(controller.selectionMetricTarget.classList.contains("hidden")).toBe(true)
    expect(controller.zoomMetricTarget.classList.contains("hidden")).toBe(true)
  })

  it("shows recovery and error states when present", () => {
    controller.onAutosaveStatus({
      detail: {
        status: "error",
        currentFile: "notes/test.md",
        hasUnsavedChanges: true
      }
    })

    controller.onStateChanged({
      detail: {
        state: {
          path: "notes/test.md",
          isMarkdown: true,
          mode: "reading",
          previewVisible: true,
          previewZoom: 110,
          cursorLine: 6,
          totalLines: 20,
          selectionLength: 0,
          hasSelection: false,
          recoveryAvailable: true
        }
      }
    })

    expect(controller.saveChipTarget.textContent).toBe("Save error")
    expect(controller.saveChipTarget.dataset.tone).toBe("error")
    expect(controller.recoveryChipTarget.textContent).toBe("Recovery available")
    expect(controller.recoveryChipTarget.classList.contains("hidden")).toBe(false)
  })

  it("hides itself again when a non-markdown file is opened", () => {
    controller.onStateChanged({
      detail: {
        state: {
          path: "notes/test.md",
          isMarkdown: true,
          mode: "raw",
          previewVisible: false,
          previewZoom: 100,
          cursorLine: 1,
          totalLines: 1,
          selectionLength: 0,
          hasSelection: false,
          recoveryAvailable: false
        }
      }
    })

    expect(controller.stripTarget.classList.contains("hidden")).toBe(false)

    controller.onStateChanged({
      detail: {
        state: {
          path: ".fed",
          isMarkdown: false,
          mode: "raw"
        }
      }
    })

    expect(controller.stripTarget.classList.contains("hidden")).toBe(true)
  })
})
