import { Controller } from "@hotwired/stimulus"
import { computeWordDiff } from "lib/diff_utils"
import { escapeHtml } from "lib/text_utils"

export default class extends Controller {
  static targets = ["dialog", "serverText", "backupText", "backupTimestamp"]

  open({ path, serverContent, backupContent, backupTimestamp }) {
    this._path = path
    this._backupContent = backupContent

    const diff = computeWordDiff(serverContent, backupContent)
    this.serverTextTarget.innerHTML = this.renderDiffOriginal(diff)
    this.backupTextTarget.innerHTML = this.renderDiffCorrected(diff)

    if (this.hasBackupTimestampTarget) {
      const date = new Date(backupTimestamp)
      this.backupTimestampTarget.textContent = date.toLocaleString()
    }

    this.dispatch("opened", {
      detail: { path: this._path }
    })
    this.dialogTarget.showModal()
  }

  acceptServer() {
    this.dispatch("resolved", { detail: { source: "server" } })
    this.dialogTarget.close()
  }

  acceptBackup() {
    this.dispatch("resolved", { detail: { source: "backup", content: this._backupContent } })
    this.dialogTarget.close()
  }

  renderDiffOriginal(diff) {
    let html = ""
    for (const item of diff) {
      const escaped = escapeHtml(item.value)
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
      const escaped = escapeHtml(item.value)
      if (item.type === "equal") {
        html += `<span class="ai-diff-equal">${escaped}</span>`
      } else if (item.type === "insert") {
        html += `<span class="ai-diff-add">${escaped}</span>`
      }
    }
    return html
  }
}
