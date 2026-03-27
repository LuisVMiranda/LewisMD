import { Controller } from "@hotwired/stimulus"
import { destroy, get, patch, post } from "@rails/request.js"

const SECRET_FIELDS = [
  "share_remote_api_token",
  "share_remote_signing_secret",
  "share_remote_alert_webhook_secret"
]

export default class extends Controller {
  static targets = [
    "dialog",
    "form",
    "statusPanel",
    "feedback",
    "saveButton",
    "recheckButton",
    "deleteButton"
  ]

  connect() {
    this.settings = {}
    this.status = {}
    this.loading = false
  }

  async open() {
    if (!this.hasDialogTarget) return

    this.dialogTarget.showModal()
    await this.loadSettings()
  }

  close() {
    if (this.hasDialogTarget) {
      this.dialogTarget.close()
    }
  }

  onDialogClick(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }

  onKeydown(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }

  onBackendChanged() {
    this.updateActionAvailability()
  }

  async save() {
    await this.withLoading(async () => {
      const response = await patch("/shares/admin", {
        body: this.serializeForm(),
        responseKind: "json"
      })
      const data = await this.parseJsonResponse(response, this.translate("errors.failed_to_save", "Failed to save."))
      this.applyPayload(data)
      this.showAppMessage(data.message || this.translate("share_management.settings_saved", "Share API settings saved."))
    })
  }

  async recheck() {
    await this.withLoading(async () => {
      const response = await post("/shares/admin/recheck", {
        responseKind: "json"
      })
      const data = await this.parseJsonResponse(response, this.translate("share_management.recheck_failed", "Couldn't refresh Share API status."))
      this.applyPayload(data)
      this.showAppMessage(data.message || this.translate("share_management.recheck_complete", "Share API status refreshed."))
    })
  }

  async deleteAllShares() {
    const confirmed = window.confirm(
      this.translate(
        "confirm.delete_all_shared_notes",
        "Delete all published remote shares?\n\nThis wipes every shared note on the remote API without restarting it."
      )
    )
    if (!confirmed) return

    await this.withLoading(async () => {
      const response = await destroy("/shares/admin", { responseKind: "json" })
      const data = await this.parseJsonResponse(response, this.translate("share_management.delete_failed", "Couldn't delete the published remote shares."))
      this.applyPayload(data)
      this.showAppMessage(data.message || this.translate("share_management.bulk_delete_success", "Deleted the published remote shares."))
      this.dispatch("shares-cleared", {
        detail: {
          deleted: true,
          deletedCount: data.deleted_count || 0
        }
      })
    })
  }

  async loadSettings() {
    await this.withLoading(async () => {
      const response = await get("/shares/admin", { responseKind: "json" })
      const data = await this.parseJsonResponse(response, this.translate("share_management.load_failed", "Couldn't load Share API settings."))
      this.applyPayload(data)
    }, {
      feedback: this.translate("share_management.loading", "Loading Share API settings...")
    })
  }

  async withLoading(work, { feedback = null } = {}) {
    this.loading = true
    this.updateActionAvailability()
    if (feedback) {
      this.setFeedback(feedback)
    }

    try {
      await work()
    } catch (error) {
      this.setFeedback(error.message || this.translate("status.share_failed", "Failed to update shared link."), true)
      this.showAppMessage(error.message || this.translate("status.share_failed", "Failed to update shared link."), true)
    } finally {
      this.loading = false
      this.updateActionAvailability()
    }
  }

  applyPayload(payload) {
    this.settings = payload.settings || {}
    this.status = payload.status || {}
    this.populateForm()
    this.renderStatus()
    this.updateActionAvailability()

    if (payload.message) {
      this.setFeedback(payload.message)
    } else {
      this.setFeedback(this.translate("share_management.ready", "Adjust settings, recheck the connection, or clear published remote shares."))
    }
  }

  populateForm() {
    if (!this.hasFormTarget) return

    Array.from(this.formTarget.elements).forEach((element) => {
      const { name, type } = element
      if (!name) return

      if (type === "checkbox") {
        element.checked = Boolean(this.settings[name])
        return
      }

      if (SECRET_FIELDS.includes(name)) {
        element.value = ""
        element.placeholder = this.settings[`${name}_configured`]
          ? this.translate("share_management.secret_configured", "Configured")
          : this.translate("share_management.secret_not_configured", "Not configured")
        return
      }

      element.value = this.settings[name] ?? ""
    })
  }

  serializeForm() {
    if (!this.hasFormTarget) return {}

    return Array.from(this.formTarget.elements).reduce((payload, element) => {
      const { name, type } = element
      if (!name || element.disabled) return payload

      if (type === "checkbox") {
        payload[name] = element.checked
        return payload
      }

      payload[name] = element.value
      return payload
    }, {})
  }

  renderStatus() {
    if (!this.hasStatusPanelTarget) return

    const backend = this.status.backend || this.settings.share_backend || "local"
    const capabilities = this.status.capabilities || {}
    const capabilityList = Object.entries(capabilities)
      .filter(([, enabled]) => Boolean(enabled))
      .map(([key]) => key.replaceAll("_", " "))
      .join(", ")

    const rows = [
      [ this.translate("share_management.status.backend", "Backend"), this.escapeHtml(backend) ],
      [ this.translate("share_management.status.public_base", "Public base"), this.escapeHtml(this.status.public_base || this.settings.share_remote_public_base || "—") ],
      [ this.translate("share_management.status.reachable", "Reachable"), this.booleanLabel(this.status.reachable) ],
      [ this.translate("share_management.status.admin", "Admin features"), this.booleanLabel(this.status.admin_enabled) ],
      [ this.translate("share_management.status.share_count", "Published shares"), this.valueLabel(this.status.remote_share_count) ],
      [ this.translate("share_management.status.storage_writable", "Storage writable"), this.booleanLabel(this.status.storage_writable) ],
      [ this.translate("share_management.status.capabilities", "Capabilities"), this.escapeHtml(capabilityList || "—") ],
      [ this.translate("share_management.status.message", "Message"), this.escapeHtml(this.status.error || this.status.message || "—") ]
    ]

    this.statusPanelTarget.innerHTML = `
      <dl class="grid gap-3 md:grid-cols-2">
        ${rows.map(([label, value]) => `
          <div class="rounded border border-[var(--theme-border)] bg-[var(--theme-bg-primary)] px-3 py-2">
            <dt class="text-[11px] uppercase tracking-wide text-[var(--theme-text-muted)]">${label}</dt>
            <dd class="mt-1 text-sm text-[var(--theme-text-primary)]">${value}</dd>
          </div>
        `).join("")}
      </dl>
    `
  }

  updateActionAvailability() {
    const remoteEnabled = this.currentBackend() === "remote"
    const adminSupported = Boolean(this.status?.capabilities?.admin_bulk_delete)

    if (this.hasSaveButtonTarget) {
      this.saveButtonTarget.disabled = this.loading
      this.saveButtonTarget.classList.toggle("opacity-60", this.loading)
    }

    if (this.hasRecheckButtonTarget) {
      this.recheckButtonTarget.disabled = this.loading || !remoteEnabled
      this.recheckButtonTarget.classList.toggle("opacity-60", this.recheckButtonTarget.disabled)
    }

    if (this.hasDeleteButtonTarget) {
      this.deleteButtonTarget.disabled = this.loading || !remoteEnabled || !adminSupported
      this.deleteButtonTarget.classList.toggle("opacity-60", this.deleteButtonTarget.disabled)
    }
  }

  currentBackend() {
    return this.hasFormTarget
      ? this.formTarget.elements.namedItem("share_backend")?.value || "local"
      : (this.settings.share_backend || "local")
  }

  setFeedback(message, error = false) {
    if (!this.hasFeedbackTarget) return

    this.feedbackTarget.textContent = message
    this.feedbackTarget.classList.toggle("text-red-500", error)
    this.feedbackTarget.classList.toggle("text-[var(--theme-text-muted)]", !error)
  }

  booleanLabel(value) {
    if (value === null || value === undefined) return "—"
    return value
      ? this.translate("share_management.yes", "Yes")
      : this.translate("share_management.no", "No")
  }

  valueLabel(value) {
    if (value === null || value === undefined || value === "") return "—"
    return this.escapeHtml(String(value))
  }

  escapeHtml(value) {
    const div = document.createElement("div")
    div.textContent = value == null ? "" : String(value)
    return div.innerHTML || "—"
  }

  async parseJsonResponse(response, fallbackMessage) {
    const data = await response.json
    if (response.ok && !data.error) return data

    throw new Error(data.error || fallbackMessage || this.translate("status.share_failed", "Failed to update shared link."))
  }

  showAppMessage(message, error = false) {
    const appController = this.getAppController()
    appController?.showTemporaryMessage?.(message, 3500, error)
  }

  getAppController() {
    const appElement = document.querySelector('[data-controller~="app"]')
    return appElement ? this.application.getControllerForElementAndIdentifier(appElement, "app") : null
  }

  translate(key, fallback, vars = {}) {
    const value = typeof window.t === "function" ? window.t(key, vars) : key
    return !value || value === key ? fallback : value
  }
}
