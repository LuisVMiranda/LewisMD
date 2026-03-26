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
import {
  collectOutlineEntries,
  findActiveOutlineIndex
} from "/reader/assets/outline_helpers.js"

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
    outline: "Outline",
    share: "Share",
    open_share_menu: "Open share menu"
  },
  share_view: {
    label: "Shared note",
    display: "Display",
    display_controls: "Reading controls",
    show_controls: "Show reading controls",
    hide_controls: "Hide reading controls",
    show_toolbar: "Show toolbar",
    hide_toolbar: "Hide toolbar",
    collapse_outline: "Collapse outline",
    expand_outline: "Expand outline",
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

function parseTranslations(value) {
  if (!value) return DEFAULT_TRANSLATIONS

  try {
    const parsed = JSON.parse(value)
    return parsed && typeof parsed === "object" ? parsed : DEFAULT_TRANSLATIONS
  } catch {
    return DEFAULT_TRANSLATIONS
  }
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

export class RemoteShareReader {
  constructor(element) {
    this.element = element
    this.frame = element.querySelector('[data-role="frame"]')
    this.outlineSection = element.querySelector('[data-role="outline-section"]')
    this.outlineList = element.querySelector('[data-role="outline-list"]')
    this.outlineEmpty = element.querySelector('[data-role="outline-empty"]')
    this.outlineBody = element.querySelector('[data-role="outline-body"]')
    this.outlineToggle = element.querySelector('[data-role="outline-toggle"]')
    this.outlineMenuAnchor = element.querySelector('[data-role="outline-menu-anchor"]')
    this.outlineMenuButton = element.querySelector('[data-role="outline-menu-toggle"]')
    this.outlineMenu = element.querySelector('[data-role="outline-menu"]')
    this.outlineMenuList = element.querySelector('[data-role="outline-menu-list"]')
    this.outlineMenuEmpty = element.querySelector('[data-role="outline-menu-empty"]')
    this.themeButton = element.querySelector('[data-role="theme-toggle"]')
    this.themeMenu = element.querySelector('[data-role="theme-menu"]')
    this.themeCurrentLabel = element.querySelector('[data-role="theme-current-label"]')
    this.localeButton = element.querySelector('[data-role="locale-toggle"]')
    this.localeMenu = element.querySelector('[data-role="locale-menu"]')
    this.localeCurrentLabel = element.querySelector('[data-role="locale-current-label"]')
    this.exportButton = element.querySelector('[data-role="export-toggle"]')
    this.exportMenu = element.querySelector('[data-role="export-menu"]')
    this.toolbar = element.querySelector('[data-role="toolbar"]')
    this.toolbarToggle = element.querySelector('[data-role="toolbar-toggle"]')
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
    this.translations = parseTranslations(element.dataset.translations)
    this.showControlsLabel = element.dataset.showControlsLabel || window.t("share_view.show_controls")
    this.hideControlsLabel = element.dataset.hideControlsLabel || window.t("share_view.hide_controls")
    this.showToolbarLabel = element.dataset.showToolbarLabel || window.t("share_view.show_toolbar")
    this.hideToolbarLabel = element.dataset.hideToolbarLabel || window.t("share_view.hide_toolbar")
    this.displayPanelExpanded = !this.displayPanel?.classList.contains("hidden")
    this.toolbarCollapsed = element.dataset.toolbarCollapsed === "true"
    this.toolbarHintActive = element.dataset.toolbarHint !== "false"
    this.toolbarHintTimeout = null
    this.exportGroupExpanded = false
    this.baseFontSize = null
    this.outlineEntries = []
    this.activeOutlineId = null
    this.outlineSyncQueued = false
    this.frameScrollTarget = null
    this.outlineCollapsed = false
  }

  connect() {
    installTranslations({
      locale: this.currentLocale,
      translations: this.translations
    })
    applyThemeToRoot(this.currentTheme)
    document.documentElement.lang = this.currentLocale
    this.updateColorSchemeMeta()
    this.renderMenus()
    this.attachEventListeners()
    this.updateDisplays()
    this.applyToolbarState()
    this.applyDisplayPanelState()
    this.applyOutlineState()
    this.startToolbarHint()

    if (this.frame?.contentDocument?.readyState === "complete") {
      this.onFrameLoad()
    }
  }

  disconnect() {
    document.removeEventListener("click", this.boundDocumentClick)
    this.frame?.removeEventListener("load", this.boundFrameLoad)
    this.detachFrameScroll()
    this.themeButton?.removeEventListener("click", this.boundThemeToggle)
    this.themeMenu?.removeEventListener("click", this.boundThemeMenuClick)
    this.localeButton?.removeEventListener("click", this.boundLocaleToggle)
    this.localeMenu?.removeEventListener("click", this.boundLocaleMenuClick)
    this.exportButton?.removeEventListener("click", this.boundExportToggle)
    this.exportMenu?.removeEventListener("click", this.boundExportMenuClick)
    this.toolbarToggle?.removeEventListener("click", this.boundToolbarToggle)
    this.displayToggle?.removeEventListener("click", this.boundDisplayToggle)
    this.outlineList?.removeEventListener("click", this.boundOutlineClick)
    this.outlineMenuList?.removeEventListener("click", this.boundOutlineClick)
    this.outlineToggle?.removeEventListener("click", this.boundOutlineToggle)
    this.outlineMenuButton?.removeEventListener("click", this.boundOutlineMenuToggle)
    if (this.compactToolbarQuery?.removeEventListener && this.boundCompactToolbarChange) {
      this.compactToolbarQuery.removeEventListener("change", this.boundCompactToolbarChange)
    }
    this.clearToolbarHintTimeout()
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
    this.boundOutlineMenuToggle = (event) => this.toggleMenu(event, "outline")
    this.boundToolbarToggle = () => this.toggleToolbar()
    this.boundDisplayToggle = () => this.toggleDisplayPanel()
    this.boundOutlineClick = (event) => this.onOutlineClick(event)
    this.boundOutlineToggle = () => this.toggleOutline()
    this.boundZoomIn = () => this.zoomIn()
    this.boundZoomOut = () => this.zoomOut()
    this.boundWidthIncrease = () => this.increaseWidth()
    this.boundWidthDecrease = () => this.decreaseWidth()
    this.boundFontChange = (event) => this.changeFontFamily(event)
    this.boundFrameScroll = () => this.scheduleOutlineSync()

    document.addEventListener("click", this.boundDocumentClick)
    this.frame?.addEventListener("load", this.boundFrameLoad)
    this.themeButton?.addEventListener("click", this.boundThemeToggle)
    this.themeMenu?.addEventListener("click", this.boundThemeMenuClick)
    this.localeButton?.addEventListener("click", this.boundLocaleToggle)
    this.localeMenu?.addEventListener("click", this.boundLocaleMenuClick)
    this.exportButton?.addEventListener("click", this.boundExportToggle)
    this.exportMenu?.addEventListener("click", this.boundExportMenuClick)
    this.outlineMenuButton?.addEventListener("click", this.boundOutlineMenuToggle)
    this.toolbarToggle?.addEventListener("click", this.boundToolbarToggle)
    this.displayToggle?.addEventListener("click", this.boundDisplayToggle)
    this.outlineList?.addEventListener("click", this.boundOutlineClick)
    this.outlineMenuList?.addEventListener("click", this.boundOutlineClick)
    this.outlineToggle?.addEventListener("click", this.boundOutlineToggle)
    this.element.querySelector('[data-role="zoom-in"]')?.addEventListener("click", this.boundZoomIn)
    this.element.querySelector('[data-role="zoom-out"]')?.addEventListener("click", this.boundZoomOut)
    this.element.querySelector('[data-role="width-increase"]')?.addEventListener("click", this.boundWidthIncrease)
    this.element.querySelector('[data-role="width-decrease"]')?.addEventListener("click", this.boundWidthDecrease)
    this.fontSelect?.addEventListener("change", this.boundFontChange)
    this.compactToolbarQuery = window.matchMedia?.("(max-width: 1023px)") || null
    this.boundCompactToolbarChange = () => this.applyToolbarState()
    this.compactToolbarQuery?.addEventListener?.("change", this.boundCompactToolbarChange)
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
      outline: this.outlineMenu,
      theme: this.themeMenu,
      locale: this.localeMenu,
      export: this.exportMenu
    }[menuName] || null
  }

  buttonFor(menuName) {
    return {
      outline: this.outlineMenuButton,
      theme: this.themeButton,
      locale: this.localeButton,
      export: this.exportButton
    }[menuName] || null
  }

  closeMenus() {
    [this.outlineMenu, this.themeMenu, this.localeMenu, this.exportMenu].forEach((menu) => menu?.classList.add("hidden"))
    ;[this.outlineMenuButton, this.themeButton, this.localeButton, this.exportButton].forEach((button) => button?.setAttribute("aria-expanded", "false"))
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
    window.location.assign(buildLocaleUrl(localeId))
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
    this.rebuildOutline()
  }

  rebuildOutline() {
    this.detachFrameScroll()
    this.outlineEntries = collectOutlineEntries(this.frameDocument)
    this.renderOutline()
    this.attachFrameScroll()
    this.updateActiveOutlineItem({ scrollList: false })
  }

  renderOutline() {
    if (!this.outlineSection || !this.outlineList) return

    ;[this.outlineList, this.outlineMenuList].forEach((list) => list?.replaceChildren())

    const hasOutline = this.outlineEntries.length > 0
    ;[this.outlineEmpty, this.outlineMenuEmpty].forEach((emptyState) => emptyState?.classList.toggle("hidden", hasOutline))
    this.activeOutlineId = null

    if (hasOutline) {
      ;[this.outlineList, this.outlineMenuList].forEach((list) => {
        if (!list) return

        const fragment = document.createDocumentFragment()
        this.outlineEntries.forEach((entry) => {
          fragment.appendChild(this.buildOutlineButton(entry))
        })
        list.appendChild(fragment)
      })
    } else {
      this.closeMenus()
    }

    this.applyOutlineState()
  }

  buildOutlineButton(entry) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "outline-item"
    button.dataset.outlineId = entry.id
    button.dataset.active = "false"
    button.style.setProperty("--outline-level", String(entry.level))
    button.textContent = entry.text
    button.title = entry.text
    return button
  }

  attachFrameScroll() {
    const frameWindow = this.frameWindow
    if (!frameWindow?.addEventListener || !this.boundFrameScroll || this.outlineEntries.length === 0) return

    frameWindow.addEventListener("scroll", this.boundFrameScroll, { passive: true })
    this.frameScrollTarget = frameWindow
  }

  detachFrameScroll() {
    if (!this.frameScrollTarget?.removeEventListener || !this.boundFrameScroll) return

    this.frameScrollTarget.removeEventListener("scroll", this.boundFrameScroll)
    this.frameScrollTarget = null
  }

  scheduleOutlineSync() {
    if (this.outlineSyncQueued) return

    this.outlineSyncQueued = true
    const scheduler = window.requestAnimationFrame || ((callback) => window.setTimeout(callback, 16))
    scheduler(() => {
      this.outlineSyncQueued = false
      this.updateActiveOutlineItem()
    })
  }

  updateActiveOutlineItem({ scrollList = true } = {}) {
    const activeIndex = findActiveOutlineIndex(this.outlineEntries, this.frameWindow)
    const activeId = activeIndex >= 0 ? this.outlineEntries[activeIndex]?.id : null

    this.setActiveOutlineId(activeId, { scrollList })
  }

  setActiveOutlineId(activeId, { scrollList = true } = {}) {
    if (!this.outlineList && !this.outlineMenuList) return

    this.element.querySelectorAll("[data-outline-id]").forEach((button) => {
      const isActive = button.dataset.outlineId === activeId
      button.dataset.active = String(isActive)
      if (isActive) {
        button.setAttribute("aria-current", "true")
        if (scrollList) button.scrollIntoView({ block: "nearest" })
      } else {
        button.removeAttribute("aria-current")
      }
    })

    this.activeOutlineId = activeId
  }

  onOutlineClick(event) {
    const button = event.target.closest("[data-outline-id]")
    if (!button) return

    event.preventDefault()

    const entry = this.outlineEntries.find(({ id }) => id === button.dataset.outlineId)
    if (!entry?.element?.scrollIntoView) return

    entry.element.scrollIntoView({
      behavior: "smooth",
      block: "start"
    })

    this.closeMenus()
    this.setActiveOutlineId(entry.id, { scrollList: false })
  }

  toggleOutline() {
    this.outlineCollapsed = !this.outlineCollapsed
    this.applyOutlineState()
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

  toggleToolbar() {
    if (!this.isCompactToolbarMode()) return

    this.dismissToolbarHint()
    this.toolbarCollapsed = !this.toolbarCollapsed
    if (this.toolbarCollapsed) this.closeMenus()
    this.applyToolbarState()
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

  applyToolbarState() {
    const compactToolbarMode = this.isCompactToolbarMode()
    if (!compactToolbarMode) {
      this.toolbarCollapsed = false
      this.dismissToolbarHint()
    }

    const collapsed = compactToolbarMode && this.toolbarCollapsed
    this.element.dataset.toolbarCollapsed = String(collapsed)
    this.element.dataset.toolbarHint = String(collapsed && this.toolbarHintActive)
    this.toolbar?.setAttribute("aria-hidden", String(collapsed))

    if (this.toolbarToggle) {
      const toggleLabel = collapsed ? this.showToolbarLabel : this.hideToolbarLabel
      this.toolbarToggle.classList.toggle("hidden", !compactToolbarMode)
      this.toolbarToggle.setAttribute("aria-expanded", String(!collapsed))
      this.toolbarToggle.setAttribute("title", toggleLabel)
      this.toolbarToggle.setAttribute("aria-label", toggleLabel)
    }
  }

  startToolbarHint() {
    if (!this.isCompactToolbarMode() || !this.toolbarCollapsed || !this.toolbarHintActive) {
      this.dismissToolbarHint()
      return
    }

    this.element.dataset.toolbarHint = "true"
    this.clearToolbarHintTimeout()
    this.toolbarHintTimeout = window.setTimeout(() => {
      this.toolbarHintActive = false
      this.element.dataset.toolbarHint = "false"
      this.toolbarHintTimeout = null
    }, 3100)
  }

  dismissToolbarHint() {
    this.clearToolbarHintTimeout()
    this.toolbarHintActive = false
    this.element.dataset.toolbarHint = "false"
  }

  clearToolbarHintTimeout() {
    if (!this.toolbarHintTimeout) return

    window.clearTimeout(this.toolbarHintTimeout)
    this.toolbarHintTimeout = null
  }

  applyOutlineState() {
    if (!this.outlineSection) return

    const hasOutline = this.outlineEntries.length > 0
    this.outlineSection.classList.toggle("hidden", !hasOutline)
    this.outlineMenuAnchor?.classList.toggle("hidden", !hasOutline)

    if (!hasOutline) {
      this.outlineMenu?.classList.add("hidden")
      this.outlineMenuButton?.setAttribute("aria-expanded", "false")
      return
    }

    this.outlineSection.dataset.collapsed = String(this.outlineCollapsed)
    this.outlineBody?.classList.toggle("hidden", this.outlineCollapsed)

    if (this.outlineToggle) {
      const toggleLabel = this.outlineCollapsed
        ? window.t("share_view.expand_outline")
        : window.t("share_view.collapse_outline")
      this.outlineToggle.setAttribute("aria-expanded", String(!this.outlineCollapsed))
      this.outlineToggle.setAttribute("title", toggleLabel)
      this.outlineToggle.setAttribute("aria-label", toggleLabel)
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

  isCompactToolbarMode() {
    if (this.compactToolbarQuery) return this.compactToolbarQuery.matches

    return window.innerWidth <= 1023
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
