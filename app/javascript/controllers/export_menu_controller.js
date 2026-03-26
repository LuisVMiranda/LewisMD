import { Controller } from "@hotwired/stimulus"
import {
  buildExportMenuItems,
  COPY_ITEMS,
  EXPORT_GROUP_ITEM,
  EXPORT_ITEMS,
  MARKDOWN_COPY_ITEM,
  renderExportMenuHtml,
  SHARE_ACTIVE_ITEMS,
  SHARE_CREATE_ITEMS
} from "../lib/share_reader/export_menu_helpers.js"

export default class extends Controller {
  static targets = ["menu", "button"]
  static values = {
    shareable: { type: Boolean, default: true },
    markdownCopyable: { type: Boolean, default: true }
  }

  static copyItems = COPY_ITEMS

  static markdownCopyItem = MARKDOWN_COPY_ITEM

  static exportGroupItem = EXPORT_GROUP_ITEM

  static exportItems = EXPORT_ITEMS

  static shareCreateItems = SHARE_CREATE_ITEMS

  static shareActiveItems = SHARE_ACTIVE_ITEMS

  connect() {
    this.shareState = {
      shareable: this.shareableValue,
      active: false,
      url: null
    }
    this.exportGroupExpanded = false

    this.renderMenu()
    this.updateExpandedState()
    this.setupClickOutside()
    this.setupTranslationsListener()
  }

  disconnect() {
    if (this.boundClickOutside) {
      document.removeEventListener("click", this.boundClickOutside)
    }
    if (this.boundTranslationsLoaded) {
      window.removeEventListener("frankmd:translations-loaded", this.boundTranslationsLoaded)
    }
  }

  toggle(event) {
    event.stopPropagation()
    this.menuTarget.classList.toggle("hidden")
    if (this.menuTarget.classList.contains("hidden")) {
      this.exportGroupExpanded = false
      this.renderMenu()
    }
    this.updateExpandedState()
  }

  select(event) {
    const actionId = event.currentTarget.dataset.actionId
    if (!actionId) return

    this.closeMenu()
    this.dispatch("selected", {
      detail: { actionId }
    })
  }

  toggleExportGroup(event) {
    event.stopPropagation()
    this.exportGroupExpanded = !this.exportGroupExpanded
    this.renderMenu()
  }

  closeMenu() {
    this.menuTarget.classList.add("hidden")
    this.exportGroupExpanded = false
    this.renderMenu()
    this.updateExpandedState()
  }

  updateExpandedState() {
    if (!this.hasButtonTarget) return

    this.buttonTarget.setAttribute("aria-expanded", (!this.menuTarget.classList.contains("hidden")).toString())
  }

  setShareState({ shareable = this.shareState.shareable, active = this.shareState.active, url = this.shareState.url } = {}) {
    this.shareState = {
      shareable: Boolean(shareable),
      active: Boolean(active),
      url: url || null
    }
    this.renderMenu()
  }

  menuItems() {
    return buildExportMenuItems({
      markdownCopyable: this.markdownCopyableValue,
      shareState: this.shareState,
      exportGroupExpanded: this.exportGroupExpanded
    })
  }

  renderMenu() {
    if (!this.hasMenuTarget) return

    this.menuTarget.innerHTML = renderExportMenuHtml({
      items: this.menuItems(),
      expanded: this.exportGroupExpanded,
      controllerIdentifier: "export-menu",
      translate: (key) => window.t(key)
    })
  }

  setupClickOutside() {
    this.boundClickOutside = (event) => {
      if (!this.element.contains(event.target)) {
        this.closeMenu()
      }
    }
    document.addEventListener("click", this.boundClickOutside)
  }

  setupTranslationsListener() {
    this.boundTranslationsLoaded = () => {
      this.renderMenu()
    }
    window.addEventListener("frankmd:translations-loaded", this.boundTranslationsLoaded)
  }
}
