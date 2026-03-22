import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["rightPane"]

  connect() {
    this.isDragging = false
    this.minPercentage = 20
    this.maxPercentage = 70 // Don't let preview exceed 70%
    
    this.onPointerMove = this.onPointerMove.bind(this)
    this.onPointerUp = this.onPointerUp.bind(this)
    
    // Look for saved config
    const configContainer = document.querySelector('[data-controller="editor-config"]')
    if (configContainer && configContainer.dataset.editorConfigPreviewWidthValue) {
      const savedWidth = parseFloat(configContainer.dataset.editorConfigPreviewWidthValue)
      if (savedWidth) {
        this.applyWidth(savedWidth)
      }
    }
  }

  startDrag(event) {
    event.preventDefault()
    this.isDragging = true
    
    window.addEventListener("pointermove", this.onPointerMove)
    window.addEventListener("pointerup", this.onPointerUp)
    
    document.body.style.cursor = "col-resize"
    document.body.style.userSelect = "none"
  }

  onPointerMove(event) {
    if (!this.isDragging) return
    
    const containerRect = this.element.getBoundingClientRect()
    
    // Pixel based calculation first
    let newRightWidth = containerRect.right - event.clientX
    
    // Constraints Calculation
    const minRightWidth = containerRect.width * 0.20 // Minimum 20%
    const maxRightWidth = containerRect.width * 0.70 // Maximum 70%
    const minLeftWidth = 550 // Pixel limit to guarantee the Toolbar never collapses under the Preview panel
    
    // Clamp Constraints safely
    if (newRightWidth < minRightWidth) newRightWidth = minRightWidth
    if (newRightWidth > maxRightWidth) newRightWidth = maxRightWidth
    if (containerRect.width - newRightWidth < minLeftWidth) {
        newRightWidth = containerRect.width - minLeftWidth
    }
    
    // Dispatch mathematically sound percentage scaling
    let rightWidthPct = (newRightWidth / containerRect.width) * 100
    this.applyWidth(rightWidthPct)
  }

  onPointerUp(event) {
    this.isDragging = false
    window.removeEventListener("pointermove", this.onPointerMove)
    window.removeEventListener("pointerup", this.onPointerUp)
    
    document.body.style.cursor = ""
    document.body.style.userSelect = ""
    
    // Save state if needed 
    // this.saveWidth(this.currentWidthPct)
  }

  applyWidth(percentage) {
    this.currentWidthPct = percentage
    if (this.hasRightPaneTarget) {
      this.rightPaneTarget.style.setProperty("--preview-width", `${percentage}%`)
    }
  }
}
