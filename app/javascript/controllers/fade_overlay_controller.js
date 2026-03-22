import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay"]

  connect() {
    this.timeout = null
    this.showTime = 2000 // 2 seconds of inactivity before fading out

    // Bind pointer handlers so we can add/remove them safely
    this.boundPointerMove = this._onWindowPointerMove.bind(this)
    this.boundOverleaveHide = this._onOverlayLeave.bind(this)
  }

  disconnect() {
    if (this.timeout) clearTimeout(this.timeout)
    window.removeEventListener("pointermove", this.boundPointerMove)
  }

  // Called from data-action="pointermove@window->fade-overlay#onPointerMove"
  // Only respond when Reading Mode is active
  onPointerMove() {
    if (!document.body.classList.contains("reading-mode-active")) {
      this.hide()
      return
    }
    this.show()
    this._resetHideTimer()
  }

  _resetHideTimer() {
    if (this.timeout) clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      // Only hide when pointer is NOT over the overlay itself
      if (!this.overlayTarget.matches(":hover")) {
        this.hide()
      }
    }, this.showTime)
  }

  show() {
    this.overlayTarget.classList.remove("opacity-0", "pointer-events-none")
    this.overlayTarget.classList.add("opacity-100", "pointer-events-auto")
  }

  hide() {
    this.overlayTarget.classList.add("opacity-0", "pointer-events-none")
    this.overlayTarget.classList.remove("opacity-100", "pointer-events-auto")
  }
}
