import { Controller } from "@hotwired/stimulus"
import { escapeHtml } from "lib/text_utils"

export default class extends Controller {
  static targets = ["section", "list", "empty"]

  connect() {
    this.items = []
    this.visible = false
    this.activeLine = null
    this._lastStructureSignature = null
    this.hide()
  }

  update({ items = [], visible = true } = {}) {
    this.items = items
    this.visible = visible

    const nextSignature = JSON.stringify({ items, visible })
    if (nextSignature === this._lastStructureSignature) {
      this.updateVisibility()
      this.updateActiveState()
      return
    }

    this._lastStructureSignature = nextSignature
    this.render()
  }

  hide() {
    this.items = []
    this.visible = false
    this.activeLine = null
    this._lastStructureSignature = JSON.stringify({ items: [], visible: false })
    this.render()
  }

  setActiveLine(lineNumber) {
    this.activeLine = Number.isInteger(lineNumber) ? lineNumber : null
    this.updateActiveState()
  }

  select(event) {
    const lineNumber = Number.parseInt(event.currentTarget.dataset.line, 10)
    if (!Number.isInteger(lineNumber)) return

    this.dispatch("selected", {
      detail: { lineNumber }
    })
  }

  render() {
    this.updateVisibility()

    if (!this.visible) {
      this.listTarget.innerHTML = ""
      this.emptyTarget.classList.add("hidden")
      return
    }

    const hasItems = this.items.length > 0
    this.emptyTarget.classList.toggle("hidden", hasItems)

    if (!hasItems) {
      this.listTarget.innerHTML = ""
      return
    }

    this.listTarget.innerHTML = this.items.map((item) => `
      <button
        type="button"
        class="outline-item"
        data-action="click->outline#select"
        data-line="${item.line}"
        data-outline-level="${item.level}"
        style="--outline-level:${item.level};"
      >${escapeHtml(item.text)}</button>
    `).join("")

    this.updateActiveState()
  }

  updateVisibility() {
    this.sectionTarget.classList.toggle("hidden", !this.visible)
  }

  updateActiveState() {
    if (!this.hasListTarget) return

    const activeLine = this.findActiveItemLine()
    this.listTarget.querySelectorAll("[data-line]").forEach((item) => {
      const itemLine = Number.parseInt(item.dataset.line, 10)
      item.dataset.active = itemLine === activeLine ? "true" : "false"
    })
  }

  findActiveItemLine() {
    if (!Number.isInteger(this.activeLine) || this.items.length === 0) return null

    let activeItem = null
    for (const item of this.items) {
      if (item.line <= this.activeLine) {
        activeItem = item
      } else {
        break
      }
    }

    return activeItem?.line ?? this.items[0]?.line ?? null
  }
}
