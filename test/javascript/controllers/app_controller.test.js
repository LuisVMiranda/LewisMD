/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, beforeEach, vi } from "vitest"
import AppController from "../../../app/javascript/controllers/app_controller.js"
import { buildDocumentOutline } from "../../../app/javascript/lib/document_outline.js"

describe("AppController shared UI state", () => {
  let controller
  let previewController
  let typewriterController
  let configController
  let codemirrorController
  let outlineController
  let splitPaneController
  let exportMenuController

  beforeEach(() => {
    previewController = {
      isVisible: false,
      hasContentTarget: true,
      zoomValue: 125,
      show: vi.fn(() => {
        previewController.isVisible = true
      }),
      hide: vi.fn(() => {
        previewController.isVisible = false
      }),
      render: vi.fn(),
      renderContent: vi.fn(),
      getRenderedDocumentPayload: vi.fn((metadata) => ({
        ...metadata,
        html: "<h1>Example</h1>",
        plainText: "Example"
      })),
      syncToLineSmooth: vi.fn(),
      toggle: vi.fn(() => {
        previewController.isVisible = !previewController.isVisible
      })
    }

    typewriterController = {
      enabledValue: false,
      toggle: vi.fn(() => {
        typewriterController.enabledValue = !typewriterController.enabledValue
      })
    }

    configController = {
      previewZoom: 110,
      previewWidth: 55,
      persistedActiveMode: "raw",
      activeModeValue: "",
      typewriterModeValue: false
    }

    codemirrorController = {
      editor: {
        state: { doc: { length: 16 } },
        dispatch: vi.fn()
      },
      getValue: vi.fn(() => "# Example\n\nBody"),
      getCursorInfo: vi.fn(() => ({ currentLine: 4, totalLines: 20 })),
      getCursorPosition: vi.fn(() => ({ line: 4, column: 7, offset: 42 })),
      getSelection: vi.fn(() => ({ from: 10, to: 14, text: "test" })),
      scrollToPosition: vi.fn()
    }

    outlineController = {
      update: vi.fn(),
      hide: vi.fn(),
      setActiveLine: vi.fn()
    }

    splitPaneController = {
      applyWidth: vi.fn()
    }

    exportMenuController = {
      setShareState: vi.fn()
    }

    controller = Object.create(AppController.prototype)
    controller.currentFile = "notes/test.md"
    controller.currentFileType = "markdown"
    controller.readingModeActive = false
    controller.recoveryAvailable = false
    controller._lastUiStateSignature = null
    controller._codemirrorReady = true
    controller._restoringPersistedUiState = false
    controller.pendingConfigSettings = {}
    controller.dispatch = vi.fn()
    controller.saveConfig = vi.fn()
    controller.getPreviewController = vi.fn(() => previewController)
    controller.getTypewriterController = vi.fn(() => typewriterController)
    controller.getEditorConfigController = vi.fn(() => configController)
    controller.getCodemirrorController = vi.fn(() => codemirrorController)
    controller.getOutlineController = vi.fn(() => outlineController)
    controller.getSplitPaneController = vi.fn(() => splitPaneController)
    controller.getExportMenuController = vi.fn(() => exportMenuController)
    controller.hasPreviewPanelTarget = false
    controller.hasTextareaTarget = false
  })

  it("builds preview mode state from the current controller state", () => {
    previewController.isVisible = true

    expect(controller.buildUiStateSnapshot()).toMatchObject({
      path: "notes/test.md",
      fileType: "markdown",
      isMarkdown: true,
      mode: "preview",
      previewVisible: true,
      readingActive: false,
      typewriterActive: false,
      previewZoom: 125,
      cursorLine: 4,
      totalLines: 20,
      column: 7,
      selectionLength: 4,
      hasSelection: true,
      recoveryAvailable: false
    })
  })

  it("prefers typewriter over preview and reading over typewriter", () => {
    previewController.isVisible = true
    typewriterController.enabledValue = true

    expect(controller.buildUiStateSnapshot().mode).toBe("typewriter")

    controller.readingModeActive = true

    expect(controller.buildUiStateSnapshot().mode).toBe("reading")
  })

  it("forces raw mode for non-markdown files", () => {
    controller.currentFile = ".fed"
    controller.currentFileType = "config"
    previewController.isVisible = true
    typewriterController.enabledValue = true
    controller.readingModeActive = true

    expect(controller.buildUiStateSnapshot()).toMatchObject({
      path: ".fed",
      fileType: "config",
      isMarkdown: false,
      mode: "raw",
      previewVisible: true,
      readingActive: true,
      typewriterActive: true
    })
  })

  it("falls back to editor config zoom when the preview controller is unavailable", () => {
    controller.getPreviewController = vi.fn(() => null)

    expect(controller.buildUiStateSnapshot().previewZoom).toBe(110)
  })

  it("dedupes unchanged state emissions", () => {
    controller.emitUiStateChanged("selection-changed")
    controller.emitUiStateChanged("selection-changed")

    expect(controller.dispatch).toHaveBeenCalledTimes(1)
    expect(controller.dispatch).toHaveBeenCalledWith("state-changed", {
      detail: {
        reason: "selection-changed",
        state: expect.objectContaining({
          mode: "raw",
          selectionLength: 4
        })
      }
    })
  })

  it("emits again when the snapshot changes", () => {
    controller.emitUiStateChanged("selection-changed")
    controller.recoveryAvailable = true
    controller.emitUiStateChanged("recovery-opened")

    expect(controller.dispatch).toHaveBeenCalledTimes(2)
    expect(controller.dispatch).toHaveBeenLastCalledWith("state-changed", {
      detail: {
        reason: "recovery-opened",
        state: expect.objectContaining({
          recoveryAvailable: true
        })
      }
    })
  })

  it("toggles recovery availability through the event handlers", () => {
    const emitSpy = vi.spyOn(controller, "emitUiStateChanged").mockImplementation(() => {})

    controller.onRecoveryDialogOpened()
    expect(controller.recoveryAvailable).toBe(true)
    expect(emitSpy).toHaveBeenCalledWith("recovery-opened")

    controller.onRecoveryDialogResolved()
    expect(controller.recoveryAvailable).toBe(false)
    expect(emitSpy).toHaveBeenCalledWith("recovery-resolved")
  })

  it("emits shared state after document changes so line and selection metrics stay fresh", () => {
    const autosaveController = {
      checkContentRestored: vi.fn(),
      scheduleOfflineBackup: vi.fn(),
      scheduleAutoSave: vi.fn()
    }
    const emitSpy = vi.spyOn(controller, "emitUiStateChanged").mockImplementation(() => {})

    controller.getAutosaveController = vi.fn(() => autosaveController)
    controller.getScrollSyncController = vi.fn(() => null)
    controller.scheduleStatsUpdate = vi.fn()
    controller.scheduleOutlineRefresh = vi.fn()
    controller.checkTableAtCursor = vi.fn()
    controller.maintainTypewriterScroll = vi.fn()
    controller.getEditorConfigController = vi.fn(() => ({
      previewZoom: 110,
      typewriterModeEnabled: false
    }))

    controller.onEditorChange({ detail: { docChanged: true } })

    expect(controller.scheduleStatsUpdate).toHaveBeenCalled()
    expect(controller.scheduleOutlineRefresh).toHaveBeenCalled()
    expect(autosaveController.checkContentRestored).toHaveBeenCalled()
    expect(autosaveController.scheduleOfflineBackup).toHaveBeenCalled()
    expect(autosaveController.scheduleAutoSave).toHaveBeenCalled()
    expect(emitSpy).toHaveBeenCalledWith("document-changed")
  })

  it("normalizes accepted AI text, restores cursor placement, and refreshes stats", () => {
    previewController.isVisible = true
    controller.updateStats = vi.fn()

    controller.onAiAccepted({
      detail: {
        correctedText: "Line 1\r\nLine 2\rLine 3",
        range: { from: 5, to: 9 }
      }
    })

    expect(codemirrorController.editor.dispatch).toHaveBeenCalledWith({
      changes: { from: 5, to: 9, insert: "Line 1\nLine 2\nLine 3" },
      selection: { anchor: 25, head: 25 }
    })
    expect(codemirrorController.scrollToPosition).toHaveBeenCalledWith(25)
    expect(previewController.renderContent).toHaveBeenCalledWith("# Example\n\nBody")
    expect(controller.updateStats).toHaveBeenCalledTimes(1)
  })

  it("disables typewriter before opening preview", () => {
    typewriterController.enabledValue = true

    controller.togglePreview()

    expect(typewriterController.toggle).toHaveBeenCalledTimes(1)
    expect(typewriterController.enabledValue).toBe(false)
    expect(previewController.toggle).toHaveBeenCalledTimes(1)
    expect(previewController.isVisible).toBe(true)
  })

  it("disables typewriter before entering reading mode", () => {
    typewriterController.enabledValue = true
    controller.editorPanelTarget = {
      classList: {
        add: vi.fn(),
        remove: vi.fn()
      }
    }
    controller.hasPreviewTitleTarget = false
    controller.hasPreviewPanelTarget = false
    controller.hasPreviewContentTarget = false
    controller.hasEditorTarget = false
    controller.hasEditorPanelTarget = true

    controller.toggleReadingMode()

    expect(typewriterController.toggle).toHaveBeenCalledTimes(1)
    expect(typewriterController.enabledValue).toBe(false)
    expect(controller.readingModeActive).toBe(true)
    expect(previewController.show).toHaveBeenCalledTimes(1)
    expect(previewController.isVisible).toBe(true)
  })

  it("updates the outline from the current markdown document and syncs the active line", () => {
    controller.refreshOutline()

    expect(outlineController.update).toHaveBeenCalledWith({
      visible: true,
      items: buildDocumentOutline("# Example\n\nBody")
    })
    expect(outlineController.setActiveLine).toHaveBeenCalledWith(4)
  })

  it("hides the outline for non-markdown files", () => {
    controller.currentFile = ".fed"
    controller.currentFileType = "config"

    controller.refreshOutline()

    expect(outlineController.hide).toHaveBeenCalledTimes(1)
    expect(outlineController.update).not.toHaveBeenCalled()
  })

  it("tracks preview scroll source lines for outline highlighting", () => {
    controller.onPreviewScrolled({ detail: { sourceLine: 9 } })

    expect(outlineController.setActiveLine).toHaveBeenCalledWith(9)
  })

  it("jumps to the selected outline line and syncs preview when visible", () => {
    controller.jumpToLine = vi.fn()
    previewController.isVisible = true

    controller.onOutlineSelected({ detail: { lineNumber: 11 } })

    expect(controller.jumpToLine).toHaveBeenCalledWith(11)
    expect(previewController.syncToLineSmooth).toHaveBeenCalledWith(4, 20)
    expect(outlineController.setActiveLine).toHaveBeenCalledWith(11)
  })

  it("recomputes outline and restores persisted UI state after codemirror is ready", () => {
    const restoreSpy = vi.spyOn(controller, "restorePersistedUiState").mockImplementation(() => {})

    controller._codemirrorReady = false
    controller.onCodeMirrorReady()

    expect(controller._codemirrorReady).toBe(true)
    expect(restoreSpy).toHaveBeenCalled()
  })

  it("restores persisted preview mode and width after the editor is ready", () => {
    configController.persistedActiveMode = "preview"

    controller.restorePersistedUiState()

    expect(splitPaneController.applyWidth).toHaveBeenCalledWith(55)
    expect(previewController.show).toHaveBeenCalledTimes(1)
    expect(typewriterController.toggle).not.toHaveBeenCalled()
  })

  it("restores persisted reading mode without saving during the restore path", () => {
    configController.persistedActiveMode = "reading"
    controller.editorPanelTarget = { classList: { add: vi.fn(), remove: vi.fn() } }
    controller.previewTitleTarget = { textContent: "Preview" }
    controller.previewPanelTarget = { classList: { add: vi.fn(), remove: vi.fn() } }
    controller.previewContentTarget = { classList: { add: vi.fn(), remove: vi.fn() } }
    controller.hasPreviewTitleTarget = true
    controller.hasPreviewPanelTarget = true
    controller.hasPreviewContentTarget = true
    controller.hasEditorTarget = false
    controller.hasEditorPanelTarget = true

    controller.restorePersistedUiState()

    expect(controller.readingModeActive).toBe(true)
    expect(previewController.show).toHaveBeenCalledTimes(1)
    expect(controller.saveConfig).not.toHaveBeenCalled()
  })

  it("persists the canonical active mode and legacy typewriter flag together", () => {
    previewController.isVisible = true

    controller.persistCurrentMode()

    expect(configController.activeModeValue).toBe("preview")
    expect(configController.typewriterModeValue).toBe(false)
    expect(controller.saveConfig).toHaveBeenCalledWith({
      active_mode: "preview",
      typewriter_mode: false
    })
  })

  it("saves preview width changes through config", () => {
    controller.onPreviewWidthChanged({ detail: { width: 54.6 } })

    expect(configController.previewWidthValue).toBe(55)
    expect(controller.saveConfig).toHaveBeenCalledWith({ preview_width: 55 })
  })

  it("syncs current share availability into the export menu", () => {
    controller.setCurrentShare({
      token: "abc123",
      url: "http://localhost:7591/s/abc123"
    })

    expect(exportMenuController.setShareState).toHaveBeenLastCalledWith({
      shareable: true,
      active: true,
      url: "http://localhost:7591/s/abc123"
    })

    controller.clearCurrentShare()

    expect(exportMenuController.setShareState).toHaveBeenLastCalledWith({
      shareable: true,
      active: false,
      url: null
    })
  })

  it("collects a preview-derived rendered payload and restores temporary visibility", async () => {
    const scrollSyncController = { updatePreview: vi.fn() }

    controller.getScrollSyncController = vi.fn(() => scrollSyncController)
    controller.waitForDomPaint = vi.fn(() => Promise.resolve())
    document.documentElement.setAttribute("data-theme", "solarized-dark")

    const payload = await controller.collectRenderedDocumentPayload()

    expect(previewController.show).toHaveBeenCalledTimes(1)
    expect(scrollSyncController.updatePreview).toHaveBeenCalledTimes(1)
    expect(previewController.getRenderedDocumentPayload).toHaveBeenCalledWith({
      title: "test",
      path: "notes/test.md",
      themeId: "solarized-dark"
    })
    expect(previewController.hide).toHaveBeenCalledTimes(1)
    expect(payload).toMatchObject({
      title: "test",
      path: "notes/test.md",
      themeId: "solarized-dark",
      html: "<h1>Example</h1>",
      plainText: "Example"
    })
  })

  it("can inline local export images into the collected payload when requested", async () => {
    controller.getScrollSyncController = vi.fn(() => null)
    controller.waitForDomPaint = vi.fn(() => Promise.resolve())
    controller.inlineExportPayloadImages = vi.fn(async (payload) => ({
      ...payload,
      html: '<h1>Example</h1><img src="data:image/png;base64,abc">'
    }))

    const payload = await controller.collectRenderedDocumentPayload({ embedLocalImages: true })

    expect(controller.inlineExportPayloadImages).toHaveBeenCalledWith(expect.objectContaining({
      html: "<h1>Example</h1>"
    }))
    expect(payload.html).toContain('src="data:image/png;base64,abc"')
    expect(previewController.hide).toHaveBeenCalledTimes(1)
  })

  it("does not restore visibility when preview was already visible", async () => {
    previewController.isVisible = true
    controller.waitForDomPaint = vi.fn(() => Promise.resolve())
    controller.getScrollSyncController = vi.fn(() => null)

    await controller.collectRenderedDocumentPayload()

    expect(previewController.show).not.toHaveBeenCalled()
    expect(previewController.render).toHaveBeenCalledWith("# Example\n\nBody", {
      currentNotePath: "notes/test.md"
    })
    expect(previewController.hide).not.toHaveBeenCalled()
  })

  it("skips persistence when preview toggles are only for transient payload preparation", () => {
    controller._transientPreviewPreparation = true
    controller.persistCurrentMode = vi.fn()
    controller.emitUiStateChanged = vi.fn()

    controller.onPreviewToggled({ detail: { visible: true } })

    expect(controller.persistCurrentMode).not.toHaveBeenCalled()
    expect(controller.emitUiStateChanged).not.toHaveBeenCalled()
  })

  it("returns no rendered payload for non-markdown files", async () => {
    controller.currentFile = ".fed"
    controller.currentFileType = "config"

    await expect(controller.collectRenderedDocumentPayload()).resolves.toBeNull()
  })

  it("shows a temporary message when copyFormattedHtml succeeds without a button", async () => {
    const clipboardWrite = vi.fn().mockResolvedValue(undefined)

    controller.collectRenderedDocumentPayload = vi.fn().mockResolvedValue({
      html: "<h1>Example</h1>",
      plainText: "Example"
    })
    global.ClipboardItem = class ClipboardItem {
      constructor(data) {
        this.data = data
      }
    }
    navigator.clipboard = { write: clipboardWrite }
    window.t = vi.fn((key) => ({
      "status.copied_to_clipboard": "Content copied to clipboard"
    }[key] || key))
    controller.showTemporaryMessage = vi.fn()

    await expect(controller.copyFormattedHtml()).resolves.toBe(true)

    expect(clipboardWrite).toHaveBeenCalledTimes(1)
    expect(controller.showTemporaryMessage).toHaveBeenCalledWith("Content copied to clipboard")
  })

  it("routes copy-html menu selections to copyFormattedHtml", async () => {
    controller.copyFormattedHtml = vi.fn().mockResolvedValue(true)

    await controller.onExportMenuSelected({ detail: { actionId: "copy-html" } })

    expect(controller.copyFormattedHtml).toHaveBeenCalledWith()
  })

  it("routes copy-markdown menu selections to copyMarkdown", async () => {
    controller.copyMarkdown = vi.fn().mockResolvedValue(true)

    await controller.onExportMenuSelected({ detail: { actionId: "copy-markdown" } })

    expect(controller.copyMarkdown).toHaveBeenCalledTimes(1)
  })

  it("routes print-pdf menu selections to printNote", async () => {
    controller.printNote = vi.fn().mockResolvedValue(undefined)

    await controller.onExportMenuSelected({ detail: { actionId: "print-pdf" } })

    expect(controller.printNote).toHaveBeenCalledTimes(1)
  })

  it("routes export-html menu selections to exportHtmlDocument", async () => {
    controller.exportHtmlDocument = vi.fn().mockResolvedValue(true)

    await controller.onExportMenuSelected({ detail: { actionId: "export-html" } })

    expect(controller.exportHtmlDocument).toHaveBeenCalledTimes(1)
  })

  it("routes export-txt menu selections to exportTextDocument", async () => {
    controller.exportTextDocument = vi.fn().mockResolvedValue(true)

    await controller.onExportMenuSelected({ detail: { actionId: "export-txt" } })

    expect(controller.exportTextDocument).toHaveBeenCalledTimes(1)
  })

  it("exports standalone HTML using the rendered preview payload", async () => {
    controller.collectRenderedDocumentPayload = vi.fn().mockResolvedValue({
      title: "Example",
      path: "notes/example.md",
      html: "<h1>Example</h1>",
      plainText: "Example"
    })
    controller.buildStandaloneExportDocument = vi.fn(() => "<!DOCTYPE html><html><body><h1>Example</h1></body></html>")
    controller.downloadExportFile = vi.fn(() => true)

    await expect(controller.exportHtmlDocument()).resolves.toBe(true)

    expect(controller.buildStandaloneExportDocument).toHaveBeenCalledWith(expect.objectContaining({
      path: "notes/example.md"
    }))
    expect(controller.downloadExportFile).toHaveBeenCalledWith(
      "example.html",
      "<!DOCTYPE html><html><body><h1>Example</h1></body></html>",
      "text/html;charset=utf-8"
    )
  })

  it("copies the current markdown source through the shared text clipboard helper", async () => {
    controller.copyTextToClipboard = vi.fn().mockResolvedValue(true)
    codemirrorController.getValue = vi.fn(() => "# Example\r\n\r\nBody")
    window.t = vi.fn((key) => key)

    await expect(controller.copyMarkdown()).resolves.toBe(true)

    expect(controller.copyTextToClipboard).toHaveBeenCalledWith("# Example\n\nBody", {
      successMessage: "status.copied_to_clipboard",
      failureMessage: "status.copy_failed"
    })
  })

  it("exports plain text using the rendered preview payload", async () => {
    controller.collectRenderedDocumentPayload = vi.fn().mockResolvedValue({
      title: "Example",
      path: "notes/example.md",
      html: "<h1>Example</h1>",
      plainText: "Line 1\r\nLine 2"
    })
    controller.downloadExportFile = vi.fn(() => true)

    await expect(controller.exportTextDocument()).resolves.toBe(true)

    expect(controller.downloadExportFile).toHaveBeenCalledWith(
      "example.txt",
      "Line 1\nLine 2\n",
      "text/plain;charset=utf-8"
    )
  })

  it("prints a standalone export document for PDF output", async () => {
    controller.collectRenderedDocumentPayload = vi.fn().mockResolvedValue({
      title: "Example",
      path: "notes/example.md",
      html: "<h1>Example</h1>",
      plainText: "Example"
    })
    controller.buildStandaloneExportDocument = vi.fn(() => "<!DOCTYPE html><html><body><h1>Example</h1></body></html>")
    controller.printStandaloneDocument = vi.fn(() => true)

    await expect(controller.printNote()).resolves.toBe(true)

    expect(controller.buildStandaloneExportDocument).toHaveBeenCalled()
    expect(controller.printStandaloneDocument).toHaveBeenCalledWith(
      "<!DOCTYPE html><html><body><h1>Example</h1></body></html>"
    )
  })

  it("creates a populated PDF blob and appends the print iframe", async () => {
    const originalCreateElement = document.createElement.bind(document)
    const originalAppendChild = document.body.appendChild.bind(document.body)
    const originalCreateObjectUrl = URL.createObjectURL
    const originalRevokeObjectUrl = URL.revokeObjectURL
    const OriginalBlob = Blob
    const listeners = {}
    const capturedBlobParts = []
    const capturedBlobTypes = []

    const iframe = {
      style: {},
      setAttribute: vi.fn(),
      remove: vi.fn(),
      contentWindow: {
        document: {
          images: [],
          fonts: { ready: Promise.resolve() }
        },
        focus: vi.fn(),
        print: vi.fn(),
        addEventListener: vi.fn((eventName, callback) => {
          listeners[eventName] = callback
        }),
        requestAnimationFrame: vi.fn((callback) => callback()),
        removeEventListener: vi.fn()
      },
      onload: null,
      src: ""
    }

    document.createElement = vi.fn((tagName) => {
      if (tagName === "iframe") return iframe
      return originalCreateElement(tagName)
    })

    document.body.appendChild = vi.fn((node) => {
      expect(node).toBe(iframe)
      expect(node.src).toBe("blob:frankmd-pdf")
      if (typeof node.onload === "function") node.onload()
      return node
    })

    URL.createObjectURL = vi.fn(() => "blob:frankmd-pdf")
    URL.revokeObjectURL = vi.fn()
    globalThis.Blob = class BlobCapture extends OriginalBlob {
      constructor(parts, options = {}) {
        capturedBlobParts.push(parts)
        capturedBlobTypes.push(options.type)
        super(parts, options)
      }
    }

    try {
      expect(controller.printStandaloneDocument("<!DOCTYPE html><html><body><h1>Example</h1></body></html>")).toBe(true)
      await Promise.resolve()
      await Promise.resolve()
      await Promise.resolve()

      expect(URL.createObjectURL).toHaveBeenCalledTimes(1)
      expect(capturedBlobTypes[0]).toBe("text/html;charset=utf-8")
      expect(String(capturedBlobParts[0][0])).toContain("<h1>Example</h1>")
      expect(document.body.appendChild).toHaveBeenCalledTimes(1)
      expect(iframe.src).toBe("blob:frankmd-pdf")
    } finally {
      document.createElement = originalCreateElement
      document.body.appendChild = originalAppendChild
      URL.createObjectURL = originalCreateObjectUrl
      URL.revokeObjectURL = originalRevokeObjectUrl
      globalThis.Blob = OriginalBlob
    }
  })

  it("routes create-share-link menu selections to createShareLink", async () => {
    controller.createShareLink = vi.fn().mockResolvedValue(true)
    await controller.onExportMenuSelected({ detail: { actionId: "create-share-link" } })
    expect(controller.createShareLink).toHaveBeenCalledTimes(1)
  })

  it("routes copy-share-link menu selections to copyShareLink", async () => {
    controller.copyShareLink = vi.fn().mockResolvedValue(true)
    await controller.onExportMenuSelected({ detail: { actionId: "copy-share-link" } })
    expect(controller.copyShareLink).toHaveBeenCalledTimes(1)
  })

  it("routes refresh-share-link menu selections to refreshShareLink", async () => {
    controller.refreshShareLink = vi.fn().mockResolvedValue(true)
    await controller.onExportMenuSelected({ detail: { actionId: "refresh-share-link" } })
    expect(controller.refreshShareLink).toHaveBeenCalledTimes(1)
  })

  it("routes disable-share-link menu selections to disableShareLink", async () => {
    controller.disableShareLink = vi.fn().mockResolvedValue(true)
    await controller.onExportMenuSelected({ detail: { actionId: "disable-share-link" } })
    expect(controller.disableShareLink).toHaveBeenCalledTimes(1)
  })

  it("delegates saving the current markdown note as a template to file operations", async () => {
    const fileOperationsController = {
      openSaveTemplateFromNoteDialog: vi.fn().mockResolvedValue(true)
    }

    controller.getFileOperationsController = vi.fn(() => fileOperationsController)

    await controller.saveCurrentNoteAsTemplate()

    expect(fileOperationsController.openSaveTemplateFromNoteDialog).toHaveBeenCalledWith("notes/test.md")
  })

  it("forwards file operation status messages into temporary feedback", () => {
    controller.showTemporaryMessage = vi.fn()

    controller.onFileOperationsStatusMessage({
      detail: {
        message: "Backup download started",
        duration: 3200,
        error: true
      }
    })

    expect(controller.showTemporaryMessage).toHaveBeenCalledWith("Backup download started", 3200, true)
  })

  it("alerts when attempting to save a non-markdown file as a template", async () => {
    controller.currentFile = ".fed"
    controller.currentFileType = "config"
    global.alert = vi.fn()
    window.t = vi.fn((key) => key)
    controller.getFileOperationsController = vi.fn(() => ({
      openSaveTemplateFromNoteDialog: vi.fn()
    }))

    await controller.saveCurrentNoteAsTemplate()

    expect(global.alert).toHaveBeenCalledWith("errors.templates_markdown_only")
  })
})
