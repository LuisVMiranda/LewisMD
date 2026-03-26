import { Controller } from "@hotwired/stimulus"
import { get, patch } from "@rails/request.js"
import {
  AVAILABLE_LOCALES,
  buildLocaleUrl as buildLocaleUrlForReader,
  localeFlagMarkup,
  localeNameFor,
  renderLocaleMenuHtml
} from "lib/share_reader/locale_helpers"
import {
  dispatchTranslationsLoaded,
  installGlobalTranslationHelper,
  setGlobalTranslations
} from "lib/share_reader/translation_helpers"

if (typeof window !== "undefined") {
  installGlobalTranslationHelper(window)
}

export default class extends Controller {
  static targets = ["menu", "currentLocale"]
  static values = {
    initial: String,
    persist: { type: Boolean, default: true }
  }

  // Available locales
  static locales = AVAILABLE_LOCALES

  connect() {
    // Load initial locale from server config
    this.currentLocaleId = this.hasInitialValue && this.initialValue ? this.initialValue : "en"
    this.translations = null
    this.loadTranslations(this.currentLocaleId)
    this.renderMenu()
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
  }

  // Load translations from server
  async loadTranslations(localeId = this.currentLocaleId) {
    try {
      const response = await get(`/translations?locale=${encodeURIComponent(localeId)}`, { responseKind: "json" })
      if (response.ok) {
        const data = await response.json
        this.translations = data.translations
        this.currentLocaleId = data.locale
        setGlobalTranslations({
          locale: this.currentLocaleId,
          translations: this.translations
        })
        dispatchTranslationsLoaded({
          locale: this.currentLocaleId,
          translations: this.translations
        })
        this.updateDisplay()
      }
    } catch (error) {
      console.warn("Failed to load translations:", error)
    }
  }

  // Listen for config changes (when .fed file is edited)
  setupConfigListener() {
    if (!this.persistValue) return

    this.boundConfigListener = (event) => {
      const { locale } = event.detail
      if (locale && locale !== this.currentLocaleId) {
        this.currentLocaleId = locale
        this.loadTranslations(locale)
        this.renderMenu()
      }
    }
    window.addEventListener("frankmd:config-changed", this.boundConfigListener)
  }

  toggle(event) {
    event.stopPropagation()
    this.menuTarget.classList.toggle("hidden")
  }

  selectLocale(event) {
    const localeId = event.currentTarget.dataset.locale
    if (localeId === this.currentLocaleId) {
      this.menuTarget.classList.add("hidden")
      return
    }
    if (this.persistValue) {
      this.currentLocaleId = localeId
      this.updateDisplay()
      this.renderMenu()
      this.menuTarget.classList.add("hidden")
      this.saveLocaleConfig(localeId)
      return
    }

    this.menuTarget.classList.add("hidden")
    this.navigateToLocale(localeId)
  }

  // Save locale to server config and reload page to apply translations
  async saveLocaleConfig(localeId) {
    if (this.configSaveTimeout) {
      clearTimeout(this.configSaveTimeout)
      this.configSaveTimeout = null
    }

    try {
      await patch("/config", {
        body: { locale: localeId },
        responseKind: "json"
      })
    } catch (error) {
      console.warn("Failed to save locale config:", error)
    }
    // Always reload to apply new locale translations from server
    this.reloadPage()
  }

  reloadPage() {
    window.location.reload()
  }

  navigateToLocale(localeId) {
    window.location.assign(this.buildLocaleUrl(localeId))
  }

  buildLocaleUrl(localeId) {
    return buildLocaleUrlForReader(localeId, window.location.href)
  }

  updateDisplay() {
    if (this.hasCurrentLocaleTarget) {
      this.currentLocaleTarget.textContent = localeNameFor(this.currentLocaleId, this.constructor.locales)
    }

    // Update menu checkmarks
    if (this.hasMenuTarget) {
      this.menuTarget.querySelectorAll("[data-locale]").forEach(el => {
        const checkmark = el.querySelector(".checkmark")
        if (checkmark) {
          checkmark.classList.toggle("opacity-0", el.dataset.locale !== this.currentLocaleId)
        }
      })
    }
  }

  renderMenu() {
    if (!this.hasMenuTarget) return

    this.menuTarget.innerHTML = renderLocaleMenuHtml({
      locales: this.constructor.locales,
      currentLocaleId: this.currentLocaleId,
      action: "click->locale#selectLocale"
    })
  }

  getFlag(flagCode) {
    return localeFlagMarkup(flagCode)
  }

  setupClickOutside() {
    this.boundClickOutside = (event) => {
      if (this.hasMenuTarget && !this.element.contains(event.target)) {
        this.menuTarget.classList.add("hidden")
      }
    }
    document.addEventListener("click", this.boundClickOutside)
  }
}
