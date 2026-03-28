import { Controller } from "@hotwired/stimulus"
import { computeWordDiff } from "lib/diff_utils"

// AI Diff Controller
// Handles the shared AI diff view, processing overlay, and config notice

export default class extends Controller {
  static targets = [
    "dialog",
    "dialogTitle",
    "configNotice",
    "diffContent",
    "originalText",
    "correctedText",
    "correctedDiff",
    "providerBadge",
    "editToggle",
    "processingOverlay",
    "processingProvider"
  ]

  connect() {
    this.replacementRange = null
    this.defaultTitleKey = "dialogs.ai_diff.title"
    this.setDialogTitleKey(this.defaultTitleKey)
  }

  showConfigNotice() {
    this.replacementRange = null
    this.setDialogTitleKey(this.defaultTitleKey)
    this.hideProviderBadge()
    this.diffContentTarget.classList.add("hidden")
    this.diffContentTarget.classList.remove("flex")
    this.configNoticeTarget.classList.remove("hidden")
    this.dialogTarget.showModal()
  }

  startProcessing(providerLabel = "AI") {
    this.dispatch("processing-started")

    if (this.hasProcessingProviderTarget) {
      this.processingProviderTarget.textContent = providerLabel
    }

    if (this.hasProcessingOverlayTarget) {
      this.processingOverlayTarget.classList.remove("hidden")
    }
  }

  stopProcessing() {
    if (this.hasProcessingOverlayTarget) {
      this.processingOverlayTarget.classList.add("hidden")
    }

    this.dispatch("processing-ended")
  }

  cleanup() {
    this.stopProcessing()
  }

  close() {
    this.dialogTarget.close()
  }

  openWithResponse(original, corrected, provider, model, range = null, titleKey = this.defaultTitleKey) {
    this.replacementRange = range
    this.setDialogTitleKey(titleKey)
    this.configNoticeTarget.classList.add("hidden")
    this.diffContentTarget.classList.remove("hidden")
    this.diffContentTarget.classList.add("flex")

    if (this.hasProviderBadgeTarget && provider && model) {
      this.providerBadgeTarget.textContent = `${provider}: ${model}`
      this.providerBadgeTarget.classList.remove("hidden")
    } else {
      this.hideProviderBadge()
    }

    const diff = computeWordDiff(original, corrected)
    this.originalTextTarget.innerHTML = this.renderDiffOriginal(diff)
    this.correctedDiffTarget.innerHTML = this.renderDiffCorrected(diff)
    this.correctedTextTarget.value = corrected

    this.correctedDiffTarget.classList.remove("hidden")
    this.correctedTextTarget.classList.add("hidden")
    if (this.hasEditToggleTarget) {
      this.editToggleTarget.textContent = window.t("common.edit")
    }

    this.dialogTarget.showModal()
  }

  openWithCustomResponse(original, corrected, provider, model, range = null, titleKey = this.defaultTitleKey) {
    this.openWithResponse(original, corrected, provider, model, range, titleKey)
  }

  toggleEditMode() {
    const isEditing = !this.correctedTextTarget.classList.contains("hidden")

    if (isEditing) {
      this.correctedTextTarget.classList.add("hidden")
      this.correctedDiffTarget.classList.remove("hidden")
      this.editToggleTarget.textContent = window.t("common.edit")
    } else {
      this.correctedDiffTarget.classList.add("hidden")
      this.correctedTextTarget.classList.remove("hidden")
      this.editToggleTarget.textContent = window.t("preview.title")
      this.correctedTextTarget.focus()
    }
  }

  accept() {
    const correctedText = this.correctedTextTarget.value
    this.dispatch("accepted", { detail: { correctedText, range: this.replacementRange } })
    this.replacementRange = null
    this.close()
  }

  renderDiffOriginal(diff) {
    let html = ""
    for (const item of diff) {
      const escaped = this.escapeHtml(item.value)
      if (item.type === "equal") {
        html += `<span class="ai-diff-equal">${escaped}</span>`
      } else if (item.type === "delete") {
        html += `<span class="ai-diff-del">${escaped}</span>`
      }
    }
    return html
  }

  renderDiffCorrected(diff) {
    let html = ""
    for (const item of diff) {
      const escaped = this.escapeHtml(item.value)
      if (item.type === "equal") {
        html += `<span class="ai-diff-equal">${escaped}</span>`
      } else if (item.type === "insert") {
        html += `<span class="ai-diff-add">${escaped}</span>`
      }
    }
    return html
  }

  hideProviderBadge() {
    if (!this.hasProviderBadgeTarget) return

    this.providerBadgeTarget.textContent = ""
    this.providerBadgeTarget.classList.add("hidden")
  }

  setDialogTitleKey(key) {
    if (!this.hasDialogTitleTarget) return

    this.dialogTitleTarget.textContent = window.t(key)
  }

  escapeHtml(text) {
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;")
  }
}
