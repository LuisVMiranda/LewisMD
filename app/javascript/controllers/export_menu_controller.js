import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "button"]
  static values = {
    shareable: { type: Boolean, default: true },
    markdownCopyable: { type: Boolean, default: true }
  }

  static copyItems = [
    { id: "copy-html", key: "copy_note" }
  ]

  static markdownCopyItem = { id: "copy-markdown", key: "copy_markdown" }

  static exportGroupItem = { id: "toggle-export-group", key: "export_files", expandable: true }

  static exportItems = [
    { id: "export-html", key: "export_html" },
    { id: "export-txt", key: "export_txt" },
    { id: "print-pdf", key: "export_pdf" }
  ]

  static shareCreateItems = [
    { id: "create-share-link", key: "create_share_link", divider: true }
  ]

  static shareActiveItems = [
    { id: "copy-share-link", key: "copy_share_link", divider: true },
    { id: "refresh-share-link", key: "refresh_share_link" },
    { id: "disable-share-link", key: "disable_share_link", destructive: true }
  ]

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
    const items = [ ...this.constructor.copyItems ]

    if (this.markdownCopyableValue) {
      items.push(this.constructor.markdownCopyItem)
    }

    items.push(this.constructor.exportGroupItem)

    if (this.exportGroupExpanded) {
      items.push(...this.constructor.exportItems.map((item) => ({ ...item, nested: true })))
    }

    if (this.shareState.shareable) {
      items.push(...(this.shareState.active
        ? this.constructor.shareActiveItems
        : this.constructor.shareCreateItems))
    }

    return items
  }

  renderMenu() {
    if (!this.hasMenuTarget) return

    this.menuTarget.innerHTML = this.menuItems().map((item) => `
      <button
        type="button"
        role="menuitem"
        class="w-full px-3 py-2 text-left text-sm hover:bg-[var(--theme-bg-hover)] flex items-center justify-between gap-2 ${item.divider ? "border-t border-[var(--theme-border)] mt-1 pt-3" : ""} ${item.destructive ? "text-red-600 dark:text-red-400" : ""} ${item.nested ? "pl-7 text-[var(--theme-text-muted)]" : ""}"
        ${item.expandable ? "" : `data-action-id="${item.id}"`}
        data-action="click->export-menu#${item.expandable ? "toggleExportGroup" : "select"}"
      >
        <span>${window.t(`export_menu.${item.key}`)}</span>
        ${item.expandable ? `
          <svg class="w-3 h-3 shrink-0 transition-transform ${this.exportGroupExpanded ? "rotate-180" : ""}" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
        ` : ""}
      </button>
    `).join("")
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
