import { Controller } from "@hotwired/stimulus"
import { patch } from "@rails/request.js"

export default class extends Controller {
  static targets = ["display"]

  connect() {
    // Default to 100% if not set by user settings
    let savedWidth = 100
    
    // Try to find the app's config initialization
    const configContainer = document.querySelector('[data-controller="editor-config"]')
    if (configContainer && configContainer.dataset.editorConfigTextWidthValue) {
      savedWidth = parseInt(configContainer.dataset.editorConfigTextWidthValue, 10)
    }

    this.currentWidth = savedWidth || 100
    this.saveTimeout = null

    // Ensure it's bounded correctly
    if (this.currentWidth < 30) this.currentWidth = 30
    if (this.currentWidth > 100) this.currentWidth = 100

    this.applyWidth()
    this.updateDisplay()
  }

  increase() {
    if (this.currentWidth < 100) {
      this.currentWidth += 10
      if (this.currentWidth > 100) this.currentWidth = 100
      this.applyWidth()
      this.updateDisplay()
      this.saveWidth()
    }
  }

  decrease() {
    if (this.currentWidth > 30) {
      this.currentWidth -= 10
      if (this.currentWidth < 30) this.currentWidth = 30
      this.applyWidth()
      this.updateDisplay()
      this.saveWidth()
    }
  }

  applyWidth() {
    // Update the CSS variable on the main content container
    const mainContainer = document.getElementById("main-content")
    if (mainContainer) {
      mainContainer.style.setProperty("--user-text-width", `${this.currentWidth}%`)
    }
    
    // Fallback: apply to body to ensure it cascades down globally if needed
    document.body.style.setProperty("--user-text-width", `${this.currentWidth}%`)
  }

  updateDisplay() {
    if (this.hasDisplayTarget) {
      this.displayTarget.textContent = `${this.currentWidth}%`
    }
  }

  saveWidth() {
    if (this.saveTimeout) {
      clearTimeout(this.saveTimeout)
    }

    this.saveTimeout = setTimeout(async () => {
      try {
        await patch("/config", {
          body: { text_width: this.currentWidth },
          responseKind: "json"
        })
      } catch (error) {
        console.warn("Failed to save text width config:", error)
      }
    }, 500)
  }
}
