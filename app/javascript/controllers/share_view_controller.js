import { Controller } from "@hotwired/stimulus"
import {
  EXPORT_THEME_VARIABLES,
  buildExportFilename,
  buildPlainTextExport,
  captureExportThemeSnapshot
} from "lib/export_document_builder"
import {
  downloadExportFile,
  printStandaloneDocument
} from "lib/browser_export_utils"

const DEFAULT_FONT_FAMILY = "default"
const MIN_ZOOM = 70
const MAX_ZOOM = 200
const ZOOM_STEP = 10
const MIN_WIDTH = 48
const MAX_WIDTH = 96
const WIDTH_STEP = 4
const PUBLIC_SHARE_PATH_PATTERN = /^\/s\/[A-Za-z0-9_-]{8,}$/

const FONT_FAMILIES = {
  default: "",
  sans: 'var(--font-sans, "Inter", ui-sans-serif, system-ui, sans-serif)',
  serif: 'Georgia, Cambria, "Times New Roman", Times, serif',
  mono: 'var(--font-mono, "JetBrains Mono", ui-monospace, monospace)'
}

export default class extends Controller {
  static targets = ["frame", "zoomValue", "widthValue", "fontSelect", "displayPanel", "displayToggle", "updatedAtPill"]

  static values = {
    defaultZoom: { type: Number, default: 100 },
    defaultWidth: { type: Number, default: 72 },
    title: String,
    locale: String,
    updatedAt: String,
    lastUpdatedTemplate: String,
    showControlsLabel: String,
    hideControlsLabel: String
  }

  connect() {
    this.currentZoom = this.defaultZoomValue
    this.currentWidth = this.defaultWidthValue
    this.currentFontFamily = DEFAULT_FONT_FAMILY
    this.baseFontSize = null
    this.displayPanelExpanded = true

    this.boundThemeChanged = () => {
      this.syncFrameTheme()
    }
    this.boundResize = () => {
      this.syncResponsiveDisplayPanel()
    }
    this.boundFrameBlockedLinkClick = (event) => this.onBlockedShareLinkClick(event)
    this.boundFrameBlockedLinkKeydown = (event) => this.onBlockedShareLinkKeydown(event)
    this.frameInteractionDocument = null

    window.addEventListener("frankmd:theme-changed", this.boundThemeChanged)
    window.addEventListener("resize", this.boundResize)
    this.renderUpdatedAtPill()
    this.updateDisplays()
    this.syncResponsiveDisplayPanel()
  }

  disconnect() {
    if (this.boundThemeChanged) {
      window.removeEventListener("frankmd:theme-changed", this.boundThemeChanged)
    }
    if (this.boundResize) {
      window.removeEventListener("resize", this.boundResize)
    }
    this.detachFrameInteractionHandlers()
  }

  zoomIn() {
    this.currentZoom = Math.min(MAX_ZOOM, this.currentZoom + ZOOM_STEP)
    this.applySettings()
  }

  zoomOut() {
    this.currentZoom = Math.max(MIN_ZOOM, this.currentZoom - ZOOM_STEP)
    this.applySettings()
  }

  increaseWidth() {
    this.currentWidth = Math.min(MAX_WIDTH, this.currentWidth + WIDTH_STEP)
    this.applySettings()
  }

  decreaseWidth() {
    this.currentWidth = Math.max(MIN_WIDTH, this.currentWidth - WIDTH_STEP)
    this.applySettings()
  }

  changeFontFamily(event) {
    this.currentFontFamily = event.target.value || DEFAULT_FONT_FAMILY
    this.applySettings()
  }

  toggleDisplayPanel() {
    this.displayPanelExpanded = !this.displayPanelExpanded
    this.applyDisplayPanelState()
  }

  onFrameLoad() {
    this.baseFontSize = this.detectBaseFontSize()
    this.syncFrameTheme()
    this.applySettings()
    this.attachFrameInteractionHandlers()
  }

  applySettings() {
    const article = this.articleElement
    if (article) {
      const baseFontSize = this.baseFontSize || this.detectBaseFontSize()
      article.style.fontSize = `${baseFontSize * (this.currentZoom / 100)}px`
      article.style.maxWidth = `${this.currentWidth}ch`
      article.style.fontFamily = FONT_FAMILIES[this.currentFontFamily] || ""
    }

    this.updateDisplays()
  }

  updateDisplays() {
    if (this.hasZoomValueTarget) {
      this.zoomValueTarget.textContent = `${this.currentZoom}%`
    }

    if (this.hasWidthValueTarget) {
      this.widthValueTarget.textContent = `${this.currentWidth}ch`
    }

    if (this.hasFontSelectTarget) {
      this.fontSelectTarget.value = this.currentFontFamily
    }
  }

  renderUpdatedAtPill() {
    if (!this.hasUpdatedAtPillTarget) return

    const formatted = this.formattedUpdatedAtLabel()
    this.updatedAtPillTarget.hidden = !formatted
    this.updatedAtPillTarget.textContent = formatted || ""
  }

  formattedUpdatedAtLabel() {
    const formattedTimestamp = this.formatUpdatedAtTimestamp(this.updatedAtValue)
    if (!formattedTimestamp) return null

    const template = this.lastUpdatedTemplateValue || "Last updated %{timestamp}"
    return template.replace(/%\{timestamp\}/g, formattedTimestamp)
  }

  formatUpdatedAtTimestamp(timestamp) {
    if (!timestamp) return null

    const parsed = new Date(timestamp)
    if (Number.isNaN(parsed.getTime())) return null

    const options = { dateStyle: "medium", timeStyle: "short" }

    try {
      return new Intl.DateTimeFormat(this.localeValue || document.documentElement.lang || undefined, options).format(parsed)
    } catch {
      return new Intl.DateTimeFormat(undefined, options).format(parsed)
    }
  }

  detectBaseFontSize() {
    const rootElement = this.frameDocument?.documentElement
    const view = this.frameWindow || window
    const rootFontSize = rootElement
      ? parseFloat(view.getComputedStyle(rootElement).getPropertyValue("--export-font-size"))
      : NaN

    if (Number.isFinite(rootFontSize) && rootFontSize > 0) {
      return rootFontSize
    }

    const article = this.articleElement
    if (!article) return 16

    const computedFontSize = parseFloat(view.getComputedStyle(article).fontSize)
    return Number.isFinite(computedFontSize) && computedFontSize > 0 ? computedFontSize : 16
  }

  syncFrameTheme() {
    const frameRoot = this.frameDocument?.documentElement
    if (!frameRoot) return

    const themeSnapshot = captureExportThemeSnapshot(document.documentElement)

    EXPORT_THEME_VARIABLES.forEach((variableName) => {
      const value = themeSnapshot.variables[variableName]
      if (value) {
        frameRoot.style.setProperty(variableName, value)
      } else {
        frameRoot.style.removeProperty(variableName)
      }
    })

    const themeId = document.documentElement.getAttribute("data-theme")
    if (themeId) {
      frameRoot.setAttribute("data-theme", themeId)
    } else {
      frameRoot.removeAttribute("data-theme")
    }

    frameRoot.classList.toggle("dark", themeSnapshot.colorScheme === "dark")

    const colorSchemeMeta = this.frameDocument.querySelector('meta[name="color-scheme"]')
    if (colorSchemeMeta) {
      colorSchemeMeta.setAttribute("content", themeSnapshot.colorScheme)
    }
  }

  async onExportMenuSelected(event) {
    const actionId = event.detail?.actionId

    switch (actionId) {
      case "copy-html":
        await this.copyToClipboard()
        return
      case "print-pdf":
        this.printDocument()
        return
      case "export-html":
        this.exportHtmlDocument()
        return
      case "export-txt":
        this.exportTextDocument()
        return
      default:
        return
    }
  }

  exportHtmlDocument() {
    const documentHtml = this.serializeFrameDocument()
    if (!documentHtml) {
      this.showTemporaryMessage(window.t("status.export_failed"))
      return false
    }

    return downloadExportFile(
      buildExportFilename({ title: this.exportTitle }, "html"),
      documentHtml,
      "text/html;charset=utf-8"
    )
  }

  exportTextDocument() {
    const payload = this.buildArticlePayload()
    if (!payload) {
      this.showTemporaryMessage(window.t("status.export_failed"))
      return false
    }

    return downloadExportFile(
      buildExportFilename({ title: this.exportTitle }, "txt"),
      buildPlainTextExport(payload),
      "text/plain;charset=utf-8"
    )
  }

  printDocument() {
    const documentHtml = this.serializeFrameDocument()
    if (!documentHtml) {
      this.showTemporaryMessage(window.t("status.export_failed"))
      return false
    }

    return printStandaloneDocument(documentHtml, {
      timeoutMs: 60000,
      onError: () => this.showTemporaryMessage(window.t("status.export_failed"))
    })
  }

  async copyToClipboard() {
    const payload = this.buildArticlePayload()
    if (!payload) {
      this.showTemporaryMessage(window.t("status.copy_failed"))
      return false
    }

    try {
      const clipboardItem = new ClipboardItem({
        "text/html": new Blob([payload.html], { type: "text/html" }),
        "text/plain": new Blob([payload.plainText], { type: "text/plain" })
      })

      await navigator.clipboard.write([clipboardItem])
      this.showTemporaryMessage(window.t("status.copied_to_clipboard"))
      return true
    } catch (error) {
      console.error("Failed to copy shared snapshot to clipboard", error)
      this.showTemporaryMessage(window.t("status.copy_failed"))
      return false
    }
  }

  buildArticlePayload() {
    const article = this.articleElement
    if (!article) return null

    return {
      title: this.exportTitle,
      html: article.innerHTML,
      plainText: article.innerText || article.textContent || ""
    }
  }

  serializeFrameDocument() {
    const frameDocument = this.frameDocument
    if (!frameDocument?.documentElement) return null

    const doctype = frameDocument.doctype
    const doctypeString = doctype
      ? `<!DOCTYPE ${doctype.name}>`
      : "<!DOCTYPE html>"

    return `${doctypeString}\n${frameDocument.documentElement.outerHTML}`
  }

  showTemporaryMessage(message, duration = 2000) {
    const existing = document.querySelector(".temporary-message")
    if (existing) existing.remove()

    const el = document.createElement("div")
    el.className = "temporary-message fixed bottom-4 left-1/2 -translate-x-1/2 bg-[var(--theme-bg-secondary)] text-[var(--theme-text-primary)] px-4 py-2 rounded-lg shadow-lg border border-[var(--theme-border)] text-sm z-50"
    el.textContent = message
    document.body.appendChild(el)

    setTimeout(() => el.remove(), duration)
  }

  attachFrameInteractionHandlers() {
    const frameDocument = this.frameDocument
    if (!frameDocument) return

    this.detachFrameInteractionHandlers()
    frameDocument.addEventListener("click", this.boundFrameBlockedLinkClick)
    frameDocument.addEventListener("keydown", this.boundFrameBlockedLinkKeydown)
    this.frameInteractionDocument = frameDocument
  }

  detachFrameInteractionHandlers() {
    if (!this.frameInteractionDocument) return

    this.frameInteractionDocument.removeEventListener("click", this.boundFrameBlockedLinkClick)
    this.frameInteractionDocument.removeEventListener("keydown", this.boundFrameBlockedLinkKeydown)
    this.frameInteractionDocument = null
  }

  onBlockedShareLinkClick(event) {
    if (event.defaultPrevented) return
    if (event.button !== 0) return
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

    const publicShareUrl = this.publicShareUrlForEvent(event)
    if (publicShareUrl) {
      event.preventDefault()
      this.navigateToTopLevelUrl(publicShareUrl)
      return
    }

    const blockedLink = event.target.closest('a[data-shared-link-kind="internal-note"]')
    if (!blockedLink) return

    event.preventDefault()
    this.showTemporaryMessage(window.t("status.private_note_link_unavailable"))
  }

  onBlockedShareLinkKeydown(event) {
    if (!["Enter", " "].includes(event.key)) return

    const publicShareUrl = this.publicShareUrlForEvent(event)
    if (publicShareUrl) {
      event.preventDefault()
      this.navigateToTopLevelUrl(publicShareUrl)
      return
    }

    const blockedLink = event.target.closest('a[data-shared-link-kind="internal-note"]')
    if (!blockedLink) return

    event.preventDefault()
    this.showTemporaryMessage(window.t("status.private_note_link_unavailable"))
  }

  publicShareUrlForEvent(event) {
    const link = event.target.closest("a[href]")
    if (!link) return null

    if (link.dataset.sharedLinkKind === "public-share") {
      return this.resolveFrameLinkUrl(link.getAttribute("href"))
    }

    const href = link.getAttribute("href")
    const resolvedUrl = this.resolveFrameLinkUrl(href)
    if (!resolvedUrl) return null

    try {
      const url = new URL(resolvedUrl)
      return PUBLIC_SHARE_PATH_PATTERN.test(url.pathname) ? resolvedUrl : null
    } catch {
      return null
    }
  }

  resolveFrameLinkUrl(href) {
    const normalizedHref = href?.trim()
    if (!normalizedHref || normalizedHref.startsWith("#") || normalizedHref.startsWith("?")) return null

    try {
      return new URL(normalizedHref, window.location.href).toString()
    } catch {
      return null
    }
  }

  navigateToTopLevelUrl(url) {
    try {
      const targetWindow = this.frameWindow?.top || window.top || window
      targetWindow.location.assign(url)
    } catch {
      window.location.assign(url)
    }
  }

  get articleElement() {
    return this.frameDocument?.querySelector(".export-article") || null
  }

  get frameDocument() {
    return this.hasFrameTarget ? this.frameTarget.contentDocument : null
  }

  get frameWindow() {
    return this.hasFrameTarget ? this.frameTarget.contentWindow : null
  }

  get exportTitle() {
    return this.hasTitleValue && this.titleValue
      ? this.titleValue
      : (this.frameDocument?.title || "shared-note")
  }

  syncResponsiveDisplayPanel() {
    this.displayPanelExpanded = this.defaultDisplayPanelExpanded()
    this.applyDisplayPanelState()
  }

  defaultDisplayPanelExpanded() {
    const width = window.innerWidth || document.documentElement.clientWidth || 0
    const height = window.innerHeight || document.documentElement.clientHeight || 0
    const isLandscape = width > height

    if (width < 768) return false
    if (width < 1024) return isLandscape
    return true
  }

  applyDisplayPanelState() {
    if (this.hasDisplayPanelTarget) {
      this.displayPanelTarget.classList.toggle("hidden", !this.displayPanelExpanded)
    }

    if (this.hasDisplayToggleTarget) {
      this.displayToggleTarget.setAttribute("aria-expanded", String(this.displayPanelExpanded))
      const toggleLabel = this.displayPanelExpanded
        ? this.hideControlsLabelValue
        : this.showControlsLabelValue
      if (toggleLabel) {
        this.displayToggleTarget.setAttribute("title", toggleLabel)
        this.displayToggleTarget.setAttribute("aria-label", toggleLabel)
      }
    }
  }
}
