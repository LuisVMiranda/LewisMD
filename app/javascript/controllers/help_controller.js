import { Controller } from "@hotwired/stimulus"
import {
  EDITOR_EXTRA_SHORTCUT_SECTIONS,
  getEditorExtraShortcutsByGroup
} from "lib/editor_extra_shortcuts"

// Help Controller
// Manages help and about dialogs with tabbed content

export default class extends Controller {
  static targets = [
    "helpDialog",
    "aboutDialog",
    "tabMarkdown",
    "tabShortcuts",
    "tabEditorExtras",
    "panelMarkdown",
    "panelShortcuts",
    "panelEditorExtras"
  ]

  connect() {
    // Setup click-outside-to-close for dialogs
    this.setupDialogClickOutside()
    this.currentTab = "markdown"
    this.renderEditorExtrasPanel()
    this.boundTranslationsLoaded = () => this.renderEditorExtrasPanel()
    window.addEventListener("frankmd:translations-loaded", this.boundTranslationsLoaded)
  }

  disconnect() {
    if (this.boundTranslationsLoaded) {
      window.removeEventListener("frankmd:translations-loaded", this.boundTranslationsLoaded)
    }
  }

  setupDialogClickOutside() {
    const dialogs = [this.helpDialogTarget, this.aboutDialogTarget].filter(d => d)

    dialogs.forEach(dialog => {
      dialog.addEventListener("click", (event) => {
        if (event.target === dialog) {
          dialog.close()
        }
      })
    })
  }

  // Open help dialog
  openHelp() {
    if (this.hasHelpDialogTarget) {
      this.currentTab = "markdown"
      this.updateTabStyles()
      this.helpDialogTarget.showModal()
    }
  }

  // Switch tab from click event
  switchTab(event) {
    const tab = event.currentTarget.dataset.tab
    this.switchToTab(tab)
  }

  // Internal method to switch tabs by name
  switchToTab(tab) {
    if (!this.getTabOrder().includes(tab)) return
    this.currentTab = tab
    this.updateTabStyles()
  }

  // Update tab button and panel visibility
  updateTabStyles() {
    const activeClasses = "bg-[var(--theme-accent)] text-[var(--theme-accent-text)]"
    const inactiveClasses = "hover:bg-[var(--theme-bg-hover)] text-[var(--theme-text-muted)]"

    this.getTabOrder().forEach((tabName) => {
      const tabButton = this.getTabButton(tabName)
      const panel = this.getTabPanel(tabName)
      const isActive = this.currentTab === tabName

      if (tabButton) {
        tabButton.className = `px-3 py-1 text-sm rounded-md ${isActive ? activeClasses : inactiveClasses}`
        tabButton.setAttribute("aria-selected", String(isActive))
        tabButton.setAttribute("tabindex", isActive ? "0" : "-1")
      }

      panel?.classList.toggle("hidden", !isActive)
    })
  }

  // Get ordered list of tab names
  getTabOrder() {
    return ["markdown", "shortcuts", "editor-extras"]
  }

  // Handle arrow key navigation on tab buttons
  onTabKeydown(event) {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return

    event.preventDefault()
    const tabs = this.getTabOrder()
    const currentIndex = tabs.indexOf(this.currentTab)

    let newIndex
    if (event.key === "ArrowRight") {
      newIndex = (currentIndex + 1) % tabs.length
    } else {
      newIndex = (currentIndex - 1 + tabs.length) % tabs.length
    }

    this.switchToTab(tabs[newIndex])
    this.focusTab(tabs[newIndex])
  }

  // Focus the tab button for a given tab name
  focusTab(tabName) {
    this.getTabButton(tabName)?.focus()
  }

  // Handle mouse wheel on tab bar to switch tabs
  onTabWheel(event) {
    event.preventDefault()
    const tabs = this.getTabOrder()
    const currentIndex = tabs.indexOf(this.currentTab)

    let newIndex
    if (event.deltaY > 0 || event.deltaX > 0) {
      // Scroll down/right -> next tab
      newIndex = (currentIndex + 1) % tabs.length
    } else {
      // Scroll up/left -> previous tab
      newIndex = (currentIndex - 1 + tabs.length) % tabs.length
    }

    this.switchToTab(tabs[newIndex])
  }

  // Close help dialog
  closeHelp() {
    if (this.hasHelpDialogTarget) {
      this.helpDialogTarget.close()
    }
  }

  // Open about dialog
  openAbout() {
    if (this.hasAboutDialogTarget) {
      this.aboutDialogTarget.showModal()
    }
  }

  // Close about dialog
  closeAbout() {
    if (this.hasAboutDialogTarget) {
      this.aboutDialogTarget.close()
    }
  }

  // Handle escape key for closing dialogs
  onKeydown(event) {
    if (event.key === "Escape") {
      if (this.hasHelpDialogTarget && this.helpDialogTarget.open) {
        this.helpDialogTarget.close()
      }
      if (this.hasAboutDialogTarget && this.aboutDialogTarget.open) {
        this.aboutDialogTarget.close()
      }
    }
  }

  getTabButton(tabName) {
    switch (tabName) {
      case "markdown":
        return this.hasTabMarkdownTarget ? this.tabMarkdownTarget : null
      case "shortcuts":
        return this.hasTabShortcutsTarget ? this.tabShortcutsTarget : null
      case "editor-extras":
        return this.hasTabEditorExtrasTarget ? this.tabEditorExtrasTarget : null
      default:
        return null
    }
  }

  getTabPanel(tabName) {
    switch (tabName) {
      case "markdown":
        return this.hasPanelMarkdownTarget ? this.panelMarkdownTarget : null
      case "shortcuts":
        return this.hasPanelShortcutsTarget ? this.panelShortcutsTarget : null
      case "editor-extras":
        return this.hasPanelEditorExtrasTarget ? this.panelEditorExtrasTarget : null
      default:
        return null
    }
  }

  renderEditorExtrasPanel() {
    if (!this.hasPanelEditorExtrasTarget) return

    const sections = EDITOR_EXTRA_SHORTCUT_SECTIONS.map((section) => {
      const title = this.translate(section.titleKey, section.defaultTitle)
      const shortcuts = getEditorExtraShortcutsByGroup(section.group)
        .map((shortcut) => `
          <div class="flex justify-between gap-3 text-sm">
            <kbd class="px-1.5 py-0.5 text-xs font-mono bg-[var(--theme-bg-primary)] rounded border border-[var(--theme-border)] whitespace-nowrap">${this.escapeHtml(shortcut.display)}</kbd>
            <span class="text-[var(--theme-text-secondary)] text-right">${this.escapeHtml(this.translate(shortcut.labelKey, shortcut.defaultLabel))}</span>
          </div>
        `)
        .join("")

      return `
        <div class="bg-[var(--theme-bg-tertiary)] rounded-lg p-3">
          <h4 class="text-xs font-semibold text-[var(--theme-text-muted)] uppercase mb-2">${this.escapeHtml(title)}</h4>
          <div class="space-y-1.5 text-sm">
            ${shortcuts}
          </div>
        </div>
      `
    }).join("")

    this.panelEditorExtrasTarget.innerHTML = `
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        ${sections}
      </div>
    `
  }

  translate(key, fallback, options = {}) {
    if (typeof window.t !== "function") return fallback
    const translated = window.t(key, options)
    return translated === key ? fallback : translated
  }

  escapeHtml(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;")
  }
}
