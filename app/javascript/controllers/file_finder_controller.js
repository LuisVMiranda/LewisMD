import { Controller } from "@hotwired/stimulus"
import { escapeHtml, fuzzyScore } from "lib/text_utils"
import { encodePath } from "lib/url_utils"

// File Finder Controller
// Handles Ctrl+P file finder dialog
// Dispatches file-finder:selected event with file path

export default class extends Controller {
  static targets = [
    "dialog",
    "input",
    "results",
    "preview"
  ]

  connect() {
    this.allFiles = []
    this.filteredResults = []
    this.selectedIndex = 0
    this.usingKeyboard = false
    this.previewDebounceMs = 150
    this.previewTimeout = null
    this.previewAbortController = null
    this.previewRequestSequence = 0
    this.previewCache = new Map()
  }

  disconnect() {
    this.cancelScheduledPreview()
    this.cancelPreviewRequest()
  }

  // Called by app_controller with flattened file tree
  open(files) {
    this.allFiles = files
    this.filteredResults = [...this.allFiles].slice(0, 10)
    this.selectedIndex = 0
    this.previewCache.clear()

    this.inputTarget.value = ""
    this.renderResults()
    this.dialogTarget.showModal()
    this.inputTarget.focus()
  }

  close() {
    this.cancelScheduledPreview()
    this.cancelPreviewRequest()
    this.dialogTarget.close()
  }

  onInput() {
    const query = this.inputTarget.value.trim().toLowerCase()

    if (!query) {
      this.filteredResults = [...this.allFiles].slice(0, 10)
    } else {
      // Fuzzy search: search in full path (including directories)
      this.filteredResults = this.allFiles
        .map(file => {
          const score = fuzzyScore(file.path.toLowerCase(), query)
          return { ...file, score }
        })
        .filter(file => file.score > 0)
        .sort((a, b) => b.score - a.score)
        .slice(0, 10)
    }

    this.selectedIndex = 0
    this.renderResults()
  }

  renderResults() {
    if (this.filteredResults.length === 0) {
      this.cancelScheduledPreview()
      this.cancelPreviewRequest()
      this.resultsTarget.innerHTML = `
        <div class="px-3 py-6 text-center text-[var(--theme-text-muted)] text-sm">
          ${window.t("sidebar.no_files_found")}
        </div>
      `
      this.previewTarget.innerHTML = ""
      return
    }

    this.resultsTarget.innerHTML = this.filteredResults
      .map((file, index) => {
        const isSelected = index === this.selectedIndex
        const name = file.name.replace(/\.md$/, "")
        const path = file.path.replace(/\.md$/, "")
        const displayPath = path !== name ? path.replace(new RegExp(`${name}$`), "").replace(/\/$/, "") : ""

        return `
          <button
            type="button"
            class="w-full px-3 py-2 text-left flex items-center gap-2 ${isSelected ? 'bg-[var(--theme-accent)] text-[var(--theme-accent-text)]' : 'hover:bg-[var(--theme-bg-hover)]'}"
            data-index="${index}"
            data-path="${escapeHtml(file.path)}"
            data-action="click->file-finder#selectFromClick mouseenter->file-finder#onHover"
          >
            <svg class="w-4 h-4 flex-shrink-0 ${isSelected ? '' : 'text-[var(--theme-text-muted)]'}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
            <div class="min-w-0 flex-1">
              <div class="truncate font-medium">${escapeHtml(name)}</div>
              ${displayPath ? `<div class="truncate text-xs ${isSelected ? 'opacity-75' : 'text-[var(--theme-text-muted)]'}">${escapeHtml(displayPath)}</div>` : ''}
            </div>
          </button>
        `
      })
      .join("")

    this.schedulePreviewLoad()
  }

  currentPreviewPath() {
    if (this.filteredResults.length === 0) return null

    const file = this.filteredResults[this.selectedIndex]
    return file?.path || null
  }

  cancelScheduledPreview() {
    if (!this.previewTimeout) return

    clearTimeout(this.previewTimeout)
    this.previewTimeout = null
  }

  cancelPreviewRequest() {
    if (!this.previewAbortController) return

    this.previewAbortController.abort()
    this.previewAbortController = null
  }

  renderPreview(preview) {
    this.previewTarget.innerHTML = `<pre class="text-xs font-mono whitespace-pre-wrap text-[var(--theme-text-secondary)] leading-relaxed">${escapeHtml(preview)}</pre>`
  }

  renderPreviewError() {
    this.previewTarget.innerHTML = `<div class="text-[var(--theme-text-muted)] text-sm">Unable to load preview</div>`
  }

  schedulePreviewLoad() {
    const path = this.currentPreviewPath()
    this.cancelScheduledPreview()
    this.cancelPreviewRequest()

    if (!path) {
      this.previewTarget.innerHTML = ""
      return
    }

    const cachedPreview = this.previewCache.get(path)
    if (cachedPreview) {
      this.renderPreview(cachedPreview)
      return
    }

    this.previewTimeout = setTimeout(() => {
      this.previewTimeout = null
      this.loadPreview(path)
    }, this.previewDebounceMs)
  }

  async loadPreview(path = this.currentPreviewPath()) {
    if (!path) {
      this.cancelPreviewRequest()
      this.previewTarget.innerHTML = ""
      return
    }

    const cachedPreview = this.previewCache.get(path)
    if (cachedPreview) {
      this.renderPreview(cachedPreview)
      return
    }

    this.cancelPreviewRequest()
    const requestId = ++this.previewRequestSequence
    const abortController = new AbortController()
    this.previewAbortController = abortController

    try {
      const response = await fetch(`/notes/${encodePath(path)}`, {
        headers: { "Accept": "application/json" },
        signal: abortController.signal
      })

      if (requestId !== this.previewRequestSequence) return

      if (!response.ok) {
        this.renderPreviewError()
        return
      }

      const data = await response.json()
      if (requestId !== this.previewRequestSequence) return

      const lines = (data.content || "").split("\n").slice(0, 10)
      const preview = `${lines.join("\n")}${lines.length >= 10 ? "\n..." : ""}`

      this.previewCache.set(path, preview)
      this.renderPreview(preview)
    } catch (error) {
      if (error?.name === "AbortError") return
      if (requestId !== this.previewRequestSequence) return

      this.renderPreviewError()
    } finally {
      if (this.previewAbortController === abortController) {
        this.previewAbortController = null
      }
    }
  }

  onKeydown(event) {
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.usingKeyboard = true
      if (this.selectedIndex < this.filteredResults.length - 1) {
        this.selectedIndex++
        this.renderResults()
      }
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.usingKeyboard = true
      if (this.selectedIndex > 0) {
        this.selectedIndex--
        this.renderResults()
      }
    } else if (event.key === "Enter") {
      event.preventDefault()
      this.selectCurrent()
    }
  }

  onHover(event) {
    // Ignore hover events when navigating with keyboard
    if (this.usingKeyboard) return

    const index = parseInt(event.currentTarget.dataset.index)
    if (index !== this.selectedIndex) {
      this.selectedIndex = index
      this.renderResults()
    }
  }

  onMouseMove() {
    // Re-enable mouse selection when mouse moves
    this.usingKeyboard = false
  }

  selectFromClick(event) {
    const path = event.currentTarget.dataset.path
    this.dispatchSelected(path)
  }

  selectCurrent() {
    if (this.filteredResults.length === 0) return
    const file = this.filteredResults[this.selectedIndex]
    if (file) {
      this.dispatchSelected(file.path)
    }
  }

  dispatchSelected(path) {
    this.dispatch("selected", { detail: { path } })
    this.close()
  }
}
