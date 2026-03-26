import { Controller } from "@hotwired/stimulus"
import { get, patch } from "@rails/request.js"
import {
  BUILTIN_THEMES,
  LIGHT_THEME_IDS,
  applyThemeToRoot,
  buildThemeUrl,
  renderThemeMenuHtml,
  resolvedThemeId,
  themeIconMarkup,
  themeNameFor
} from "../lib/share_reader/theme_helpers.js"

export default class extends Controller {
  static targets = ["menu", "currentTheme"]
  static values = {
    initial: String,
    persist: { type: Boolean, default: true },
    allowOmarchy: { type: Boolean, default: true },
    queryParam: { type: Boolean, default: false }
  }

  // Built-in themes - Light and Dark first, then alphabetical
  static themes = BUILTIN_THEMES

  // Light themes for Tailwind dark: toggle
  static lightThemes = LIGHT_THEME_IDS

  connect() {
    // Load initial theme from server config
    this.currentThemeId = this.hasInitialValue && this.initialValue ? this.initialValue : null
    this.omarchyThemeName = null
    this.omarchyPollingInterval = null
    this.omarchyAvailable = false

    // Build runtime themes list (copy of static)
    this.runtimeThemes = [...this.constructor.themes]

    // Check omarchy availability, then apply theme and render
    if (this.allowOmarchyValue) {
      this.checkOmarchyAvailability().then(() => {
        this.applyTheme()
        this.renderMenu()
      })
    } else {
      if (this.currentThemeId === "omarchy") {
        this.currentThemeId = "dark"
      }
      this.applyTheme()
      this.renderMenu()
    }

    this.setupClickOutside()
    this.setupConfigListener()
  }

  disconnect() {
    if (this.boundConfigListener) {
      window.removeEventListener("frankmd:config-changed", this.boundConfigListener)
    }
    if (this.boundClickOutside) {
      document.removeEventListener("click", this.boundClickOutside)
    }
    if (this.configSaveTimeout) {
      clearTimeout(this.configSaveTimeout)
    }
    this.stopOmarchyPolling()
  }

  // Listen for config changes (when .fed file is edited)
  setupConfigListener() {
    if (!this.persistValue) return

    this.boundConfigListener = (event) => {
      const { theme } = event.detail
      if (theme && theme !== this.currentThemeId) {
        this.currentThemeId = theme
        this.applyTheme()
        this.renderMenu()
      }
    }
    window.addEventListener("frankmd:config-changed", this.boundConfigListener)
  }

  toggle(event) {
    event.stopPropagation()
    this.menuTarget.classList.toggle("hidden")
  }

  selectTheme(event) {
    const themeId = event.currentTarget.dataset.theme
    this.currentThemeId = themeId
    if (this.persistValue) {
      this.saveThemeConfig(themeId)
    } else {
      this.syncThemeQueryParam(themeId)
    }
    this.applyTheme()
    this.menuTarget.classList.add("hidden")
  }

  // Save theme to server config (debounced)
  saveThemeConfig(themeId) {
    if (!this.persistValue) return

    if (this.configSaveTimeout) {
      clearTimeout(this.configSaveTimeout)
    }

    this.configSaveTimeout = setTimeout(async () => {
      try {
        const response = await patch("/config", {
          body: { theme: themeId },
          responseKind: "json"
        })

        if (!response.ok) {
          console.warn("Failed to save theme config:", await response.text)
        } else {
          // Notify other controllers that config file was modified
          window.dispatchEvent(new CustomEvent("frankmd:config-file-modified"))
        }
      } catch (error) {
        console.warn("Failed to save theme config:", error)
      }
    }, 500)
  }

  applyTheme() {
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
    const themeId = resolvedThemeId(this.currentThemeId, prefersDark)

    if (themeId === "omarchy" && this.allowOmarchyValue) {
      this.applyOmarchyTheme()
      return
    }

    // Switching away from omarchy - clean up
    this.stopOmarchyPolling()
    this.removeOmarchyStyles()

    const themeState = applyThemeToRoot(themeId, document.documentElement, this.constructor.lightThemes)

    this.updateCurrentThemeDisplay(themeId)
    this.updateMenuCheckmarks(themeId)
    this.dispatchThemeChanged(themeState.themeId, themeState.colorScheme)
  }

  async applyOmarchyTheme() {
    try {
      const response = await get("/config/omarchy_theme", { responseKind: "json" })

      if (!response.ok) {
        // Omarchy no longer available - fall back to dark
        this.currentThemeId = "dark"
        this.saveThemeConfig("dark")
        this.applyTheme()
        this.renderMenu()
        return
      }

      const data = await response.json
      this.omarchyThemeName = data.theme_name
      this.injectOmarchyStyles(data.variables)

      // Set data-theme so CSS selectors work
      document.documentElement.setAttribute("data-theme", "omarchy")

      // Toggle dark class based on omarchy theme luminance
      document.documentElement.classList.toggle("dark", data.is_dark)

      this.updateCurrentThemeDisplay("omarchy")
      this.updateMenuCheckmarks("omarchy")
      this.dispatchThemeChanged("omarchy", data.is_dark ? "dark" : "light")

      // Start polling for theme changes
      this.startOmarchyPolling()
    } catch (error) {
      console.warn("Failed to apply Omarchy theme:", error)
      this.currentThemeId = "dark"
      this.saveThemeConfig("dark")
      this.applyTheme()
      this.renderMenu()
    }
  }

  injectOmarchyStyles(variables) {
    let styleEl = document.getElementById("omarchy-theme-vars")
    if (!styleEl) {
      styleEl = document.createElement("style")
      styleEl.id = "omarchy-theme-vars"
      document.head.appendChild(styleEl)
    }

    const cssVars = Object.entries(variables)
      .map(([key, value]) => `  ${key}: ${value};`)
      .join("\n")

    styleEl.textContent = `[data-theme="omarchy"] {\n${cssVars}\n}`
  }

  removeOmarchyStyles() {
    const styleEl = document.getElementById("omarchy-theme-vars")
    if (styleEl) {
      styleEl.remove()
    }
  }

  startOmarchyPolling() {
    if (this.omarchyPollingInterval) return

    this.omarchyPollingInterval = setInterval(async () => {
      try {
        const response = await get("/config/omarchy_theme", { responseKind: "json" })

        if (!response.ok) {
          // Omarchy was removed - fall back
          this.stopOmarchyPolling()
          this.currentThemeId = "dark"
          this.saveThemeConfig("dark")
          this.applyTheme()
          this.renderMenu()
          return
        }

        const data = await response.json
        if (data.theme_name !== this.omarchyThemeName) {
          this.omarchyThemeName = data.theme_name
          this.injectOmarchyStyles(data.variables)
          document.documentElement.classList.toggle("dark", data.is_dark)
          this.dispatchThemeChanged("omarchy", data.is_dark ? "dark" : "light")
        }
      } catch (error) {
        // Silently ignore polling errors
      }
    }, 3000)
  }

  stopOmarchyPolling() {
    if (this.omarchyPollingInterval) {
      clearInterval(this.omarchyPollingInterval)
      this.omarchyPollingInterval = null
    }
    this.omarchyThemeName = null
  }

  async checkOmarchyAvailability() {
    if (!this.allowOmarchyValue) return

    try {
      const response = await get("/config/omarchy_theme", { responseKind: "json" })
      if (response.ok) {
        this.omarchyAvailable = true
        this.runtimeThemes.push({ id: "omarchy", name: "Omarchy", icon: "sync" })
      }
    } catch (error) {
      // Omarchy not available
    }
  }

  updateCurrentThemeDisplay(themeId) {
    if (this.hasCurrentThemeTarget) {
      this.currentThemeTarget.textContent = themeNameFor(themeId, this.runtimeThemes)
    }
  }

  updateMenuCheckmarks(themeId) {
    if (this.hasMenuTarget) {
      this.menuTarget.querySelectorAll("[data-theme]").forEach(el => {
        const checkmark = el.querySelector(".checkmark")
        if (checkmark) {
          checkmark.classList.toggle("opacity-0", el.dataset.theme !== themeId)
        }
      })
    }
  }

  renderMenu() {
    if (!this.hasMenuTarget) return

    const currentTheme = resolvedThemeId(
      this.currentThemeId,
      window.matchMedia("(prefers-color-scheme: dark)").matches
    )

    this.menuTarget.innerHTML = renderThemeMenuHtml({
      themes: this.runtimeThemes,
      currentThemeId: currentTheme,
      action: "click->theme#selectTheme"
    })
  }

  getIcon(iconType) {
    return themeIconMarkup(iconType)
  }

  setupClickOutside() {
    this.boundClickOutside = (event) => {
      if (this.hasMenuTarget && !this.element.contains(event.target)) {
        this.menuTarget.classList.add("hidden")
      }
    }
    document.addEventListener("click", this.boundClickOutside)
  }

  syncThemeQueryParam(themeId) {
    if (!this.queryParamValue) return

    const nextUrl = new URL(buildThemeUrl(themeId, window.location.href))
    window.history.replaceState(window.history.state, "", `${nextUrl.pathname}${nextUrl.search}${nextUrl.hash}`)
  }

  dispatchThemeChanged(themeId, colorScheme) {
    window.dispatchEvent(new CustomEvent("frankmd:theme-changed", {
      detail: {
        theme: themeId,
        colorScheme
      }
    }))
  }
}
