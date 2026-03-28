import { Controller } from "@hotwired/stimulus"
import { destroy, get, patch, post } from "@rails/request.js"
import { marked } from "marked"
import { escapeHtml, normalizeLineEndings } from "lib/text_utils"
import { findTableAtPosition, findCodeBlockAtPosition } from "lib/markdown_utils"
import { allExtensions } from "lib/marked_extensions"
import { encodePath } from "lib/url_utils"
import {
  DEFAULT_SHORTCUTS,
  createKeyHandler,
  mergeShortcuts
} from "lib/keyboard_shortcuts"
import { createTextareaAdapter } from "lib/codemirror_adapter"
import {
  insertBlockContent,
  insertInlineContent,
  insertImage,
  insertCodeBlock,
  insertVideoEmbed
} from "lib/codemirror_content_insertion"
import { buildDocumentOutline } from "lib/document_outline"
import {
  buildExportFilename,
  buildPlainTextExport,
  buildStandaloneExportDocument as buildStandaloneExportHtmlDocument,
  captureExportThemeSnapshot
} from "lib/export_document_builder"
import { inlineSameOriginImages } from "lib/export_image_embedder"
import {
  downloadExportFile as downloadBrowserExportFile,
  printStandaloneDocument as printBrowserExportDocument,
  waitForDocumentImages as waitForBrowserDocumentImages,
  waitForExportDocumentAssets as waitForBrowserExportAssets
} from "lib/browser_export_utils"
export default class extends Controller {
  static targets = [
    "fileTree",
    "editorPlaceholder",
    "editor",
    "textarea",
    "currentPath",
    "contextMenu",
    "editorToolbar",
    "helpDialog",
    "tableHint",
    "sidebar",
    "sidebarToggle",
    "aiButton",
    "editorWrapper",
    "editorBody",
    "editorPanel",
    "previewPanel",
    "previewContent",
    "previewTitle"
  ]

  static outlets = [
    "codemirror", "preview", "typewriter", "stats-panel",
    "split-pane",
    "path-display", "text-format", "help", "file-operations",
    "emoji-picker", "offline-backup", "recovery-diff",
    "autosave", "scroll-sync", "editor-config",
    "image-picker", "file-finder", "find-replace", "jump-to-line",
    "outline", "export-menu",
    "content-search", "video-dialog", "log-viewer",
    "code-dialog", "customize", "share-management", "drag-drop"
  ]

  static values = {
    initialPath: String,
    initialNote: Object
  }

  connect() {
    this.currentFile = null
    this.currentFileType = null  // "markdown", "config", or null
    this.expandedFolders = new Set()
    this.lastOpenMarkdownNotePath = null
    this.readingModeActive = false
    this.recoveryAvailable = false
    this._lastUiStateSignature = null
    this._lastExplorerResumeStateSignature = null
    this._codemirrorReady = false
    this._restoringPersistedUiState = false
    this._transientPreviewPreparation = false
    this.currentShare = null
    this._shareStateRequestId = 0

    // Sidebar/Explorer visibility - always start visible
    // (don't persist closed state across sessions)
    this.sidebarVisible = true

    // Track pending config saves to debounce
    this.configSaveTimeout = null
    this.pendingConfigSettings = {}

    // Debounce timers for performance
    this._tableCheckTimeout = null
    this._outlineRefreshTimeout = null

    this.setupKeyboardShortcuts()
    this.setupDialogClickOutside()
    this.applySidebarVisibility()
    this.setupConfigFileListener()
    this.setupTableEditorListener()
    this.setupRecoveryStateListeners()

    // Configure marked with custom extensions for superscript, subscript, highlight, emoji
    marked.use({
      breaks: true,
      gfm: true,
      extensions: allExtensions
    })

    // Setup browser history handling for back/forward buttons
    this.setupHistoryHandling()

    // Pre-set codemirror's content attribute so it creates the editor with the right content
    // (before the codemirror controller connects and reads its contentValue)
    this._preloadInitialContent()

    // Defer full initialization until codemirror outlet connects.
    // Fallback timeout ensures it runs even if outlet callback doesn't fire.
    this._initialFileHandled = false
    this._initialFileTimeout = setTimeout(() => this._completeInitialLoad(), 50)
  }

  // Called by Stimulus when the codemirror outlet controller connects
  codemirrorOutletConnected() {
    this._completeInitialLoad()
  }

  _preloadInitialContent() {
    if (!this.hasInitialNoteValue) return

    const initialNote = this.initialNoteValue
    if (!initialNote || !initialNote.exists || initialNote.content === null) return

    const cmElement = this.element.querySelector('[data-controller~="codemirror"]')
    if (cmElement) {
      cmElement.setAttribute("data-codemirror-content-value", initialNote.content)
    }
  }

  _completeInitialLoad() {
    if (this._initialFileHandled) return
    this._initialFileHandled = true
    if (this._initialFileTimeout) {
      clearTimeout(this._initialFileTimeout)
      this._initialFileTimeout = null
    }
    this.hydrateExpandedFoldersFromTree()
    this.handleInitialFile()
    this.captureExplorerResumeStateSignature()
    this._removeSplashScreen()
  }

  _removeSplashScreen() {
    const loadingScreen = document.getElementById("app-loading")
    if (loadingScreen) {
      loadingScreen.style.opacity = "0"
      loadingScreen.style.transition = "opacity 0.2s ease-out"
      setTimeout(() => loadingScreen.remove(), 200)
    }
  }

  disconnect() {
    // Clear all timeouts
    if (this.configSaveTimeout) clearTimeout(this.configSaveTimeout)
    if (this._tableCheckTimeout) clearTimeout(this._tableCheckTimeout)
    if (this._outlineRefreshTimeout) clearTimeout(this._outlineRefreshTimeout)
    if (this._initialFileTimeout) clearTimeout(this._initialFileTimeout)

    // Remove window/document event listeners
    if (this.boundPopstateHandler) {
      window.removeEventListener("popstate", this.boundPopstateHandler)
    }
    if (this.boundTableInsertHandler) {
      window.removeEventListener("frankmd:insert-table", this.boundTableInsertHandler)
    }
    if (this.boundConfigFileHandler) {
      window.removeEventListener("frankmd:config-file-modified", this.boundConfigFileHandler)
    }
    if (this.boundKeydownHandler) {
      document.removeEventListener("keydown", this.boundKeydownHandler)
    }
    if (this.boundRecoveryOpenedHandler) {
      this.element.removeEventListener("recovery-diff:opened", this.boundRecoveryOpenedHandler)
    }
    if (this.boundRecoveryResolvedHandler) {
      this.element.removeEventListener("recovery-diff:resolved", this.boundRecoveryResolvedHandler)
    }

    // Clean up object URLs to prevent memory leaks
    this.cleanupLocalFolderImages()

    // Abort any pending AI requests
    if (this.aiImageAbortController) {
      this.aiImageAbortController.abort()
    }
  }

  // === Controller Getters (via Stimulus Outlets) ===

  // Outlet getters use the plural form (*Outlets) which returns only connected controllers
  // as an array (never throws). Returns null when the outlet controller isn't connected yet.
  getPreviewController() { return this.previewOutlets[0] ?? null }
  getTypewriterController() { return this.typewriterOutlets[0] ?? null }
  getCodemirrorController() { return this.codemirrorOutlets[0] ?? null }
  getSplitPaneController() { return this.splitPaneOutlets[0] ?? null }
  getPathDisplayController() { return this.pathDisplayOutlets[0] ?? null }
  getTextFormatController() { return this.textFormatOutlets[0] ?? null }
  getHelpController() { return this.helpOutlets[0] ?? null }
  getStatsPanelController() { return this.statsPanelOutlets[0] ?? null }
  getFileOperationsController() { return this.fileOperationsOutlets[0] ?? null }
  getEmojiPickerController() { return this.emojiPickerOutlets[0] ?? null }
  getOfflineBackupController() { return this.offlineBackupOutlets[0] ?? null }
  getRecoveryDiffController() { return this.recoveryDiffOutlets[0] ?? null }
  getAutosaveController() { return this.autosaveOutlets[0] ?? null }
  getScrollSyncController() { return this.scrollSyncOutlets[0] ?? null }
  getEditorConfigController() { return this.editorConfigOutlets[0] ?? null }
  getOutlineController() { return this.outlineOutlets[0] ?? null }
  getExportMenuController() { return this.exportMenuOutlets?.[0] ?? null }
  getShareManagementController() { return this.shareManagementOutlets?.[0] ?? null }

  outlineOutletConnected() {
    this.refreshOutline()
  }

  exportMenuOutletConnected() {
    this.updateExportMenuShareState()
  }

  splitPaneOutletConnected() {
    this.applyPersistedPreviewWidth()
  }

  // === Shared UI State Snapshot ===

  getModeState() {
    const previewController = this.getPreviewController()
    const typewriterController = this.getTypewriterController()
    const previewVisible = previewController
      ? previewController.isVisible
      : (this.hasPreviewPanelTarget && !this.previewPanelTarget.classList.contains("hidden"))
    const readingActive = Boolean(this.readingModeActive)
    const typewriterActive = Boolean(typewriterController?.enabledValue)

    let mode = "raw"
    if (this.isMarkdownFile() && this.currentFile) {
      if (readingActive) {
        mode = "reading"
      } else if (typewriterActive) {
        mode = "typewriter"
      } else if (previewVisible) {
        mode = "preview"
      }
    }

    return {
      mode,
      previewVisible,
      readingActive,
      typewriterActive
    }
  }

  getDocumentContext() {
    const codemirrorController = this.getCodemirrorController()
    const configCtrl = this.getEditorConfigController()
    const previewController = this.getPreviewController()
    const cursorInfo = codemirrorController?.getCursorInfo() || {}
    const cursorPosition = codemirrorController?.getCursorPosition?.() || {}
    const selection = codemirrorController?.getSelection?.() || {}
    const selectionLength = Math.max(0, (selection.to ?? 0) - (selection.from ?? 0))

    return {
      path: this.currentFile || null,
      fileType: this.currentFileType || null,
      isMarkdown: this.isMarkdownFile(),
      previewZoom: previewController?.zoomValue ?? configCtrl?.previewZoom ?? null,
      cursorLine: cursorInfo.currentLine ?? null,
      totalLines: cursorInfo.totalLines ?? null,
      column: cursorPosition.column ?? null,
      selectionLength,
      hasSelection: selectionLength > 0
    }
  }

  buildUiStateSnapshot() {
    return {
      ...this.getDocumentContext(),
      ...this.getModeState(),
      recoveryAvailable: Boolean(this.recoveryAvailable),
      shareable: Boolean(this.currentFile && this.isMarkdownFile()),
      shareActive: Boolean(this.currentShare?.url),
      shareStale: Boolean(this.currentShare?.stale),
      shareUrl: this.currentShare?.url || null
    }
  }

  emitUiStateChanged(reason) {
    const state = this.buildUiStateSnapshot()
    const signature = JSON.stringify(state)

    if (signature === this._lastUiStateSignature) return

    this._lastUiStateSignature = signature
    this.dispatch("state-changed", {
      detail: { reason, state }
    })
  }

  // === URL Management for Bookmarkable URLs ===

  handleInitialFile() {
    // Check if server provided initial note data (from URL like /notes/path/to/file.md)
    const initialNote = this.hasInitialNoteValue ? this.initialNoteValue : null
    if (initialNote && Object.keys(initialNote).length > 0) {
      const { path, content, exists, error } = initialNote

      if (exists && content !== null) {
        // File exists - load it directly from server-provided data
        this.currentFile = path
        const fileType = this.getFileType(path)
        const displayPath = fileType === "markdown" ? path.replace(/\.md$/, "") : path
        this.updatePathDisplay(displayPath)
        this.expandParentFolders(path)
        this.showEditor(content, fileType)
        this.rememberCurrentMarkdownNote({ persist: false })
        this.syncTreeSelection(path)
        return
      }

      if (!exists) {
        // File was requested but doesn't exist
        if (this.clearRememberedLastOpenNote(path)) {
          this.persistExplorerResumeState()
        }
        this.showFileNotFoundMessage(path, error || window.t("errors.file_not_found"))
        // Update URL to root without adding history entry
        this.updateUrl(null, { replace: true })
        return
      }
    }

    // Fallback: Check URL path directly (shouldn't normally happen if server is handling it)
    const urlPath = this.getFilePathFromUrl()
    if (urlPath) {
      this.loadFile(urlPath)
    }
  }

  getFilePathFromUrl() {
    const path = window.location.pathname
    const match = path.match(/^\/notes\/(.+\.md)$/)
    if (match) {
      return decodeURIComponent(match[1])
    }

    // Also check query param ?file=
    const params = new URLSearchParams(window.location.search)
    return params.get("file")
  }

  updateUrl(path, options = {}) {
    const { replace = false } = options
    const newUrl = path ? `/notes/${encodePath(path)}` : "/"

    if (window.location.pathname !== newUrl) {
      if (replace) {
        window.history.replaceState({ file: path }, "", newUrl)
      } else {
        window.history.pushState({ file: path }, "", newUrl)
      }
    }
  }

  setupHistoryHandling() {
    this.boundPopstateHandler = async (event) => {
      const path = event.state?.file || this.getFilePathFromUrl()

      if (path) {
        await this.loadFile(path, { updateHistory: false })
      } else {
        this.showEditorPlaceholder("file-cleared")
      }
    }
    window.addEventListener("popstate", this.boundPopstateHandler)
  }

  expandParentFolders(path) {
    const parts = path.split("/")
    let expandPath = ""

    for (let i = 0; i < parts.length - 1; i++) {
      expandPath = expandPath ? `${expandPath}/${parts[i]}` : parts[i]
      this.expandedFolders.add(expandPath)
    }
  }

  parentFolderPaths(path) {
    if (!path) return []

    const parts = String(path).split("/")
    const folders = []
    let currentPath = ""

    for (let i = 0; i < parts.length - 1; i++) {
      currentPath = currentPath ? `${currentPath}/${parts[i]}` : parts[i]
      folders.push(currentPath)
    }

    return folders
  }

  findTreeFileElement(path) {
    if (!this.fileTreeTarget || !path) return null

    return Array.from(this.fileTreeTarget.querySelectorAll('[data-type="file"]'))
      .find((element) => element.dataset.path === path) || null
  }

  clearTreeSelection() {
    if (!this.fileTreeTarget) return

    this.fileTreeTarget.querySelectorAll('[data-type="file"].selected').forEach((element) => {
      element.classList.remove("selected")
    })
  }

  setFolderExpandedInTree(path, expanded) {
    if (!this.fileTreeTarget || !path) return false

    const folderElement = Array.from(this.fileTreeTarget.querySelectorAll(".tree-folder"))
      .find((element) => element.dataset.path === path)
    if (!folderElement) return false

    const children = folderElement.querySelector(".tree-children")
    const chevron = folderElement.querySelector(".tree-chevron")

    if (children) {
      children.classList.toggle("hidden", !expanded)
    }

    if (chevron) {
      chevron.classList.toggle("expanded", expanded)
    }

    return true
  }

  syncTreeSelection(path = this.currentFile) {
    this.clearTreeSelection()
    if (!path) return false

    this.expandParentFolders(path)
    this.parentFolderPaths(path).forEach((folderPath) => {
      this.setFolderExpandedInTree(folderPath, true)
    })

    const fileElement = this.findTreeFileElement(path)
    if (!fileElement) return false

    fileElement.classList.add("selected")
    return true
  }

  hydrateExpandedFoldersFromTree() {
    if (!this.fileTreeTarget) return

    const expandedFolders = Array.from(this.fileTreeTarget.querySelectorAll(".tree-folder"))
      .filter((folderEl) => {
        const children = folderEl.querySelector(".tree-children")
        return children && !children.classList.contains("hidden")
      })
      .map((folderEl) => folderEl.dataset.path)
      .filter(Boolean)

    this.expandedFolders = new Set(expandedFolders)
  }

  serializeExpandedFoldersForConfig() {
    return this.sortedExpandedFolders()
      .map((path) => encodeURIComponent(path))
      .join(",")
  }

  sortedExpandedFolders() {
    return Array.from(this.expandedFolders).sort((left, right) => left.localeCompare(right))
  }

  serializeExpandedFoldersForRequest() {
    return JSON.stringify(this.sortedExpandedFolders())
  }

  currentExplorerResumeState() {
    return {
      last_open_note: this.lastOpenMarkdownNotePath || "",
      explorer_expanded_folders: this.serializeExpandedFoldersForConfig()
    }
  }

  captureExplorerResumeStateSignature() {
    this._lastExplorerResumeStateSignature = JSON.stringify(this.currentExplorerResumeState())
  }

  persistExplorerResumeState() {
    const nextState = this.currentExplorerResumeState()
    const nextSignature = JSON.stringify(nextState)
    if (nextSignature === this._lastExplorerResumeStateSignature) return

    this._lastExplorerResumeStateSignature = nextSignature
    this.saveConfig(nextState)
  }

  rememberCurrentMarkdownNote({ persist = true } = {}) {
    if (!this.currentFile || !this.isMarkdownFile()) return

    this.lastOpenMarkdownNotePath = this.currentFile
    if (persist) {
      this.persistExplorerResumeState()
    }
  }

  clearRememberedLastOpenNote(path = null) {
    if (!this.lastOpenMarkdownNotePath) return false

    if (!path) {
      this.lastOpenMarkdownNotePath = null
      return true
    }

    const normalizedPath = String(path)
    const matchesRememberedNote =
      this.lastOpenMarkdownNotePath === normalizedPath ||
      this.lastOpenMarkdownNotePath.startsWith(`${normalizedPath}/`)

    if (!matchesRememberedNote) return false

    this.lastOpenMarkdownNotePath = null
    return true
  }

  remapRememberedLastOpenNote(oldPath, newPath) {
    if (!this.lastOpenMarkdownNotePath) return false

    if (this.lastOpenMarkdownNotePath === oldPath) {
      this.lastOpenMarkdownNotePath = newPath
      return true
    }

    if (this.lastOpenMarkdownNotePath.startsWith(`${oldPath}/`)) {
      this.lastOpenMarkdownNotePath = `${newPath}${this.lastOpenMarkdownNotePath.slice(oldPath.length)}`
      return true
    }

    return false
  }

  showFileNotFoundMessage(path, message) {
    this.currentFile = null
    this.currentFileType = null
    this.clearCurrentShare()
    this.refreshNoteLinkAutocompleteContext()
    this.editorPlaceholderTarget.classList.add("hidden")
    this.editorTarget.classList.remove("hidden")
    this.editorToolbarTarget.classList.add("hidden")
    this.editorToolbarTarget.classList.remove("flex")

    this.textareaTarget.value = ""
    this.textareaTarget.disabled = true

    this.currentPathTarget.innerHTML = `
      <span class="text-red-500">${escapeHtml(path)}</span>
      <span class="text-[var(--theme-text-muted)] ml-2">(${escapeHtml(message)})</span>
    `

    // Clear after a moment and return to normal state
    setTimeout(() => {
      this.textareaTarget.disabled = false
      this.showEditorPlaceholder("file-cleared")
    }, 5000)
  }

  showEditorPlaceholder(reason = "file-cleared") {
    this.currentFile = null
    this.currentFileType = null
    this.clearCurrentShare()
    this.clearTreeSelection()
    this.getPreviewController()?.setCurrentNotePath?.(null)
    this.refreshNoteLinkAutocompleteContext()
    this.updatePathDisplay(null)
    this.editorPlaceholderTarget.classList.remove("hidden")
    this.editorTarget.classList.add("hidden")
    this.editorToolbarTarget.classList.add("hidden")
    this.editorToolbarTarget.classList.remove("flex")
    this.hideStatsPanel()
    if (this._codemirrorReady) {
      this.restorePersistedUiState()
    } else {
      this.refreshOutline()
    }
    this.emitUiStateChanged(reason)
  }

  toggleFolder(event) {
    const path = event.currentTarget.dataset.path
    const folderEl = event.currentTarget.closest(".tree-folder")
    const children = folderEl.querySelector(".tree-children")
    const chevron = event.currentTarget.querySelector(".tree-chevron")

    if (this.expandedFolders.has(path)) {
      this.expandedFolders.delete(path)
      children.classList.add("hidden")
      chevron.classList.remove("expanded")
    } else {
      this.expandedFolders.add(path)
      children.classList.remove("hidden")
      chevron.classList.add("expanded")
    }

    this.persistExplorerResumeState()
  }

  // === Drag and Drop Event Handler ===
  // Handle item moved event from drag-drop controller
  onItemMoved(event) {
    const { oldPath, newPath, type } = event.detail

    if (type === "folder") {
      // Preserve expand/collapse state for moved folder and its descendants
      this.expandedFolders = new Set(
        Array.from(this.expandedFolders, (path) => {
          if (path === oldPath || path.startsWith(oldPath + "/")) {
            return `${newPath}${path.slice(oldPath.length)}`
          }
          return path
        })
      )
    }

    // Expand the target folder
    const targetFolder = newPath.split("/").slice(0, -1).join("/")
    if (targetFolder) {
      this.expandedFolders.add(targetFolder)
    }

    // Update current file reference if it was moved
    if (type === "folder" && this.currentFile?.startsWith(oldPath + "/")) {
      this.currentFile = `${newPath}${this.currentFile.slice(oldPath.length)}`
      this.updatePathDisplay(this.currentFile.replace(/\.md$/, ""))
      this.updateUrl(this.currentFile)
    }

    if (this.currentFile === oldPath) {
      this.currentFile = newPath
      this.updatePathDisplay(newPath.replace(/\.md$/, ""))
      this.updateUrl(newPath)
    }

    this.remapRememberedLastOpenNote(oldPath, newPath)

    if (this.currentFile) {
      this.refreshCurrentShareState()
    }

    // Tree is already updated by Turbo Stream
    this.persistExplorerResumeState()
  }

  // === File Selection and Editor ===
  async selectFile(event) {
    const path = event.currentTarget.dataset.path
    await this.loadFile(path)
  }

  async loadFile(path, options = {}) {
    const { updateHistory = true } = options

    try {
      const response = await get(`/notes/${encodePath(path)}`, { responseKind: "json" })

      if (!response.ok) {
        if (response.statusCode === 404) {
          if (this.clearRememberedLastOpenNote(path)) {
            this.persistExplorerResumeState()
          }
          this.showFileNotFoundMessage(path, window.t("errors.note_not_found"))
          if (updateHistory) {
            this.updateUrl(null)
          }
          return
        }
        throw new Error(window.t("errors.failed_to_load"))
      }

      const data = await response.json
      this.currentFile = path
      const fileType = this.getFileType(path)

      // Display path (don't strip extension for non-markdown files)
      const displayPath = fileType === "markdown" ? path.replace(/\.md$/, "") : path
      this.updatePathDisplay(displayPath)

      // Expand parent folders in tree
      this.expandParentFolders(path)

      this.showEditor(data.content, fileType)
      this.rememberCurrentMarkdownNote()
      if (!this.syncTreeSelection(path)) {
        await this.refreshTree()
      }

      // Update URL for bookmarkability
      if (updateHistory) {
        this.updateUrl(path)
      }
    } catch (error) {
      console.error("Error loading file:", error)
      const autosave = this.getAutosaveController()
      if (autosave) autosave.showSaveStatus(window.t("status.error_loading"), true)
    }
  }

  showEditor(content, fileType = "markdown") {
    this.currentFileType = fileType
    this.clearCurrentShare()
    this.editorPlaceholderTarget.classList.add("hidden")
    this.editorTarget.classList.remove("hidden")

    // Reset table hint immediately when loading new content
    this._setTableHintVisible(false)
    if (this._tableCheckTimeout) {
      clearTimeout(this._tableCheckTimeout)
      this._tableCheckTimeout = null
    }

    // Delegate persistence tracking to autosave controller
    const autosave = this.getAutosaveController()
    if (autosave) {
      autosave.setFile(this.currentFile, content)
      autosave.checkOfflineBackup(content)
    }

    // Set content via CodeMirror controller
      const codemirrorController = this.getCodemirrorController()
      if (codemirrorController) {
        codemirrorController.setValue(content)
        this.refreshNoteLinkAutocompleteContext()
        codemirrorController.focus()
      } else {
        // Fallback to hidden textarea
        this.textareaTarget.value = content
      }

    // Only show toolbar and preview for markdown files
    const isMarkdown = fileType === "markdown"
    this.getPreviewController()?.setCurrentNotePath?.(isMarkdown ? this.currentFile : null)

    if (isMarkdown) {
      this.editorToolbarTarget.classList.remove("hidden")
      this.editorToolbarTarget.classList.add("flex")
      this.updatePreview()
    } else {
      this.editorToolbarTarget.classList.add("hidden")
      this.editorToolbarTarget.classList.remove("flex")
      // Hide preview for non-markdown files
      const previewController = this.getPreviewController()
      if (previewController && previewController.isVisible) {
        previewController.hide()
      }
    }

    this.refreshOutline()

    // Show stats panel and update stats
    this.showStatsPanel()
    this.updateStats()
    // Apply editor settings (font, size, line numbers)
    this.applyEditorSettings()
    this.refreshCurrentShareState()
    this.emitUiStateChanged("file-loaded")
  }

  refreshNoteLinkAutocompleteContext() {
    const codemirrorController = this.getCodemirrorController()
    if (!codemirrorController) return

    codemirrorController.setCurrentNotePath(this.isMarkdownFile() ? this.currentFile : null)
    const notes = this.fileTreeTarget
      ? this.getFilesFromTree().filter((file) => file.file_type === "markdown" || file.path.endsWith(".md"))
      : []
    codemirrorController.setAvailableNotes(notes)
  }

  setCurrentShare(share) {
    this.currentShare = share ? { ...share } : null
    this.updateExportMenuShareState()
    this.emitUiStateChanged("share-state-changed")
  }

  clearCurrentShare() {
    this.currentShare = null
    this.updateExportMenuShareState()
    this.emitUiStateChanged("share-state-changed")
  }

  updateExportMenuShareState() {
    const exportMenuController = this.getExportMenuController()
    if (!exportMenuController) return

    exportMenuController.setShareState({
      shareable: Boolean(this.currentFile && this.isMarkdownFile()),
      active: Boolean(this.currentShare?.url),
      url: this.currentShare?.url || null
    })
  }

  async refreshCurrentShareState() {
    if (!this.currentFile || !this.isMarkdownFile()) {
      this.clearCurrentShare()
      return null
    }

    const requestId = ++this._shareStateRequestId
    const path = this.currentFile

    this.clearCurrentShare()

    try {
      const response = await get(`/shares/${encodePath(path)}`, { responseKind: "json" })
      if (requestId !== this._shareStateRequestId || this.currentFile !== path) return null

      if (response.ok) {
        const share = await response.json
        this.setCurrentShare(share)
        return share
      }

      if (response.statusCode === 404) {
        return null
      }

      throw new Error(await response.text)
    } catch (error) {
      if (requestId === this._shareStateRequestId && this.currentFile === path) {
        console.warn("Failed to load share state:", error)
        this.clearCurrentShare()
      }
      return null
    }
  }

  // Check if current file is markdown
  isMarkdownFile() {
    return this.currentFileType === "markdown"
  }

  // Get file type from path
  getFileType(path) {
    if (!path) return null
    if (path === ".fed") return "config"
    if (path.endsWith(".md")) return "markdown"
    return "text"
  }

  onTextareaInput() {
    // Legacy method - CodeMirror now handles input via onEditorChange
    this.onEditorChange({ detail: { docChanged: true } })
  }

  // Handle CodeMirror editor change events
  onEditorChange(event) {
    const autosave = this.getAutosaveController()
    if (autosave) {
      const codemirrorController = this.getCodemirrorController()
      const currentContent = codemirrorController ? codemirrorController.getValue() : ""
      autosave.checkContentRestored(currentContent)
      autosave.scheduleOfflineBackup()
      autosave.scheduleAutoSave()
    }

    this.scheduleStatsUpdate()
    this.scheduleOutlineRefresh()

    // Only do markdown-specific processing for markdown files
    if (this.isMarkdownFile()) {
      // Delegate preview sync to scroll-sync controller
      const scrollSync = this.getScrollSyncController()
      if (scrollSync) {
        const previewController = this.getPreviewController()
        if (previewController && previewController.isVisible) {
          scrollSync.updatePreviewWithSync()
        }
      }

      this.checkTableAtCursor()

      // Typewriter scroll centering works regardless of preview
      const configCtrl = this.getEditorConfigController()
      if (configCtrl && configCtrl.typewriterModeEnabled) {
        this.maintainTypewriterScroll()
      }
    }

    this.emitUiStateChanged("document-changed")
  }

  // Handle CodeMirror selection change events
  onEditorSelectionChange(event) {
    this.updateLinePosition()

    // Show/hide table hint when cursor moves into/out of a table.
    // Skip if a doc change already scheduled a check in this event cycle
    // (typing fires both docChanged and selectionSet in the same CM update).
    if (this.isMarkdownFile() && !this._tableCheckTimeout) {
      this.checkTableAtCursor()
    }

    this.syncOutlineActiveLine()
    this.emitUiStateChanged("selection-changed")
  }

  scheduleOutlineRefresh() {
    if (this._outlineRefreshTimeout) {
      clearTimeout(this._outlineRefreshTimeout)
    }

    this._outlineRefreshTimeout = setTimeout(() => {
      this._outlineRefreshTimeout = null
      this.refreshOutline()
    }, 80)
  }

  refreshOutline() {
    const outlineController = this.getOutlineController()
    if (!outlineController) return

    if (!this.currentFile || !this.isMarkdownFile()) {
      outlineController.hide()
      return
    }

    outlineController.update({
      visible: true,
      items: buildDocumentOutline(this.getCurrentDocumentContent())
    })

    this.syncOutlineActiveLine()
  }

  syncOutlineActiveLine(lineNumber = null) {
    const outlineController = this.getOutlineController()
    if (!outlineController || !this.currentFile || !this.isMarkdownFile()) return

    const nextLine = Number.isInteger(lineNumber)
      ? lineNumber
      : this.getCursorInfo()?.currentLine

    outlineController.setActiveLine(nextLine ?? null)
  }

  onPreviewScrolled(event) {
    if (!this.isMarkdownFile()) return

    const sourceLine = event.detail?.sourceLine
    if (!Number.isInteger(sourceLine)) return

    this.syncOutlineActiveLine(sourceLine)
  }

  async onPreviewNoteLinkSelected(event) {
    const path = event.detail?.path
    if (!path) return

    await this.loadFile(path)
  }

  onOutlineSelected(event) {
    const lineNumber = event.detail?.lineNumber
    if (!Number.isInteger(lineNumber)) return

    this.jumpToLine(lineNumber)

    const previewController = this.getPreviewController()
    const codemirrorController = this.getCodemirrorController()
    if (previewController && previewController.isVisible && codemirrorController) {
      const { currentLine, totalLines } = codemirrorController.getCursorInfo()
      previewController.syncToLineSmooth(currentLine, totalLines)
    }

    this.syncOutlineActiveLine(lineNumber)
  }

  // Dispatch an input event to trigger all listeners after programmatic value changes
  // Note: CodeMirror handles this automatically, but kept for backward compatibility
  triggerTextareaInput() {
    this.onEditorChange({ detail: { docChanged: true } })
  }

  // Check if cursor is in a markdown table (debounced to avoid performance issues)
  checkTableAtCursor() {
    // Debounce table detection - no need to check on every keystroke
    if (this._tableCheckTimeout) {
      clearTimeout(this._tableCheckTimeout)
    }

    this._tableCheckTimeout = setTimeout(() => {
      this._tableCheckTimeout = null
      this._doCheckTableAtCursor()
    }, 200)
  }

  // Internal: Actually perform the table check
  _doCheckTableAtCursor() {
    const codemirrorController = this.getCodemirrorController()
    if (!codemirrorController) return

    const text = codemirrorController.getValue()
    const cursorInfo = codemirrorController.getCursorPosition()
    const tableInfo = findTableAtPosition(text, cursorInfo.offset)

    this._setTableHintVisible(!!tableInfo)
  }

  // Toggle table hint visibility. Consolidated here because Tailwind's
  // .inline-block is declared after .hidden at equal specificity, so
  // both classes must be swapped to actually change display.
  _setTableHintVisible(visible) {
    this.tableHintTarget.classList.toggle("hidden", !visible)
    this.tableHintTarget.classList.toggle("inline-block", visible)
  }

  // === Autosave Event Handlers ===

  onAutosaveConfigSaved() {
    this.reloadConfig()
  }

  onAutosaveOfflineChanged(event) {
    const { offline } = event.detail
    if (offline && this.configSaveTimeout) {
      clearTimeout(this.configSaveTimeout)
      this.configSaveTimeout = null
    }
  }

  // Reload configuration from server and apply changes
  async reloadConfig() {
    const configCtrl = this.getEditorConfigController()
    if (configCtrl) {
      await configCtrl.reload()
      const autosaveCtrl = this.getAutosaveController()
      if (autosaveCtrl) {
        autosaveCtrl.showSaveStatus(window.t("status.config_applied"))
        setTimeout(() => autosaveCtrl.showSaveStatus(""), 2000)
      }
    }
  }

  // === Preview Panel - Delegates to preview_controller ===
  togglePreview() {
    // Only allow preview for markdown files
    if (!this.isMarkdownFile()) {
      this.showTemporaryMessage("Preview is only available for markdown files")
      return
    }

    // Reading mode is a preview-first layout. Exit it first, then apply the
    // user's preview toggle against the restored editor layout.
    if (this.readingModeActive) {
      this.toggleReadingMode()
    }

    this.disableTypewriterMode()

    const previewController = this.getPreviewController()
    if (previewController) {
      previewController.toggle()
    }
  }

  updatePreview() {
    const previewController = this.getPreviewController()
    if (!previewController) return

    previewController.setCurrentNotePath?.(this.currentFile)

    const scrollSync = this.getScrollSyncController()
    if (scrollSync) {
      scrollSync.updatePreview()
      return
    }

    previewController.render(this.getCurrentDocumentContent(), {
      currentNotePath: this.currentFile
    })
  }

  getCurrentDocumentContent() {
    const codemirrorController = this.getCodemirrorController()
    const editorContent = codemirrorController ? codemirrorController.getValue() : ""
    const textareaContent = this.hasTextareaTarget ? this.textareaTarget.value : ""
    return editorContent || textareaContent || ""
  }

  getRenderedDocumentTitle() {
    if (!this.currentFile) return "Untitled"

    const leaf = this.currentFile.split("/").pop() || this.currentFile
    return leaf.replace(/\.[^.]+$/, "") || "Untitled"
  }

  getActiveThemeId() {
    return document.documentElement.getAttribute("data-theme") ||
      this.getEditorConfigController()?.themeValue ||
      null
  }

  waitForDomPaint() {
    return new Promise((resolve) => {
      if (typeof requestAnimationFrame === "function") {
        requestAnimationFrame(() => {
          requestAnimationFrame(() => resolve())
        })
      } else {
        setTimeout(resolve, 0)
      }
    })
  }

  async prepareRenderedPreview() {
    if (!this.currentFile || !this.isMarkdownFile()) return null

    const previewController = this.getPreviewController()
    if (!previewController?.hasContentTarget) return null

    const shouldRestoreVisibility = !previewController.isVisible && !this.readingModeActive

    if (!previewController.isVisible) {
      this._transientPreviewPreparation = true
      try {
        previewController.show()
      } finally {
        this._transientPreviewPreparation = false
      }
    }

    this.updatePreview()
    await this.waitForDomPaint()

    return {
      previewController,
      restore: () => {
        if (!shouldRestoreVisibility) return

        this._transientPreviewPreparation = true
        try {
          previewController.hide()
        } finally {
          this._transientPreviewPreparation = false
        }
      }
    }
  }

  async collectRenderedDocumentPayload({ embedLocalImages = false } = {}) {
    const preparedPreview = await this.prepareRenderedPreview()
    if (!preparedPreview) return null

    let payload = null

    try {
      payload = preparedPreview.previewController.getRenderedDocumentPayload({
        title: this.getRenderedDocumentTitle(),
        path: this.currentFile,
        themeId: this.getActiveThemeId()
      })
    } finally {
      preparedPreview.restore()
    }

    if (!payload || !embedLocalImages) return payload
    return this.inlineExportPayloadImages(payload)
  }

  async inlineExportPayloadImages(payload) {
    if (!payload?.html) return payload

    return {
      ...payload,
      html: await inlineSameOriginImages(payload.html, {
        baseUrl: window.location.href
      })
    }
  }

  // === Table Editor ===
  openTableEditor() {
    let existingTable = null
    let startPos = 0
    let endPos = 0

    // Check if cursor is in existing table
    const codemirrorController = this.getCodemirrorController()
    if (codemirrorController) {
      const text = codemirrorController.getValue()
      const cursorPos = codemirrorController.getCursorPosition().offset
      const tableInfo = findTableAtPosition(text, cursorPos)

      if (tableInfo) {
        existingTable = tableInfo.lines.join("\n")
        startPos = tableInfo.startPos
        endPos = tableInfo.endPos
      }
    }

    // Dispatch event for table_editor_controller
    window.dispatchEvent(new CustomEvent("frankmd:open-table-editor", {
      detail: { existingTable, startPos, endPos }
    }))
  }

  // Setup listener for table insertion from table_editor_controller
  setupTableEditorListener() {
    this.boundTableInsertHandler = this.handleTableInsert.bind(this)
    window.addEventListener("frankmd:insert-table", this.boundTableInsertHandler)
  }

  // Handle table insertion from table_editor_controller
  handleTableInsert(event) {
    const { markdown, editMode, startPos, endPos } = event.detail

    if (!markdown) return

    const codemirrorController = this.getCodemirrorController()
    if (!codemirrorController) return

    insertBlockContent(codemirrorController, markdown, { editMode, startPos, endPos })
    codemirrorController.focus()
    this.onEditorChange({ detail: { docChanged: true } })
  }

  // === Image Picker Event Handler ===
  onImageSelected(event) {
    const { markdown } = event.detail
    if (!markdown) return

    const codemirrorController = this.getCodemirrorController()
    if (!codemirrorController) return

    insertImage(codemirrorController, markdown)
    codemirrorController.focus()
    this.onEditorChange({ detail: { docChanged: true } })
  }

  // Open image picker dialog (delegates to image-picker controller)
  openImagePicker() {
    if (this.hasImagePickerOutlet) this.imagePickerOutlet.open()
  }

  // === Editor Customization - Delegates to customize_controller ===
  openCustomize() {
    if (this.hasCustomizeOutlet) {
      const configCtrl = this.getEditorConfigController()
      const font = configCtrl ? configCtrl.currentFont : "cascadia-code"
      const fontSize = configCtrl ? configCtrl.currentFontSize : 14
      const previewFontFamily = configCtrl ? configCtrl.currentPreviewFontFamily : "sans"
      this.customizeOutlet.open(font, fontSize, previewFontFamily)
    }
  }

  // Handle customize:applied event from customize_controller
  onCustomizeApplied(event) {
    const { font, fontSize, previewFontFamily } = event.detail

    // Save to server config (will trigger reload)
    this.saveConfig({
      editor_font: font,
      editor_font_size: fontSize,
      preview_font_family: previewFontFamily
    })

    // Apply immediately via config controller
    const configCtrl = this.getEditorConfigController()
    if (configCtrl) {
      configCtrl.fontValue = font
      configCtrl.fontSizeValue = fontSize
      configCtrl.previewFontFamilyValue = previewFontFamily
    }
  }

  applyEditorSettings() {
    const configCtrl = this.getEditorConfigController()
    if (configCtrl) {
      configCtrl.applyFont()
      configCtrl.applyEditorWidth()
      configCtrl.applyPreviewFontFamily()
      configCtrl.applyLineNumbers()
    }
  }

  // === Editor Width Adjustment ===

  // Editor width bounds (in characters)
  static MIN_EDITOR_WIDTH = 40
  static MAX_EDITOR_WIDTH = 200
  static EDITOR_WIDTH_STEP = 8 // Change by 8 characters per step

  increaseEditorWidth() {
    const maxWidth = this.constructor.MAX_EDITOR_WIDTH
    const step = this.constructor.EDITOR_WIDTH_STEP
    const configCtrl = this.getEditorConfigController()
    const currentWidth = configCtrl ? configCtrl.editorWidth : 72

    if (currentWidth >= maxWidth) {
      this.showTemporaryMessage(`Maximum width (${maxWidth}ch)`)
      return
    }

    const newWidth = Math.min(currentWidth + step, maxWidth)
    if (configCtrl) configCtrl.editorWidthValue = newWidth
    this.saveConfig({ editor_width: newWidth })
    this.showTemporaryMessage(`Editor width: ${newWidth}ch`)
  }

  decreaseEditorWidth() {
    const minWidth = this.constructor.MIN_EDITOR_WIDTH
    const step = this.constructor.EDITOR_WIDTH_STEP
    const configCtrl = this.getEditorConfigController()
    const currentWidth = configCtrl ? configCtrl.editorWidth : 72

    if (currentWidth <= minWidth) {
      this.showTemporaryMessage(`Minimum width (${minWidth}ch)`)
      return
    }

    const newWidth = Math.max(currentWidth - step, minWidth)
    if (configCtrl) configCtrl.editorWidthValue = newWidth
    this.saveConfig({ editor_width: newWidth })
    this.showTemporaryMessage(`Editor width: ${newWidth}ch`)
  }

  // === Line Numbers - Now handled by CodeMirror ===

  toggleLineNumberMode() {
    const codemirrorController = this.getCodemirrorController()
    if (codemirrorController) {
      const newMode = codemirrorController.toggleLineNumberMode()
      const configCtrl = this.getEditorConfigController()
      if (configCtrl) configCtrl.lineNumbersValue = newMode
      this.saveConfig({ editor_line_numbers: newMode })
    }
  }


  // === Path Display - Delegates to path_display_controller ===

  updatePathDisplay(path) {
    const pathDisplayController = this.getPathDisplayController()
    if (pathDisplayController) {
      pathDisplayController.update(path)
    }
  }

  // === Save config settings to server (debounced) ===
  saveConfig(settings) {
    this.pendingConfigSettings = {
      ...this.pendingConfigSettings,
      ...settings
    }

    // Clear any pending save
    if (this.configSaveTimeout) {
      clearTimeout(this.configSaveTimeout)
    }

    // Debounce saves to avoid excessive API calls
    this.configSaveTimeout = setTimeout(async () => {
      const updates = { ...this.pendingConfigSettings }
      this.pendingConfigSettings = {}
      this.configSaveTimeout = null

      try {
        const response = await patch("/config", {
          body: updates,
          responseKind: "json"
        })

        if (!response.ok) {
          console.warn("Failed to save config:", await response.text)
        } else {
          // Notify other controllers that config file was modified
          window.dispatchEvent(new CustomEvent("frankmd:config-file-modified"))
        }
      } catch (error) {
        console.warn("Failed to save config:", error)
      }
    }, 500)
  }

  // Reload .fed content if it's open in the editor
  async reloadCurrentConfigFile() {
    if (this.currentFile !== ".fed") return

    try {
      const response = await get(`/notes/${encodePath(".fed")}`, { responseKind: "json" })

      if (response.ok) {
        const data = await response.json
        const codemirrorController = this.getCodemirrorController()
        if (codemirrorController) {
          // Save cursor position
          const cursorPos = codemirrorController.getCursorPosition().offset
          // Update content
          codemirrorController.setValue(data.content || "")
          // Restore cursor position (or end of file if content is shorter)
          const newContent = codemirrorController.getValue()
          const newCursorPos = Math.min(cursorPos, newContent.length)
          codemirrorController.setSelection(newCursorPos, newCursorPos)
        }
      }
    } catch (error) {
      console.warn("Failed to reload config file:", error)
    }
  }

  // Listen for config file modifications from any source (theme, settings, etc.)
  setupConfigFileListener() {
    this.boundConfigFileHandler = () => {
      // If .fed is currently open in the editor, reload it
      if (this.currentFile === ".fed") {
        this.reloadCurrentConfigFile()
      }
    }
    window.addEventListener("frankmd:config-file-modified", this.boundConfigFileHandler)
  }

  setupRecoveryStateListeners() {
    this.boundRecoveryOpenedHandler = this.onRecoveryDialogOpened.bind(this)
    this.boundRecoveryResolvedHandler = this.onRecoveryDialogResolved.bind(this)
    this.element.addEventListener("recovery-diff:opened", this.boundRecoveryOpenedHandler)
    this.element.addEventListener("recovery-diff:resolved", this.boundRecoveryResolvedHandler)
  }

  onRecoveryDialogOpened() {
    this.recoveryAvailable = true
    this.emitUiStateChanged("recovery-opened")
  }

  onRecoveryDialogResolved() {
    this.recoveryAvailable = false
    this.emitUiStateChanged("recovery-resolved")
  }

  // === Preview Zoom - Delegates to preview_controller ===
  zoomPreviewIn() {
    const previewController = this.getPreviewController()
    if (previewController) {
      previewController.zoomIn()
    }
  }

  zoomPreviewOut() {
    const previewController = this.getPreviewController()
    if (previewController) {
      previewController.zoomOut()
    }
  }

  applyPreviewZoom() {
    const previewController = this.getPreviewController()
    if (previewController) {
      previewController.applyZoom()
    }
  }

  // === Sidebar/Explorer Toggle ===
  toggleSidebar() {
    this.sidebarVisible = !this.sidebarVisible
    this.applySidebarVisibility()
  }

  applySidebarVisibility() {
    if (this.hasSidebarTarget) {
      this.sidebarTarget.classList.toggle("hidden", !this.sidebarVisible)
    }
    if (this.hasSidebarToggleTarget) {
      this.sidebarToggleTarget.setAttribute("aria-expanded", this.sidebarVisible.toString())
    }
  }

  // === Reading Mode Toggle ===
  toggleReadingMode(event) {
    if (!this.readingModeActive) {
      this.disableTypewriterMode()
    }

    this.readingModeActive = !this.readingModeActive

    if (this.readingModeActive) {
      // Enter Reading Mode: Hide Editor Panel
      this.editorPanelTarget.classList.add("hidden")

      // Mark body so fade-overlay controller knows reading mode is active
      document.body.classList.add("reading-mode-active")

      // Update Preview header title to 'Reading Mode'
      if (this.hasPreviewTitleTarget) {
        this.previewTitleTarget.textContent = "Reading Mode"
      }

      // Ensure preview is visible if it was hidden
      const previewController = this.getPreviewController()
      if (previewController && !previewController.isVisible) {
        previewController.show()
      }

      // Expand Preview Width Priority
      if (this.hasPreviewPanelTarget) {
        this.previewPanelTarget.classList.add("!w-full")
      }

      // Apply Typography Constraints for Reading Mode
      if (this.hasPreviewContentTarget) {
        this.previewContentTarget.classList.remove("max-w-none")
        this.previewContentTarget.classList.add("max-w-4xl", "mx-auto", "px-8")
      }

      // Explicit Typography Safeguard: Ensure Editor Target NEVER inherits these classes
      if (this.hasEditorTarget) {
        this.editorTarget.classList.remove("max-w-4xl", "mx-auto", "px-8")
      }
      if (this.hasEditorPanelTarget) {
        this.editorPanelTarget.classList.remove("max-w-4xl", "mx-auto", "px-8")
      }
    } else {
      // Exit Reading Mode: Show Editor Panel
      this.editorPanelTarget.classList.remove("hidden")

      // Remove body class so fade-overlay pill stops listening
      document.body.classList.remove("reading-mode-active")

      // Restore Preview header title to 'Preview'
      if (this.hasPreviewTitleTarget) {
        this.previewTitleTarget.textContent = "Preview"
      }

      // Restore Preview Width
      if (this.hasPreviewPanelTarget) {
        this.previewPanelTarget.classList.remove("!w-full")
      }

      // Restore Typography Defaults
      if (this.hasPreviewContentTarget) {
        this.previewContentTarget.classList.remove("max-w-4xl", "mx-auto", "px-8")
        this.previewContentTarget.classList.add("max-w-none")
      }

      // If typewriter was already active before reading mode, recenter once the
      // editor is visible again.
      if (this.isMarkdownFile()) {
        setTimeout(() => {
          this.maintainTypewriterScroll()
        }, 10)
      }
    }

    this.persistCurrentMode()
    this.emitUiStateChanged("reading-mode-toggled")
  }

  // === Print / Export as PDF ===
  async printNote() {
    try {
      const payload = await this.collectRenderedDocumentPayload({ embedLocalImages: true })
      if (!payload) return false

      const documentHtml = this.buildStandaloneExportDocument(payload)
      return this.printStandaloneDocument(documentHtml)
    } catch (error) {
      console.error("Failed to export PDF", error)
      this.showTemporaryMessage(window.t("status.export_failed"))
      return false
    }
  }

  getExportLanguage() {
    return document.documentElement.lang ||
      document.documentElement.getAttribute("lang") ||
      window.frankmdLocale ||
      "en"
  }

  buildStandaloneExportDocument(payload) {
    return buildStandaloneExportHtmlDocument(payload, {
      theme: captureExportThemeSnapshot(document.documentElement),
      language: this.getExportLanguage(),
      documentTitle: payload?.title || "Untitled"
    })
  }

  downloadExportFile(filename, content, contentType) {
    return downloadBrowserExportFile(filename, content, contentType)
  }

  printStandaloneDocument(documentHtml) {
    return printBrowserExportDocument(documentHtml, {
      timeoutMs: 60000,
      onError: () => this.showTemporaryMessage(window.t("status.export_failed"))
    })
  }

  async waitForExportDocumentAssets(frameWindow, timeoutMs = 5000) {
    return waitForBrowserExportAssets(frameWindow, timeoutMs)
  }

  async waitForDocumentImages(frameDocument, timeoutMs = 5000) {
    return waitForBrowserDocumentImages(frameDocument, timeoutMs)
  }

  async exportHtmlDocument() {
    try {
      const payload = await this.collectRenderedDocumentPayload({ embedLocalImages: true })
      if (!payload) return false

      return this.downloadExportFile(
        buildExportFilename(payload, "html"),
        this.buildStandaloneExportDocument(payload),
        "text/html;charset=utf-8"
      )
    } catch (error) {
      console.error("Failed to export HTML", error)
      this.showTemporaryMessage(window.t("status.export_failed"))
      return false
    }
  }

  async exportTextDocument() {
    try {
      const payload = await this.collectRenderedDocumentPayload()
      if (!payload) return false

      return this.downloadExportFile(
        buildExportFilename(payload, "txt"),
        buildPlainTextExport(payload),
        "text/plain;charset=utf-8"
      )
    } catch (error) {
      console.error("Failed to export text", error)
      this.showTemporaryMessage(window.t("status.export_failed"))
      return false
    }
  }

  async copyMarkdown() {
    const codemirrorController = this.getCodemirrorController()
    const content = codemirrorController
      ? codemirrorController.getValue()
      : (this.hasTextareaTarget ? this.textareaTarget.value : "")

    return this.copyTextToClipboard(normalizeLineEndings(content), {
      successMessage: window.t("status.copied_to_clipboard"),
      failureMessage: window.t("status.copy_failed")
    })
  }

  // === Export as Clipboard (Rich HTML) ===
  async copyFormattedHtml({ button = null } = {}) {
    const originalHtml = button?.innerHTML
    let copied = false

    try {
      const payload = await this.collectRenderedDocumentPayload({ embedLocalImages: true })
      if (!payload) return false

      // Write both HTML and Plain Text formats
      const clipboardItem = new ClipboardItem({
        "text/html": new Blob([payload.html], { type: "text/html" }),
        "text/plain": new Blob([payload.plainText], { type: "text/plain" })
      })

      await navigator.clipboard.write([clipboardItem])

      if (button) {
        // Visual feedback: Change icon to checkmark temporarily
        button.innerHTML = `<svg class="w-5 h-5 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" /></svg>`
      } else {
        this.showTemporaryMessage(window.t("status.copied_to_clipboard"))
      }

      copied = true
    } catch (err) {
      console.error("Failed to copy note to clipboard", err)
      if (button) {
        // Visual feedback: Change icon to X temporarily
        button.innerHTML = `<svg class="w-5 h-5 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>`
      } else {
        this.showTemporaryMessage(window.t("status.copy_failed"))
      }

      copied = false
    } finally {
      if (button) {
        setTimeout(() => {
          button.innerHTML = originalHtml
        }, 2000)
      }
    }

    return copied
  }

  async copyTextToClipboard(text, {
    successMessage = window.t("status.copied_to_clipboard"),
    failureMessage = window.t("status.copy_failed")
  } = {}) {
    try {
      await navigator.clipboard.writeText(text)
      this.showTemporaryMessage(successMessage)
      return true
    } catch (error) {
      console.error("Failed to copy text to clipboard", error)
      this.showTemporaryMessage(failureMessage)
      return false
    }
  }

  async buildCurrentShareSnapshot() {
    const payload = await this.collectRenderedDocumentPayload({ embedLocalImages: true })
    if (!payload) return null

    return {
      payload,
      documentHtml: this.buildStandaloneExportDocument(payload)
    }
  }

  async parseShareResponse(response, fallbackErrorKey = "status.share_failed") {
    if (response.ok) {
      return response.json
    }

    try {
      const data = await response.json
      throw new Error(data?.error || window.t(fallbackErrorKey))
    } catch (error) {
      if (error instanceof Error) throw error
      throw new Error(window.t(fallbackErrorKey))
    }
  }

  async flushPendingAutosaveForShare() {
    const autosaveController = this.getAutosaveController()
    if (autosaveController?.saveTimeout) {
      await autosaveController.saveNow()
    }
  }

  applySharedNoteContent(share) {
    const nextContent = share?.note_content
    if (!nextContent || !this.isMarkdownFile()) return

    const codemirrorController = this.getCodemirrorController()
    if (!codemirrorController) return

    const currentContent = codemirrorController.getValue()
    if (currentContent === nextContent) return

    const currentSelection = codemirrorController.getSelection()
    const currentCursor = codemirrorController.getCursorPosition().offset
    const prefixDelta = nextContent.endsWith(currentContent) ? nextContent.length - currentContent.length : 0
    const nextCursor = Math.min(currentCursor + prefixDelta, nextContent.length)

    codemirrorController.setValue(nextContent)

    if (currentSelection.from !== currentSelection.to && prefixDelta > 0) {
      const nextAnchor = Math.min(currentSelection.from + prefixDelta, nextContent.length)
      const nextHead = Math.min(currentSelection.to + prefixDelta, nextContent.length)
      codemirrorController.setSelection(nextAnchor, nextHead)
    } else {
      codemirrorController.setSelection(nextCursor, nextCursor)
    }

    this.refreshNoteLinkAutocompleteContext()
  }

  async createShareLink() {
    try {
      await this.flushPendingAutosaveForShare()
      const snapshot = await this.buildCurrentShareSnapshot()
      if (!snapshot) return false

      const response = await post("/shares", {
        body: {
          path: this.currentFile,
          title: snapshot.payload.title,
          html: snapshot.documentHtml
        },
        responseKind: "json"
      })

      const share = await this.parseShareResponse(response)
      this.applySharedNoteContent(share)
      this.setCurrentShare(share)

      return this.copyTextToClipboard(share.url, {
        successMessage: window.t(share.created ? "status.share_link_created" : "status.share_link_copied"),
        failureMessage: window.t("status.share_failed")
      })
    } catch (error) {
      console.error("Failed to create shared link", error)
      this.showTemporaryMessage(error.message || window.t("status.share_failed"))
      return false
    }
  }

  async copyShareLink() {
    if (!this.currentShare?.url) {
      this.showTemporaryMessage(window.t("errors.share_not_found"))
      return false
    }

    return this.copyTextToClipboard(this.currentShare.url, {
      successMessage: window.t("status.share_link_copied"),
      failureMessage: window.t("status.share_failed")
    })
  }

  async refreshShareLink() {
    if (!this.currentShare?.url) {
      this.showTemporaryMessage(window.t("errors.share_not_found"))
      return false
    }

    try {
      await this.flushPendingAutosaveForShare()
      const snapshot = await this.buildCurrentShareSnapshot()
      if (!snapshot) return false

      const response = await patch(`/shares/${encodePath(this.currentFile)}`, {
        body: {
          title: snapshot.payload.title,
          html: snapshot.documentHtml
        },
        responseKind: "json"
      })

      const share = await this.parseShareResponse(response)
      this.applySharedNoteContent(share)
      this.setCurrentShare(share)
      this.showTemporaryMessage(window.t("status.share_link_refreshed"))
      return true
    } catch (error) {
      console.error("Failed to refresh shared snapshot", error)
      this.showTemporaryMessage(error.message || window.t("status.share_failed"))
      return false
    }
  }

  async disableShareLink() {
    if (!this.currentShare?.url) {
      this.showTemporaryMessage(window.t("errors.share_not_found"))
      return false
    }

    try {
      const response = await destroy(`/shares/${encodePath(this.currentFile)}`, {
        responseKind: "json"
      })

      await this.parseShareResponse(response)
      this.clearCurrentShare()
      this.showTemporaryMessage(window.t("status.share_link_disabled"))
      return true
    } catch (error) {
      console.error("Failed to disable shared link", error)
      this.showTemporaryMessage(error.message || window.t("status.share_failed"))
      return false
    }
  }

  openShareManagement() {
    this.getShareManagementController()?.open()
  }

  openExportMenu() {
    this.getExportMenuController()?.openMenu?.()
  }

  onStatusStripPublishClicked() {
    this.openExportMenu()
  }

  async onShareManagementSharesCleared() {
    if (this.currentShare) {
      this.clearCurrentShare()
    }

    await this.refreshCurrentShareState()
  }

  async onShareManagementShareDeleted(event) {
    if (this.currentShareMatchesManagementDeletion(event?.detail)) {
      this.clearCurrentShare()
    }

    await this.refreshCurrentShareState()
  }

  async onShareManagementOpenNote(event) {
    const path = event.detail?.path
    if (!path) return

    await this.loadFile(path)
  }

  currentShareMatchesManagementDeletion(detail = {}) {
    if (!this.currentShare) return false

    return [
      detail.token && detail.token === this.currentShare.token,
      detail.path && detail.path === this.currentFile,
      detail.noteIdentifier && detail.noteIdentifier === this.currentShare.note_identifier
    ].some(Boolean)
  }

  async onExportMenuSelected(event) {
    const actionId = event.detail?.actionId

    switch (actionId) {
      case "copy-html":
        await this.copyFormattedHtml()
        return
      case "copy-markdown":
        await this.copyMarkdown()
        return
      case "print-pdf":
        await this.printNote()
        return
      case "export-html":
        await this.exportHtmlDocument()
        return
      case "export-txt":
        await this.exportTextDocument()
        return
      case "create-share-link":
        await this.createShareLink()
        return
      case "copy-share-link":
        await this.copyShareLink()
        return
      case "refresh-share-link":
        await this.refreshShareLink()
        return
      case "disable-share-link":
        await this.disableShareLink()
        return
      case "manage-share-api":
        this.openShareManagement()
        return
      default:
        return
    }
  }

  // === Typewriter Mode - Delegates to typewriter_controller ===

  applyPersistedPreviewWidth() {
    const splitPaneController = this.getSplitPaneController()
    const configCtrl = this.getEditorConfigController()
    if (!splitPaneController || !configCtrl) return

    splitPaneController.applyWidth(configCtrl.previewWidth)
  }

  getPersistedActiveMode() {
    const configCtrl = this.getEditorConfigController()
    return configCtrl ? configCtrl.persistedActiveMode : "raw"
  }

  restorePersistedUiState() {
    this.applyPersistedPreviewWidth()

    if (!this._codemirrorReady || !this.currentFile || !this.isMarkdownFile()) {
      return
    }

    const previewController = this.getPreviewController()
    const typewriterController = this.getTypewriterController()
    const targetMode = this.getPersistedActiveMode()

    this._restoringPersistedUiState = true

    try {
      if (this.readingModeActive && targetMode !== "reading") {
        this.toggleReadingMode()
      }

      if (typewriterController?.enabledValue && targetMode !== "typewriter") {
        this.disableTypewriterMode()
      }

      switch (targetMode) {
        case "reading":
          if (!this.readingModeActive) {
            this.toggleReadingMode()
          }
          break
        case "preview":
          if (previewController && !previewController.isVisible) {
            previewController.show()
          }
          break
        case "typewriter":
          if (previewController?.isVisible) {
            previewController.hide()
          }
          if (typewriterController && !typewriterController.enabledValue) {
            typewriterController.toggle()
          }
          break
        case "raw":
        default:
          if (previewController?.isVisible) {
            previewController.hide()
          }
          break
      }
    } finally {
      this._restoringPersistedUiState = false
    }

    this.refreshOutline()
  }

  persistCurrentMode() {
    if (this._restoringPersistedUiState || !this.currentFile || !this.isMarkdownFile()) return

    const mode = this.getModeState().mode
    const configCtrl = this.getEditorConfigController()

    if (configCtrl) {
      configCtrl.activeModeValue = mode
      configCtrl.typewriterModeValue = mode === "typewriter"
    }

    this.saveConfig({
      active_mode: mode,
      typewriter_mode: mode === "typewriter"
    })
  }

  disableTypewriterMode() {
    const typewriterController = this.getTypewriterController()
    if (!typewriterController || !typewriterController.enabledValue) return false

    typewriterController.toggle()
    return true
  }

  toggleTypewriterMode() {
    // Only allow typewriter mode for markdown files
    if (!this.isMarkdownFile()) {
      this.showTemporaryMessage("Typewriter mode is only available for markdown files")
      return
    }

    const typewriterController = this.getTypewriterController()
    if (typewriterController) {
      // ALWAYS exit Reading Mode first, regardless of Typewriter's current state.
      // This ensures pressing Typewriter while in Reading Mode always restores the editor.
      if (this.readingModeActive) {
        this.toggleReadingMode()
      }

      if (!typewriterController.enabledValue) {
        // Enabling Typewriter: also hide preview for distraction-free writing
        const previewController = this.getPreviewController()
        if (previewController && previewController.isVisible) {
          previewController.hide()
        }
      }

      typewriterController.toggle()
    }
  }

  // Handle typewriter:toggled event
  onTypewriterToggled(event) {
    const { enabled } = event.detail

    // Toggle typewriter mode on preview controller
    const previewController = this.getPreviewController()
    if (previewController) {
      previewController.setTypewriterMode(enabled)
    }

    // Typewriter mode: hide preview for distraction-free writing
    // Sidebar is intentionally left untouched â€” it is user-controlled only
    if (enabled) {
      // Hide preview (keep editor only for focused writing)
      if (previewController && previewController.isVisible) {
        previewController.hide()
      }

      // Add typewriter body class for full-width editor centering
      document.body.classList.add("typewriter-mode")
    } else {
      // Remove typewriter body class
      document.body.classList.remove("typewriter-mode")
    }

    this.persistCurrentMode()
    this.emitUiStateChanged("typewriter-toggled")
  }

  maintainTypewriterScroll() {
    const codemirrorController = this.getCodemirrorController()
    if (!codemirrorController) return

    // Center cursor in editor (works regardless of preview)
    codemirrorController.maintainTypewriterScroll()

    // Sync preview if visible
    const previewController = this.getPreviewController()
    if (previewController && previewController.isVisible) {
      const syncData = codemirrorController.getTypewriterSyncData()
      if (syncData) {
        previewController.syncToTypewriter(syncData.currentLine, syncData.totalLines)
      }
    }
  }

  // Show a temporary message to the user (auto-dismisses)
  showTemporaryMessage(message, duration = 2000, isError = false) {
    // Remove any existing message
    const existing = document.querySelector(".temporary-message")
    if (existing) existing.remove()

    const el = document.createElement("div")
    el.className = isError
      ? "temporary-message fixed bottom-4 left-1/2 -translate-x-1/2 bg-[var(--theme-bg-secondary)] text-[var(--theme-error)] px-4 py-2 rounded-lg shadow-lg border border-[var(--theme-error)] text-sm z-50"
      : "temporary-message fixed bottom-4 left-1/2 -translate-x-1/2 bg-[var(--theme-bg-secondary)] text-[var(--theme-text-primary)] px-4 py-2 rounded-lg shadow-lg border border-[var(--theme-border)] text-sm z-50"
    el.textContent = message
    document.body.appendChild(el)

    setTimeout(() => el.remove(), duration)
  }

  // === File Finder (Ctrl+P) - Delegates to file_finder_controller ===
  openFileFinder() {
    if (this.hasFileFinderOutlet) {
      this.fileFinderOutlet.open(this.getFilesFromTree())
    }
  }

  // Build flat list of files from DOM tree for file finder, sorted newest-first
  getFilesFromTree() {
    const fileElements = this.fileTreeTarget.querySelectorAll('[data-type="file"]')
    return Array.from(fileElements).map(el => ({
      path: el.dataset.path,
      name: el.dataset.path.split("/").pop().replace(/\.md$/, ""),
      type: "file",
      file_type: el.dataset.fileType || "markdown",
      mtime: parseInt(el.dataset.mtime, 10) || 0
    })).sort((a, b) => b.mtime - a.mtime)
  }

  // Handle file selected event from file_finder_controller
  onFileSelected(event) {
    const { path } = event.detail
    this.openFileAndRevealInTree(path)
  }

  async openFileAndRevealInTree(path) {
    // Expand all parent folders in the tree
    const parts = path.split("/")
    let currentPath = ""
    for (let i = 0; i < parts.length - 1; i++) {
      currentPath = currentPath ? `${currentPath}/${parts[i]}` : parts[i]
      this.expandedFolders.add(currentPath)
    }

    // Show sidebar if hidden
    if (!this.sidebarVisible) {
      this.sidebarVisible = true
      this.applySidebarVisibility()
    }

    // Load the file
    await this.loadFile(path)
  }

  openFindReplace(options = {}) {
    if (this.hasFindReplaceOutlet) {
      const codemirrorController = this.getCodemirrorController()
      const selection = codemirrorController ? codemirrorController.getSelection().text : ""
      this.findReplaceOutlet.open({
        textarea: this.createTextareaAdapter(),
        tab: options.tab,
        query: selection || undefined
      })
    }
  }

  // Create an adapter that makes CodeMirror look like a textarea for find/replace
  createTextareaAdapter() {
    const codemirrorController = this.getCodemirrorController()
    if (!codemirrorController) {
      return this.hasTextareaTarget ? this.textareaTarget : null
    }
    return createTextareaAdapter(codemirrorController)
  }

  onFindReplaceJump(event) {
    const { start, end } = event.detail
    const codemirrorController = this.getCodemirrorController()

    if (codemirrorController) {
      codemirrorController.focus()
      codemirrorController.setSelection(start, end)
      codemirrorController.scrollToPosition(start)
    }
  }

  onFindReplaceReplace(event) {
    const { start, end, replacement } = event.detail
    const codemirrorController = this.getCodemirrorController()

    if (codemirrorController) {
      codemirrorController.replaceRange(replacement, start, end)
      const newPosition = start + replacement.length
      codemirrorController.setSelection(newPosition, newPosition)
      codemirrorController.scrollToPosition(newPosition)
      this.onEditorChange({ detail: { docChanged: true } })
    }
  }

  onFindReplaceReplaceAll(event) {
    const { updatedText } = event.detail
    if (typeof updatedText !== "string") return

    const codemirrorController = this.getCodemirrorController()
    if (codemirrorController) {
      codemirrorController.setValue(updatedText)
      codemirrorController.setSelection(0, 0)
      codemirrorController.scrollTo(0)
      this.onEditorChange({ detail: { docChanged: true } })
    }
  }

  openJumpToLine() {
    if (this.hasJumpToLineOutlet) {
      this.jumpToLineOutlet.open(this.createTextareaAdapter())
    }
  }

  onJumpToLine(event) {
    const { lineNumber } = event.detail
    if (!lineNumber) return
    this.jumpToLine(lineNumber)
  }

  // Content Search (Ctrl+Shift+F) - Delegates to content_search_controller
  openContentSearch() {
    if (this.hasContentSearchOutlet) this.contentSearchOutlet.open()
  }

  // Handle search result selected event from content_search_controller
  async onSearchResultSelected(event) {
    const { path, lineNumber } = event.detail
    await this.openFileAndRevealInTree(path)
    this.jumpToLine(lineNumber)
  }

  jumpToLine(lineNumber) {
    const codemirrorController = this.getCodemirrorController()
    if (codemirrorController) {
      codemirrorController.jumpToLine(lineNumber)
    }
  }

  scrollTextareaToPosition(position) {
    const codemirrorController = this.getCodemirrorController()
    if (codemirrorController) {
      codemirrorController.scrollToPosition(position)
    }
  }

  // === Help Dialog - delegates to help controller ===
  openHelp() {
    const helpController = this.getHelpController()
    if (helpController) {
      helpController.openHelp()
    }
  }

  // === Log Viewer - Delegates to log_viewer_controller ===
  openLogViewer() {
    if (this.hasLogViewerOutlet) this.logViewerOutlet.open()
  }

  // === Code Snippet Editor - Delegates to code_dialog_controller ===
  openCodeEditor() {
    const codemirrorController = this.getCodemirrorController()
    if (!codemirrorController || !this.hasCodeDialogOutlet) return

    const text = codemirrorController.getValue()
    const cursorPos = codemirrorController.getCursorPosition().offset
    const codeBlock = findCodeBlockAtPosition(text, cursorPos)

    if (codeBlock) {
      this.codeDialogOutlet.open({
        language: codeBlock.language || "",
        content: codeBlock.content || "",
        editMode: true,
        startPos: codeBlock.startPos,
        endPos: codeBlock.endPos
      })
    } else {
      this.codeDialogOutlet.open()
    }
  }

  // Handle code insert event from code_dialog_controller
  onCodeInsert(event) {
    const codemirrorController = this.getCodemirrorController()
    if (!codemirrorController) return

    const { codeBlock, language, editMode, startPos, endPos } = event.detail

    insertCodeBlock(codemirrorController, codeBlock, language, { editMode, startPos, endPos })
    codemirrorController.focus()
    this.onEditorChange({ detail: { docChanged: true } })
  }

  // About Dialog - delegates to help controller
  openAboutDialog() {
    const helpController = this.getHelpController()
    if (helpController) {
      helpController.openAbout()
    }
  }

  // Video Dialog - delegates to video-dialog controller
  openVideoDialog() {
    if (this.hasVideoDialogOutlet) this.videoDialogOutlet.open()
  }

  // Video Embed Event Handler - receives events from video_dialog_controller
  insertVideoEmbed(event) {
    const { embedCode } = event.detail
    if (!embedCode) return

    const codemirrorController = this.getCodemirrorController()
    if (!codemirrorController) return

    insertVideoEmbed(codemirrorController, embedCode)
    codemirrorController.focus()
    this.onEditorChange({ detail: { docChanged: true } })
  }

  // === AI Assist Methods ===

  async openAiDialog() {
    if (!this.currentFile) {
      alert(window.t("errors.no_file_open"))
      return
    }

    const codemirrorController = this.getCodemirrorController()
    const text = codemirrorController ? codemirrorController.getValue() : ""
    if (!text.trim()) {
      alert(window.t("errors.no_text_to_check"))
      return
    }

    // Save file first if there are pending changes (server reads from disk)
    const autosaveForAi = this.getAutosaveController()
    if (autosaveForAi && autosaveForAi.saveTimeout) {
      await autosaveForAi.saveNow()
    }

    this.getAiAssistController()?.openModal("grammar")
  }

  openCustomAiDialog() {
    this.getAiAssistController()?.openModal("custom_prompt")
  }

  getAiAssistController() {
    const element = document.querySelector('[data-controller~="custom-ai-prompt"]')
    return element ? this.application.getControllerForElementAndIdentifier(element, "custom-ai-prompt") : null
  }

  // Handle AI processing started event - disable editor and show button loading state
  onAiProcessingStarted() {
    const codemirrorController = this.getCodemirrorController()
    if (codemirrorController) {
      codemirrorController.setReadOnly(true)
    }

    if (this.hasAiButtonTarget) {
      this.aiButtonOriginalContent = this.aiButtonTarget.innerHTML
      this.aiButtonTarget.innerHTML = `
        <svg class="animate-spin w-4 h-4" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        <span>${window.t("status.processing")}</span>
      `
      this.aiButtonTarget.disabled = true
    }
  }

  // Handle AI processing ended event - re-enable editor and restore button
  onAiProcessingEnded() {
    const codemirrorController = this.getCodemirrorController()
    if (codemirrorController) {
      codemirrorController.setReadOnly(false)
    }

    if (this.hasAiButtonTarget && this.aiButtonOriginalContent) {
      this.aiButtonTarget.innerHTML = this.aiButtonOriginalContent
      this.aiButtonTarget.disabled = false
    }
  }

  // Handle AI correction accepted event - update editor with corrected text
  onAiAccepted(event) {
    const { correctedText, range } = event.detail
    const codemirrorController = this.getCodemirrorController()
    if (codemirrorController) {
      // Sanitize incoming AI payload â€” strip carriage returns but preserve newlines
      const sanitizedText = normalizeLineEndings(correctedText)
      const replacingSelection = range && range.from !== undefined && range.to !== undefined
      const from = replacingSelection ? range.from : 0
      const to = replacingSelection ? range.to : codemirrorController.editor.state.doc.length
      const nextCursorPosition = from + sanitizedText.length

      codemirrorController.editor.dispatch({
        changes: { from, to, insert: sanitizedText },
        selection: { anchor: nextCursorPosition, head: nextCursorPosition }
      })
      codemirrorController.scrollToPosition(nextCursorPosition)

      // Force the preview to re-render with the new content
      const previewController = this.getPreviewController()
      if (previewController && previewController.isVisible) {
        previewController.renderContent(codemirrorController.getValue())
      }

      // Fix: Directly update stats panel via the Stimulus outlet.
      // This ensures the line counter recalculates immediately after AI text insertion
      // (CodeMirror's doc.lines is always accurate post-dispatch).
      this.updateStats()
    }
  }

  // Handle preview zoom changed event - save to config
  onPreviewZoomChanged(event) {
    const { zoom } = event.detail
    const configCtrl = this.getEditorConfigController()
    if (configCtrl) configCtrl.previewZoomValue = zoom
    this.saveConfig({ preview_zoom: zoom })
    this.emitUiStateChanged("preview-zoom-changed")
  }

  onCodeMirrorReady() {
    this._codemirrorReady = true
    this.restorePersistedUiState()
  }

  // Handle preview toggled event
  onPreviewToggled(event) {
    const { visible } = event.detail
    if (visible) {
      // Ensure editor sync is setup (may not have been ready at connect time)
      const previewController = this.getPreviewController()
      if (previewController && this.hasTextareaTarget) {
        previewController.setupEditorSync(this.textareaTarget)
      }
    }

    if (this._transientPreviewPreparation) return

    this.persistCurrentMode()
    this.emitUiStateChanged("preview-toggled")
  }

  onPreviewWidthChanged(event) {
    const width = Number(event.detail?.width)
    if (!Number.isFinite(width)) return

    const nextWidth = Math.max(20, Math.min(Math.round(width), 70))
    const configCtrl = this.getEditorConfigController()
    if (configCtrl) configCtrl.previewWidthValue = nextWidth
    this.saveConfig({ preview_width: nextWidth })
  }

  // === File Operations Event Handlers ===

  async onFileCreated(event) {
    const { path } = event.detail

    // Expand parent folders
    const pathParts = path.split("/")
    let expandPath = ""
    for (let i = 0; i < pathParts.length - 1; i++) {
      expandPath = expandPath ? `${expandPath}/${pathParts[i]}` : pathParts[i]
      this.expandedFolders.add(expandPath)
    }

    // Tree is already updated by Turbo Stream
    await this.loadFile(path)
  }

  onFolderCreated(event) {
    const { path } = event.detail
    this.expandedFolders.add(path)
    // Tree is already updated by Turbo Stream
    this.persistExplorerResumeState()
  }

  onFileRenamed(event) {
    const { oldPath, newPath, type } = event.detail
    let currentFileRenamed = false

    if (type === "folder") {
      // Preserve expand/collapse state for renamed folder and its descendants.
      this.expandedFolders = new Set(
        Array.from(this.expandedFolders, (path) => {
          if (path === oldPath || path.startsWith(oldPath + "/")) {
            return `${newPath}${path.slice(oldPath.length)}`
          }
          return path
        })
      )
    }

    // For folder renames, update current file path if it's inside the renamed folder
    if (type === "folder" && this.currentFile?.startsWith(oldPath + "/")) {
      this.currentFile = `${newPath}${this.currentFile.slice(oldPath.length)}`
      this.updatePathDisplay(this.currentFile.replace(/\.md$/, ""))
      this.updateUrl(this.currentFile)
      currentFileRenamed = true
    }

    // Update current file if it was the renamed file
    if (this.currentFile === oldPath) {
      this.currentFile = newPath
      this.updatePathDisplay(newPath.replace(/\.md$/, ""))
      this.updateUrl(newPath)
      currentFileRenamed = true
    }

    this.remapRememberedLastOpenNote(oldPath, newPath)

    if (currentFileRenamed) {
      this.getAutosaveController()?.renameCurrentFile?.(oldPath, newPath)
      this.getPreviewController()?.setCurrentNotePath?.(this.isMarkdownFile() ? this.currentFile : null)
      this.refreshNoteLinkAutocompleteContext()
    }

    if (this.currentFile) {
      this.refreshCurrentShareState()
    }

    // Tree is already updated by Turbo Stream
    this.persistExplorerResumeState()
  }

  onFileDeleted(event) {
    const { path, type } = event.detail

    if (type === "folder") {
      this.expandedFolders = new Set(
        Array.from(this.expandedFolders).filter((expandedPath) => expandedPath !== path && !expandedPath.startsWith(`${path}/`))
      )
    }

    this.clearRememberedLastOpenNote(path)

    const deletedCurrentFile =
      this.currentFile === path ||
      (type === "folder" && this.currentFile?.startsWith(`${path}/`))

    // Clear editor if deleted file was currently open
    if (deletedCurrentFile) {
      this.showEditorPlaceholder("file-cleared")
    }

    // Tree is already updated by Turbo Stream
    this.persistExplorerResumeState()
  }

  onFileOperationsStatusMessage(event) {
    const { message, duration = 2500, error = false } = event.detail || {}
    if (!message) return

    this.showTemporaryMessage(message, duration, error)
  }

  // File Operations - delegate to file-operations controller
  newNote() {
    const fileOps = this.getFileOperationsController()
    if (fileOps) fileOps.newNote()
  }

  newFolder() {
    const fileOps = this.getFileOperationsController()
    if (fileOps) fileOps.newFolder()
  }

  async saveCurrentNoteAsTemplate() {
    if (!this.currentFile || !this.isMarkdownFile()) {
      alert(window.t("errors.templates_markdown_only"))
      return
    }

    const fileOps = this.getFileOperationsController()
    if (fileOps) {
      await fileOps.openSaveTemplateFromNoteDialog(this.currentFile)
    }
  }

  showContextMenu(event) {
    const fileOps = this.getFileOperationsController()
    if (fileOps) fileOps.showContextMenu(event)
  }

  setupDialogClickOutside() {
    // Close dialog when clicking on backdrop (outside the dialog content)
    if (this.hasHelpDialogTarget) {
      this.helpDialogTarget.addEventListener("click", (event) => {
        if (event.target === this.helpDialogTarget) {
          this.helpDialogTarget.close()
        }
      })
    }
  }

  async refreshTree() {
    try {
      const expanded = this.serializeExpandedFoldersForRequest()
      const selected = this.currentFile || ""
      const response = await get(`/notes/tree?expanded=${encodeURIComponent(expanded)}&selected=${encodeURIComponent(selected)}`)
      if (response.ok) {
        const html = await response.text
        this.fileTreeTarget.innerHTML = html
        this.refreshNoteLinkAutocompleteContext()
      }
    } catch (error) {
      console.error("Error refreshing tree:", error)
    }
  }

  // === Keyboard Shortcuts ===
  setupKeyboardShortcuts() {
    // Merge default shortcuts with user customizations (future: load from config)
    const shortcuts = mergeShortcuts(DEFAULT_SHORTCUTS, this.userShortcuts)

    this.boundKeydownHandler = createKeyHandler(shortcuts, (action) => {
      this.executeShortcutAction(action)
    })

    document.addEventListener("keydown", this.boundKeydownHandler)
  }

  // Execute an action triggered by a keyboard shortcut
  executeShortcutAction(action) {
    const actions = {
      newNote: () => this.getFileOperationsController()?.newNote(),
      save: () => this.getAutosaveController()?.saveNow(),
      // Note: bold and italic are handled by CodeMirror's keymap (codemirror_extensions.js)
      togglePreview: () => this.togglePreview(),
      toggleReadingMode: () => this.toggleReadingMode(),
      findInFile: () => this.openFindReplace(),
      findReplace: () => this.openFindReplace({ tab: "replace" }),
      jumpToLine: () => this.openJumpToLine(),
      lineNumbers: () => this.toggleLineNumberMode(),
      contentSearch: () => this.openContentSearch(),
      fileFinder: () => this.openFileFinder(),
      toggleSidebar: () => this.toggleSidebar(),
      typewriterMode: () => this.toggleTypewriterMode(),
      textFormat: () => this.openTextFormatMenu(),
      emojiPicker: () => this.openEmojiPicker(),
      increaseWidth: () => this.increaseEditorWidth(),
      decreaseWidth: () => this.decreaseEditorWidth(),
      logViewer: () => this.openLogViewer(),
      help: () => this.openHelp(),
      closeDialogs: () => this.closeAllDialogs()
    }

    const handler = actions[action]
    if (handler) {
      handler()
    }
  }

  // Close all open dialogs and menus
  closeAllDialogs() {
    // Close context menu
    if (this.hasContextMenuTarget) {
      this.contextMenuTarget.classList.add("hidden")
    }

    // Close help dialog
    if (this.hasHelpDialogTarget && this.helpDialogTarget.open) {
      this.helpDialogTarget.close()
    }
  }

  // === Editor Indentation ===
  // Note: Tab/Shift+Tab indentation is now handled by CodeMirror's indentWithTab keymap

  // Get the current indent string
  getIndentString() {
    const configCtrl = this.getEditorConfigController()
    return (configCtrl ? configCtrl.editorIndent : 2) || "  "
  }

  // === Text Format Menu ===

  // Open text format menu via Ctrl+M
  openTextFormatMenu() {
    if (!this.isMarkdownFile()) return
    const cm = this.getCodemirrorController()
    if (!cm) return
    const textFormatController = this.getTextFormatController()
    if (textFormatController) textFormatController.openFromKeyboard(cm)
  }

  onTextareaContextMenu(event) {
    if (!this.isMarkdownFile()) return
    const cm = this.getCodemirrorController()
    const textFormatController = this.getTextFormatController()
    if (textFormatController) textFormatController.onContextMenu(event, cm, true)
  }

  onTextFormatContentChanged() {
    this.getAutosaveController()?.scheduleAutoSave()
    this.updatePreview()
  }

  onTextFormatClosed() {
    const cm = this.getCodemirrorController()
    if (cm) cm.focus()
  }

  applyInlineFormat(formatId) {
    const cm = this.getCodemirrorController()
    if (!cm) return
    const textFormatController = this.getTextFormatController()
    if (!textFormatController) return
    if (textFormatController.applyFormatById(formatId, this.createTextareaAdapter())) {
      this.getAutosaveController()?.scheduleAutoSave()
      this.updatePreview()
    }
  }

  // === Emoji Picker ===

  // Open emoji picker dialog
  openEmojiPicker() {
    if (!this.hasTextareaTarget) return
    if (!this.isMarkdownFile()) return

    const emojiPickerController = this.getEmojiPickerController()
    if (emojiPickerController) {
      emojiPickerController.open()
    }
  }

  // Handle emoji/emoticon selected event
  onEmojiSelected(event) {
    const codemirrorController = this.getCodemirrorController()
    if (!codemirrorController) return

    const { text: insertText } = event.detail
    if (!insertText) return

    insertInlineContent(codemirrorController, insertText)
    codemirrorController.focus()
    this.getAutosaveController()?.scheduleAutoSave()
    this.updatePreview()
  }

  // === Utilities ===

  // Position a dialog near a specific point (for explorer dialogs)
  positionDialogNearPoint(dialog, x, y) {
    dialog.classList.add("positioned")

    // Use showModal first to get dimensions
    dialog.showModal()

    // Get dialog dimensions
    const rect = dialog.getBoundingClientRect()
    const padding = 10

    // Calculate position, keeping dialog on screen
    let left = x
    let top = y

    // Adjust if dialog would go off right edge
    if (left + rect.width > window.innerWidth - padding) {
      left = window.innerWidth - rect.width - padding
    }

    // Adjust if dialog would go off bottom edge
    if (top + rect.height > window.innerHeight - padding) {
      top = window.innerHeight - rect.height - padding
    }

    // Ensure dialog stays on screen (left/top)
    left = Math.max(padding, left)
    top = Math.max(padding, top)

    dialog.style.left = `${left}px`
    dialog.style.top = `${top}px`
  }

  // Show dialog centered (default behavior)
  showDialogCentered(dialog) {
    dialog.classList.remove("positioned")
    dialog.style.left = ""
    dialog.style.top = ""
    dialog.showModal()
  }

  // Clean up any object URLs created for local folder images
  cleanupLocalFolderImages() {
    // Implementation depends on image picker state
    // This is called on disconnect to prevent memory leaks
  }

  // === Document Stats - delegates to stats-panel controller ===

  showStatsPanel() {
    const statsController = this.getStatsPanelController()
    if (statsController) {
      statsController.show()
    }
  }

  hideStatsPanel() {
    const statsController = this.getStatsPanelController()
    if (statsController) {
      statsController.hide()
    }
  }

  scheduleStatsUpdate() {
    const statsController = this.getStatsPanelController()
    const codemirrorController = this.getCodemirrorController()
    if (statsController && codemirrorController) {
      statsController.scheduleUpdate(codemirrorController.getValue(), codemirrorController.getCursorInfo())
    }
  }

  updateStats() {
    const statsController = this.getStatsPanelController()
    const codemirrorController = this.getCodemirrorController()
    if (statsController && codemirrorController) {
      statsController.update(codemirrorController.getValue(), codemirrorController.getCursorInfo())
    }
  }

  updateLinePosition() {
    const statsController = this.getStatsPanelController()
    const codemirrorController = this.getCodemirrorController()
    if (statsController && codemirrorController) {
      statsController.updateLinePosition(codemirrorController.getCursorInfo())
    }
  }

  getCursorInfo() {
    const codemirrorController = this.getCodemirrorController()
    if (!codemirrorController) return null

    return codemirrorController.getCursorInfo()
  }
}
