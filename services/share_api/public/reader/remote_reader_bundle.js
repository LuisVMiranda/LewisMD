import {
  BUILTIN_THEMES,
  applyThemeToRoot,
  buildThemeUrl,
  isDarkTheme,
  renderThemeMenuHtml,
  resolvedThemeId,
  themeNameFor
} from "/reader/assets/theme_helpers.js"
import {
  AVAILABLE_LOCALES,
  buildLocaleUrl,
  localeNameFor,
  renderLocaleMenuHtml
} from "/reader/assets/locale_helpers.js"
import {
  buildExportMenuItems,
  renderExportMenuHtml
} from "/reader/assets/export_menu_helpers.js"
import {
  dispatchTranslationsLoaded,
  installGlobalTranslationHelper,
  setGlobalTranslations
} from "/reader/assets/translation_helpers.js"

const EXPORT_THEME_VARIABLES = [
  "--theme-bg-primary",
  "--theme-bg-secondary",
  "--theme-bg-tertiary",
  "--theme-border",
  "--theme-text-primary",
  "--theme-text-secondary",
  "--theme-text-muted",
  "--theme-accent",
  "--theme-accent-hover",
  "--theme-code-bg",
  "--theme-heading-1",
  "--theme-heading-2",
  "--theme-heading-3",
  "--font-mono",
  "--font-sans"
]

const DEFAULT_TRANSLATIONS = {
  header: {
    change_theme: "Change theme",
    change_language: "Change language",
    share: "Share",
    open_share_menu: "Open share menu"
  },
  share_view: {
    label: "Shared note",
    display: "Display",
    display_controls: "Reading controls",
    show_controls: "Show reading controls",
    hide_controls: "Hide reading controls",
    iframe_title: "Shared note preview",
    zoom: "Zoom",
    zoom_in: "Zoom in",
    zoom_out: "Zoom out",
    width: "Width",
    width_narrower: "Make text column narrower",
    width_wider: "Make text column wider",
    font_family: "Font",
    font_default: "Default",
    font_sans: "Sans",
    font_serif: "Serif",
    font_mono: "Mono"
  },
  export_menu: {
    copy_note: "Copy Note",
    copy_markdown: "Copy Markdown",
    export_files: "Export files",
    export_html: "Export HTML",
    export_txt: "Export TXT",
    export_pdf: "Export PDF",
    create_share_link: "Create shared link",
    copy_share_link: "Copy shared link",
    refresh_share_link: "Refresh shared snapshot",
    disable_share_link: "Disable shared link"
  },
  status: {
    copied_to_clipboard: "Copied to clipboard.",
    copy_failed: "Could not copy this snapshot.",
    export_failed: "Could not export this snapshot.",
    print_failed: "Could not open the print dialog."
  }
}

const DEFAULT_FONT_FAMILY = "default"
const MIN_ZOOM = 70
const MAX_ZOOM = 200
const ZOOM_STEP = 10
const MIN_WIDTH = 48
const MAX_WIDTH = 96
const WIDTH_STEP = 4

const FONT_FAMILIES = {
  default: "",
  sans: 'var(--font-sans, "Inter", ui-sans-serif, system-ui, sans-serif)',
  serif: 'Georgia, Cambria, "Times New Roman", Times, serif',
  mono: 'var(--font-mono, "JetBrains Mono", ui-monospace, monospace)'
}

installGlobalTranslationHelper(window)

function currentThemeId(explicitThemeId = null) {
  const prefersDark = window.matchMedia?.("(prefers-color-scheme: dark)").matches || false
  return resolvedThemeId(explicitThemeId || document.documentElement.getAttribute("data-theme"), prefersDark)
}

function installTranslations({ locale = "en", translations = DEFAULT_TRANSLATIONS } = {}) {
  setGlobalTranslations({
    locale,
    translations
  })
  dispatchTranslationsLoaded({
    locale,
    translations
  })
}

function buildFilename(title, extension) {
  const safeBase = String(title || "shared-note")
    .replace(/[<>:"/\\|?*\u0000-\u001F]/g, "-")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^\.+/, "")
    .replace(/[. -]+$/, "")
    .trim() || "shared-note"

  return `${safeBase}.${extension}`
}

function downloadFile(filename, content, contentType) {
  const blob = new Blob([content], { type: contentType })
  const url = URL.createObjectURL(blob)
  const link = document.createElement("a")
  link.href = url
  link.download = filename
  link.rel = "noopener"
  link.style.display = "none"
  document.body.appendChild(link)
  link.click()
  setTimeout(() => {
    link.remove()
    URL.revokeObjectURL(url)
  }, 0)
}

class RemoteShareReader {
  constructor(element) {
    this.element = element
    this.frame = element.querySelector('[data-role="frame"]')
    this.themeButton = element.querySelector('[data-role="theme-toggle"]')
    this.themeMenu = element.querySelector('[data-role="theme-menu"]')
    this.themeCurrentLabel = element.querySelector('[data-role="theme-current-label"]')
    this.localeButton = element.querySelector('[data-role="locale-toggle"]')
    this.localeMenu = element.querySelector('[data-role="locale-menu"]')
    this.localeCurrentLabel = element.querySelector('[data-role="locale-current-label"]')
    this.exportButton = element.querySelector('[data-role="export-toggle"]')
    this.exportMenu = element.querySelector('[data-role="export-menu"]')
    this.displayPanel = element.querySelector('[data-role="display-panel"]')
    this.displayToggle = element.querySelector('[data-role="display-toggle"]')
    this.zoomValue = element.querySelector('[data-role="zoom-value"]')
    this.widthValue = element.querySelector('[data-role="width-value"]')
    this.fontSelect = element.querySelector('[data-role="font-select"]')

    this.title = element.dataset.title || document.title || "shared-note"
    this.currentTheme = currentThemeId(element.dataset.theme)
    this.currentLocale = element.dataset.locale || "en"
    this.currentZoom = Number.parseInt(element.dataset.defaultZoom || "100", 10) || 100
    this.currentWidth = Number.parseInt(element.dataset.defaultWidth || "72", 10) || 72
    this.currentFontFamily = element.dataset.defaultFontFamily || DEFAULT_FONT_FAMILY
    this.showControlsLabel = element.dataset.showControlsLabel || window.t("share_view.show_controls")
    this.hideControlsLabel = element.dataset.hideControlsLabel || window.t("share_view.hide_controls")
    this.displayPanelExpanded = !this.displayPanel?.classList.contains("hidden")
    this.exportGroupExpanded = false
    this.baseFontSize = null
  }

  connect() {
    installTranslations({ locale: this.currentLocale })
    applyThemeToRoot(this.currentTheme)
    document.documentElement.lang = this.currentLocale
    this.updateColorSchemeMeta()
    this.renderMenus()
    this.attachEventListeners()
    this.updateDisplays()
    this.applyDisplayPanelState()

    if (this.frame?.contentDocument?.readyState === "complete") {
      this.onFrameLoad()
    }
  }

  disconnect() {
    document.removeEventListener("click", this.boundDocumentClick)
    this.frame?.removeEventListener("load", this.boundFrameLoad)
    this.themeButton?.removeEventListener("click", this.boundThemeToggle)
    this.themeMenu?.removeEventListener("click", this.boundThemeMenuClick)
    this.localeButton?.removeEventListener("click", this.boundLocaleToggle)
    this.localeMenu?.removeEventListener("click", this.boundLocaleMenuClick)
    this.exportButton?.removeEventListener("click", this.boundExportToggle)
    this.exportMenu?.removeEventListener("click", this.boundExportMenuClick)
    this.displayToggle?.removeEventListener("click", this.boundDisplayToggle)
    this.element.querySelector('[data-role="zoom-in"]')?.removeEventListener("click", this.boundZoomIn)
    this.element.querySelector('[data-role="zoom-out"]')?.removeEventListener("click", this.boundZoomOut)
    this.element.querySelector('[data-role="width-increase"]')?.removeEventListener("click", this.boundWidthIncrease)
    this.element.querySelector('[data-role="width-decrease"]')?.removeEventListener("click", this.boundWidthDecrease)
    this.fontSelect?.removeEventListener("change", this.boundFontChange)
  }

  attachEventListeners() {
    this.boundDocumentClick = (event) => {
      if (!this.element.contains(event.target)) this.closeMenus()
    }
    this.boundFrameLoad = () => this.onFrameLoad()
    this.boundThemeToggle = (event) => this.toggleMenu(event, "theme")
    this.boundThemeMenuClick = (event) => this.onThemeMenuClick(event)
    this.boundLocaleToggle = (event) => this.toggleMenu(event, "locale")
    this.boundLocaleMenuClick = (event) => this.onLocaleMenuClick(event)
    this.boundExportToggle = (event) => this.toggleMenu(event, "export")
    this.boundExportMenuClick = (event) => this.onExportMenuClick(event)
    this.boundDisplayToggle = () => this.toggleDisplayPanel()
    this.boundZoomIn = () => this.zoomIn()
    this.boundZoomOut = () => this.zoomOut()
    this.boundWidthIncrease = () => this.increaseWidth()
    this.boundWidthDecrease = () => this.decreaseWidth()
    this.boundFontChange = (event) => this.changeFontFamily(event)

    document.addEventListener("click", this.boundDocumentClick)
    this.frame?.addEventListener("load", this.boundFrameLoad)
    this.themeButton?.addEventListener("click", this.boundThemeToggle)
    this.themeMenu?.addEventListener("click", this.boundThemeMenuClick)
    this.localeButton?.addEventListener("click", this.boundLocaleToggle)
    this.localeMenu?.addEventListener("click", this.boundLocaleMenuClick)
    this.exportButton?.addEventListener("click", this.boundExportToggle)
    this.exportMenu?.addEventListener("click", this.boundExportMenuClick)
    this.displayToggle?.addEventListener("click", this.boundDisplayToggle)
    this.element.querySelector('[data-role="zoom-in"]')?.addEventListener("click", this.boundZoomIn)
    this.element.querySelector('[data-role="zoom-out"]')?.addEventListener("click", this.boundZoomOut)
    this.element.querySelector('[data-role="width-increase"]')?.addEventListener("click", this.boundWidthIncrease)
    this.element.querySelector('[data-role="width-decrease"]')?.addEventListener("click", this.boundWidthDecrease)
    this.fontSelect?.addEventListener("change", this.boundFontChange)
  }

  renderMenus() {
    if (this.themeMenu) {
      this.themeMenu.innerHTML = renderThemeMenuHtml({
        themes: BUILTIN_THEMES,
        currentThemeId: this.currentTheme,
        action: ""
      })
    }

    if (this.localeMenu) {
      this.localeMenu.innerHTML = renderLocaleMenuHtml({
        locales: AVAILABLE_LOCALES,
        currentLocaleId: this.currentLocale,
        action: ""
      })
    }

    if (this.exportMenu) {
      this.exportMenu.innerHTML = renderExportMenuHtml({
        items: buildExportMenuItems({
          markdownCopyable: false,
          shareState: { shareable: false, active: false, url: null },
          exportGroupExpanded: this.exportGroupExpanded
        }),
        expanded: this.exportGroupExpanded,
        controllerIdentifier: "remote-reader",
        translate: (key) => window.t(key)
      })
    }

    this.updateCurrentLabels()
  }

  updateCurrentLabels() {
    if (this.themeCurrentLabel) {
      this.themeCurrentLabel.textContent = themeNameFor(this.currentTheme, BUILTIN_THEMES)
    }

    if (this.localeCurrentLabel) {
      this.localeCurrentLabel.textContent = localeNameFor(this.currentLocale, AVAILABLE_LOCALES)
    }
  }

  toggleMenu(event, menuName) {
    event.preventDefault()
    event.stopPropagation()

    const targetMenu = this.menuFor(menuName)
    const targetButton = this.buttonFor(menuName)
    if (!targetMenu || !targetButton) return

    const shouldOpen = targetMenu.classList.contains("hidden")
    this.closeMenus()

    if (shouldOpen) {
      targetMenu.classList.remove("hidden")
      targetButton.setAttribute("aria-expanded", "true")
    }
  }

  menuFor(menuName) {
    return {
      theme: this.themeMenu,
      locale: this.localeMenu,
      export: this.exportMenu
    }[menuName] || null
  }

  buttonFor(menuName) {
    return {
      theme: this.themeButton,
      locale: this.localeButton,
      export: this.exportButton
    }[menuName] || null
  }

  closeMenus() {
    [this.themeMenu, this.localeMenu, this.exportMenu].forEach((menu) => menu?.classList.add("hidden"))
    ;[this.themeButton, this.localeButton, this.exportButton].forEach((button) => button?.setAttribute("aria-expanded", "false"))
  }

  onThemeMenuClick(event) {
    const button = event.target.closest("[data-theme]")
    if (!button) return

    event.preventDefault()
    const themeId = button.dataset.theme
    if (!BUILTIN_THEMES.some((theme) => theme.id === themeId)) return

    this.currentTheme = themeId
    applyThemeToRoot(themeId)
    this.updateColorSchemeMeta()
    this.updateCurrentLabels()
    this.renderMenus()
    this.syncFrameTheme()
    this.replaceUrl(buildThemeUrl(themeId))
    this.closeMenus()
  }

  onLocaleMenuClick(event) {
    const button = event.target.closest("[data-locale]")
    if (!button) return

    event.preventDefault()
    const localeId = button.dataset.locale
    if (!AVAILABLE_LOCALES.some((locale) => locale.id === localeId)) return

    this.currentLocale = localeId
    document.documentElement.lang = localeId
    installTranslations({ locale: localeId })
    this.renderMenus()
    this.replaceUrl(buildLocaleUrl(localeId))
    this.closeMenus()
  }

  onExportMenuClick(event) {
    const button = event.target.closest("button")
    if (!button) return

    event.preventDefault()
    event.stopPropagation()

    const actionId = button.dataset.actionId
    if (!actionId) {
      this.exportGroupExpanded = !this.exportGroupExpanded
      this.renderMenus()
      return
    }

    switch (actionId) {
      case "copy-html":
        this.copyToClipboard()
        break
      case "export-html":
        this.exportHtmlDocument()
        break
      case "export-txt":
        this.exportTextDocument()
        break
      case "print-pdf":
        this.printDocument()
        break
      default:
        break
    }

    this.exportGroupExpanded = false
    this.renderMenus()
    this.closeMenus()
  }

  onFrameLoad() {
    this.baseFontSize = this.detectBaseFontSize()
    this.syncFrameTheme()
    this.applySettings()
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
    if (this.zoomValue) this.zoomValue.textContent = `${this.currentZoom}%`
    if (this.widthValue) this.widthValue.textContent = `${this.currentWidth}ch`
    if (this.fontSelect) this.fontSelect.value = this.currentFontFamily
  }

  detectBaseFontSize() {
    const rootElement = this.frameDocument?.documentElement
    const view = this.frameWindow || window
    const rootFontSize = rootElement
      ? Number.parseFloat(view.getComputedStyle(rootElement).getPropertyValue("--export-font-size"))
      : Number.NaN

    if (Number.isFinite(rootFontSize) && rootFontSize > 0) return rootFontSize

    const article = this.articleElement
    if (!article) return 16

    const computedFontSize = Number.parseFloat(view.getComputedStyle(article).fontSize)
    return Number.isFinite(computedFontSize) && computedFontSize > 0 ? computedFontSize : 16
  }

  syncFrameTheme() {
    const frameRoot = this.frameDocument?.documentElement
    if (!frameRoot) return

    const computedStyle = window.getComputedStyle(document.documentElement)
    EXPORT_THEME_VARIABLES.forEach((variableName) => {
      const value = computedStyle.getPropertyValue(variableName).trim()
      if (value) {
        frameRoot.style.setProperty(variableName, value)
      } else {
        frameRoot.style.removeProperty(variableName)
      }
    })

    frameRoot.setAttribute("data-theme", this.currentTheme)
    frameRoot.classList.toggle("dark", isDarkTheme(this.currentTheme))

    const colorScheme = isDarkTheme(this.currentTheme) ? "dark" : "light"
    const colorSchemeMeta = this.frameDocument.querySelector('meta[name="color-scheme"]')
    if (colorSchemeMeta) {
      colorSchemeMeta.setAttribute("content", colorScheme)
    }
  }

  updateColorSchemeMeta() {
    const meta = document.querySelector('meta[name="color-scheme"]')
    if (meta) {
      meta.setAttribute("content", isDarkTheme(this.currentTheme) ? "dark" : "light")
    }
  }

  async copyToClipboard() {
    const payload = this.buildArticlePayload()
    if (!payload) {
      this.showTemporaryMessage(window.t("status.copy_failed"))
      return false
    }

    try {
      if (window.ClipboardItem && navigator.clipboard?.write) {
        const clipboardItem = new ClipboardItem({
          "text/html": new Blob([payload.html], { type: "text/html" }),
          "text/plain": new Blob([payload.plainText], { type: "text/plain" })
        })
        await navigator.clipboard.write([clipboardItem])
      } else if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(payload.plainText)
      } else {
        throw new Error("Clipboard API is unavailable")
      }

      this.showTemporaryMessage(window.t("status.copied_to_clipboard"))
      return true
    } catch (error) {
      console.error("Failed to copy shared snapshot to clipboard", error)
      this.showTemporaryMessage(window.t("status.copy_failed"))
      return false
    }
  }

  exportHtmlDocument() {
    const documentHtml = this.serializeFrameDocument()
    if (!documentHtml) {
      this.showTemporaryMessage(window.t("status.export_failed"))
      return false
    }

    downloadFile(
      buildFilename(this.title, "html"),
      documentHtml,
      "text/html;charset=utf-8"
    )
    return true
  }

  exportTextDocument() {
    const payload = this.buildArticlePayload()
    if (!payload) {
      this.showTemporaryMessage(window.t("status.export_failed"))
      return false
    }

    downloadFile(
      buildFilename(this.title, "txt"),
      payload.plainText.endsWith("\n") ? payload.plainText : `${payload.plainText}\n`,
      "text/plain;charset=utf-8"
    )
    return true
  }

  printDocument() {
    try {
      if (!this.frameWindow) throw new Error("Frame window is unavailable")
      this.frameWindow.focus()
      this.frameWindow.print()
      return true
    } catch (error) {
      console.error("Failed to open print dialog", error)
      this.showTemporaryMessage(window.t("status.print_failed"))
      return false
    }
  }

  buildArticlePayload() {
    const article = this.articleElement
    if (!article) return null

    return {
      html: article.innerHTML,
      plainText: article.innerText || article.textContent || ""
    }
  }

  serializeFrameDocument() {
    const frameDocument = this.frameDocument
    if (!frameDocument?.documentElement) return null

    const doctype = frameDocument.doctype
    const doctypeString = doctype ? `<!DOCTYPE ${doctype.name}>` : "<!DOCTYPE html>"
    return `${doctypeString}\n${frameDocument.documentElement.outerHTML}`
  }

  applyDisplayPanelState() {
    this.displayPanel?.classList.toggle("hidden", !this.displayPanelExpanded)

    if (this.displayToggle) {
      this.displayToggle.setAttribute("aria-expanded", String(this.displayPanelExpanded))
      const toggleLabel = this.displayPanelExpanded ? this.hideControlsLabel : this.showControlsLabel
      this.displayToggle.setAttribute("title", toggleLabel)
      this.displayToggle.setAttribute("aria-label", toggleLabel)
    }
  }

  replaceUrl(url) {
    try {
      window.history.replaceState({}, "", url)
    } catch {
      window.location.assign(url)
    }
  }

  showTemporaryMessage(message, duration = 2200) {
    const existing = document.querySelector(".share-view__temporary-message")
    if (existing) existing.remove()

    const element = document.createElement("div")
    element.className = "share-view__temporary-message"
    element.textContent = message
    document.body.appendChild(element)
    window.setTimeout(() => element.remove(), duration)
  }

  get articleElement() {
    return this.frameDocument?.querySelector(".export-article") || null
  }

  get frameDocument() {
    return this.frame?.contentDocument || null
  }

  get frameWindow() {
    return this.frame?.contentWindow || null
  }
}

const readerInstances = new WeakMap()

function boot(root = document) {
  root.querySelectorAll("[data-remote-reader]").forEach((element) => {
    if (readerInstances.has(element)) return

    const reader = new RemoteShareReader(element)
    reader.connect()
    readerInstances.set(element, reader)
  })
}

const RemoteReaderBundle = {
  themes: BUILTIN_THEMES,
  locales: AVAILABLE_LOCALES,
  defaultTranslations: DEFAULT_TRANSLATIONS,
  installTranslations,
  applyTheme(themeId) {
    return applyThemeToRoot(themeId)
  },
  buildThemeUrl(themeId, currentUrl = window.location.href) {
    return buildThemeUrl(themeId, currentUrl)
  },
  buildLocaleUrl(localeId, currentUrl = window.location.href) {
    return buildLocaleUrl(localeId, currentUrl)
  },
  renderThemeMenu({ themes = BUILTIN_THEMES, themeId = currentThemeId() } = {}) {
    return renderThemeMenuHtml({
      themes,
      currentThemeId: themeId,
      action: ""
    })
  },
  renderLocaleMenu({ locales = AVAILABLE_LOCALES, localeId = window.frankmdLocale || "en" } = {}) {
    return renderLocaleMenuHtml({
      locales,
      currentLocaleId: localeId,
      action: ""
    })
  },
  buildExportMenu({ shareState = { shareable: false, active: false, url: null }, exportGroupExpanded = false } = {}) {
    return renderExportMenuHtml({
      items: buildExportMenuItems({
        markdownCopyable: false,
        shareState,
        exportGroupExpanded
      }),
      expanded: exportGroupExpanded,
      controllerIdentifier: "remote-reader",
      translate: (key) => window.t(key)
    })
  },
  boot
}

window.LewisMDRemoteReader = RemoteReaderBundle

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", () => boot(), { once: true })
} else {
  boot()
}

export default RemoteReaderBundle
