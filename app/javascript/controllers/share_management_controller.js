import { Controller } from "@hotwired/stimulus"
import { destroy, get, patch, post } from "@rails/request.js"

const SECRET_FIELDS = [
  "share_remote_api_token",
  "share_remote_signing_secret",
  "share_remote_alert_webhook_secret"
]

const TAB_NAMES = [ "status", "connection", "publishing" ]

export default class extends Controller {
  static targets = [
    "dialog",
    "form",
    "statusPanel",
    "feedback",
    "saveButton",
    "recheckButton",
    "deleteButton",
    "tabButton",
    "tabPanel",
    "publishedLoading",
    "publishedEmpty",
    "publishedList"
  ]

  connect() {
    this.settings = {}
    this.status = {}
    this.loading = false
    this.activeTab = "status"
    this.publishedShares = []
    this.publishedSharesLoaded = false
    this.publishedSharesLoading = false
    this.publishedSharesError = null
    this.renderTabs()
    this.renderPublishedShares()
  }

  async open() {
    if (!this.hasDialogTarget) return

    this.activeTab = "status"
    this.publishedSharesLoaded = false
    this.publishedShares = []
    this.publishedSharesError = null
    this.renderTabs()
    this.renderPublishedShares()
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

  async switchTab(event) {
    const nextTab = event.currentTarget.dataset.tab
    if (!TAB_NAMES.includes(nextTab)) return

    this.activeTab = nextTab
    this.renderTabs()

    if (nextTab === "publishing") {
      await this.loadPublishedShares()
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
      this.publishedSharesLoaded = false
      if (this.activeTab === "publishing") {
        await this.loadPublishedShares(true)
      }
      this.showAppMessage(data.message || this.translate("share_management.bulk_delete_success", "Deleted the published remote shares."))
      this.dispatch("shares-cleared", {
        detail: {
          deleted: true,
          deletedCount: data.deleted_count || 0
        }
      })
    })
  }

  async copyPublishedShare(event) {
    event.stopPropagation()
    const share = this.findPublishedShare(event.currentTarget.dataset.token)
    if (!share?.url) return

    const success = this.translate("status.share_link_copied", "Shared link copied.")
    const failure = this.translate("status.share_failed", "Failed to update shared link.")

    const copied = await this.copyTextToClipboard(share.url, {
      successMessage: success,
      failureMessage: failure
    })

    if (!copied) {
      this.showAppMessage(failure, true)
    }
  }

  async deletePublishedShare(event) {
    event.stopPropagation()

    const share = this.findPublishedShare(event.currentTarget.dataset.token)
    if (!share) return

    const confirmed = window.confirm(
      this.translate(
        "confirm.delete_published_note",
        "Delete this published note?",
        { title: share.title || share.path || share.token }
      )
    )
    if (!confirmed) return

    await this.withLoading(async () => {
      const response = await destroy(`/shares/admin/published/${encodeURIComponent(share.token)}`, {
        responseKind: "json"
      })
      const data = await this.parseJsonResponse(
        response,
        this.translate("share_management.delete_published_failed", "Couldn't delete the published note.")
      )

      this.publishedShares = this.publishedShares.filter((row) => row.token !== share.token)
      this.renderPublishedShares()
      this.setFeedback(data.message || this.translate("share_management.published_deleted", "Published note deleted."))
      this.showAppMessage(data.message || this.translate("share_management.published_deleted", "Published note deleted."))
      this.dispatch("share-deleted", {
        detail: {
          token: share.token,
          path: share.path,
          backend: share.backend,
          noteIdentifier: share.note_identifier || null
        }
      })
    })
  }

  openPublishedShare(event) {
    const share = this.findPublishedShare(event.currentTarget.dataset.token)
    if (!share) return

    if (share.missing_locally || !share.path) {
      this.showAppMessage(
        this.translate(
          "share_management.published_missing_locally",
          "This published note no longer exists locally."
        ),
        true
      )
      return
    }

    this.dispatch("open-note", {
      detail: {
        path: share.path
      }
    })
    this.close()
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

  async loadPublishedShares(force = false) {
    if (this.publishedSharesLoading) return
    if (this.publishedSharesLoaded && !force) return

    this.publishedSharesLoading = true
    this.publishedSharesError = null
    this.renderPublishedShares()

    try {
      const response = await get("/shares/admin/published", { responseKind: "json" })
      const data = await this.parseJsonResponse(response, this.translate("share_management.published_load_failed", "Couldn't load the published notes overview."))
      this.publishedShares = Array.isArray(data.published_shares) ? data.published_shares : []
      this.publishedSharesLoaded = true
    } catch (error) {
      this.publishedShares = []
      this.publishedSharesLoaded = false
      this.publishedSharesError = error.message
      this.setFeedback(error.message, true)
      this.showAppMessage(error.message, true)
    } finally {
      this.publishedSharesLoading = false
      this.renderPublishedShares()
    }
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
      this.setFeedback(this.defaultFeedbackMessage())
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

    const message = this.status.error || this.status.message || "-"

    const rows = [
      [ this.translate("share_management.status.backend", "Backend"), this.escapeHtml(backend) ],
      [ this.translate("share_management.status.public_base", "Public base"), this.escapeHtml(this.status.public_base || this.settings.share_remote_public_base || "-") ],
      [ this.translate("share_management.status.reachable", "Reachable"), this.reachableLabel(this.status.reachable) ],
      [ this.translate("share_management.status.admin", "Admin features"), this.booleanLabel(this.status.admin_enabled) ],
      [ this.translate("share_management.status.local_default_expiry", "Local default expiry"), this.expirationLabel(this.status.local_default_expiration_days) ],
      [ this.translate("share_management.status.remote_max_expiry", "Remote max expiry"), this.expirationLabel(this.status.remote_max_expiration_days) ],
      [ this.translate("share_management.status.share_count", "Published shares"), this.valueLabel(this.status.remote_share_count) ],
      [ this.translate("share_management.status.storage_writable", "Storage writable"), this.booleanLabel(this.status.storage_writable) ],
      [ this.translate("share_management.status.capabilities", "Capabilities"), this.escapeHtml(capabilityList || "-") ],
      [ this.translate("share_management.status.message", "Message"), this.escapeHtml(message) ]
    ]
    const warnings = Array.isArray(this.status.warnings) ? this.status.warnings : []

    this.statusPanelTarget.innerHTML = `
      <div class="space-y-3">
        <dl class="grid gap-3 md:grid-cols-2">
          ${rows.map(([label, value]) => `
            <div class="rounded border border-[var(--theme-border)] bg-[var(--theme-bg-primary)] px-3 py-2">
              <dt class="text-[11px] uppercase tracking-wide text-[var(--theme-text-muted)]">${label}</dt>
              <dd class="mt-1 text-sm text-[var(--theme-text-primary)]">${value}</dd>
            </div>
          `).join("")}
        </dl>
        ${this.renderWarningCards(warnings)}
      </div>
    `
  }

  renderTabs() {
    this.tabButtonTargets.forEach((button) => {
      const active = button.dataset.tab === this.activeTab
      button.dataset.active = active.toString()
      button.classList.toggle("bg-[var(--theme-bg-primary)]", active)
      button.classList.toggle("text-[var(--theme-text-primary)]", active)
      button.classList.toggle("border-[var(--theme-border)]", active)
      button.classList.toggle("text-[var(--theme-text-muted)]", !active)
      button.classList.toggle("bg-transparent", !active)
    })

    this.tabPanelTargets.forEach((panel) => {
      panel.classList.toggle("hidden", panel.dataset.tabPanel !== this.activeTab)
    })

    if (this.hasSaveButtonTarget) {
      this.saveButtonTarget.classList.toggle("hidden", this.activeTab !== "connection")
    }
    if (this.hasRecheckButtonTarget) {
      this.recheckButtonTarget.classList.toggle("hidden", this.activeTab !== "status")
    }
    if (this.hasDeleteButtonTarget) {
      this.deleteButtonTarget.classList.toggle("hidden", this.activeTab !== "status")
    }
  }

  renderPublishedShares() {
    if (!this.hasPublishedLoadingTarget || !this.hasPublishedEmptyTarget || !this.hasPublishedListTarget) return

    this.publishedLoadingTarget.classList.toggle("hidden", !this.publishedSharesLoading)
    const hasShares = this.publishedShares.length > 0
    const showEmpty = !this.publishedSharesLoading && !hasShares
    this.publishedEmptyTarget.classList.toggle("hidden", !showEmpty)
    this.publishedListTarget.classList.toggle("hidden", !hasShares)

    if (showEmpty) {
      this.publishedEmptyTarget.textContent = this.publishedSharesError ||
        this.translate("share_management.published_empty", "No published notes were found.")
    }

    if (!hasShares) {
      this.publishedListTarget.innerHTML = ""
      return
    }

    this.publishedListTarget.innerHTML = `
      <div class="space-y-3">
        ${this.publishedShares.map((share) => `
          <div
            class="w-full rounded-lg border border-[var(--theme-border)] bg-[var(--theme-bg-primary)] px-4 py-3 text-left hover:bg-[var(--theme-bg-hover)]"
            role="button"
            tabindex="0"
            data-token="${this.escapeHtml(share.token)}"
            data-action="click->share-management#openPublishedShare"
          >
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div class="min-w-0 flex-1">
                <div class="flex flex-wrap items-center gap-2">
                  <span class="font-medium text-[var(--theme-text-primary)]">${this.escapeHtml(share.title || "Untitled")}</span>
                  <span class="rounded-full border border-[var(--theme-border)] px-2 py-0.5 text-[11px] uppercase tracking-wide text-[var(--theme-text-muted)]">${this.escapeHtml(share.backend)}</span>
                  ${share.stale ? `<span class="rounded-full border border-red-500/30 px-2 py-0.5 text-[11px] uppercase tracking-wide text-red-600 dark:text-red-400">${this.escapeHtml(this.translate("share_management.published_stale", "Stale"))}</span>` : ""}
                  ${share.missing_locally ? `<span class="rounded-full border border-amber-500/30 px-2 py-0.5 text-[11px] uppercase tracking-wide text-amber-700 dark:text-amber-300">${this.escapeHtml(this.translate("share_management.published_missing", "Missing locally"))}</span>` : ""}
                </div>
                <p class="mt-1 truncate text-xs text-[var(--theme-text-muted)]">${this.escapeHtml(share.path || "-")}</p>
                <div class="mt-2 grid gap-1 text-xs text-[var(--theme-text-muted)] md:grid-cols-2">
                  <span>${this.escapeHtml(this.translate("share_management.published_uuid", "UUID"))}: ${this.escapeHtml(share.note_identifier || "-")}</span>
                  <span>${this.escapeHtml(this.translate("share_management.published_date", "Published"))}: ${this.escapeHtml(this.formatTimestamp(share.created_at))}</span>
                </div>
              </div>
              <div class="flex shrink-0 items-center gap-2">
                <button
                  type="button"
                  class="rounded border border-[var(--theme-border)] px-3 py-1.5 text-xs text-[var(--theme-text-secondary)] hover:bg-[var(--theme-bg-hover)]"
                  data-token="${this.escapeHtml(share.token)}"
                  data-action="click->share-management#copyPublishedShare"
                >${this.escapeHtml(this.translate("share_management.copy_link", "Copy Link"))}</button>
                <button
                  type="button"
                  class="rounded border border-red-500/30 px-3 py-1.5 text-xs text-red-600 dark:text-red-400 hover:bg-red-500/10"
                  data-token="${this.escapeHtml(share.token)}"
                  data-action="click->share-management#deletePublishedShare"
                >${this.escapeHtml(this.translate("share_management.delete_published", "Delete"))}</button>
              </div>
            </div>
          </div>
        `).join("")}
      </div>
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

  defaultFeedbackMessage() {
    return this.translate("share_management.ready", "Adjust settings, recheck the connection, or clear published remote shares.")
  }

  findPublishedShare(token) {
    return this.publishedShares.find((share) => share.token === token)
  }

  async copyTextToClipboard(text, options = {}) {
    const appController = this.getAppController()
    if (appController?.copyTextToClipboard) {
      return appController.copyTextToClipboard(text, options)
    }

    try {
      await navigator.clipboard.writeText(text)
      return true
    } catch (_error) {
      return false
    }
  }

  setFeedback(message, error = false) {
    if (!this.hasFeedbackTarget) return

    this.feedbackTarget.textContent = message
    this.feedbackTarget.classList.toggle("text-red-500", error)
    this.feedbackTarget.classList.toggle("text-[var(--theme-text-muted)]", !error)
  }

  booleanLabel(value) {
    if (value === null || value === undefined) return "-"
    return value
      ? this.translate("share_management.yes", "Yes")
      : this.translate("share_management.no", "No")
  }

  reachableLabel(value) {
    if (value === null || value === undefined) return "-"

    if (value) {
      return this.statusPill(
        this.translate("share_management.status.online", "ONLINE"),
        "online"
      )
    }

    return this.statusPill(
      this.translate("share_management.status.offline", "OFFLINE"),
      "offline"
    )
  }

  statusPill(label, tone) {
    const toneClasses = tone === "online"
      ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300"
      : "border-red-500/30 bg-red-500/10 text-red-600 dark:text-red-400"

    return `<span class="inline-flex items-center rounded-full border px-[26px] py-0.5 text-[11px] font-medium uppercase tracking-wide ${toneClasses}">${this.escapeHtml(label)}</span>`
  }

  valueLabel(value) {
    if (value === null || value === undefined || value === "") return "-"
    return this.escapeHtml(String(value))
  }

  expirationLabel(value) {
    if (value === null || value === undefined || value === "") return "-"
    return `${this.escapeHtml(String(value))} ${this.escapeHtml(this.translate("share_management.status.days", "days"))}`
  }

  renderWarningCards(warnings) {
    if (!warnings.length) return ""

    return `
      <div class="space-y-3">
        ${warnings.map((warning) => `
          <div class="${this.warningCardClasses(warning.severity)}">
            <div class="flex items-start justify-between gap-3">
              <div>
                <p class="text-[11px] font-semibold uppercase tracking-wide">${this.escapeHtml(warning.title || "Warning")}</p>
                <p class="mt-1 text-sm">${this.escapeHtml(warning.message || "")}</p>
                ${warning.remediation ? `<p class="mt-2 text-xs opacity-90">${this.escapeHtml(warning.remediation)}</p>` : ""}
              </div>
              <span class="rounded-full border px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-[0.14em]">${this.escapeHtml(warning.severity || "info")}</span>
            </div>
          </div>
        `).join("")}
      </div>
    `
  }

  warningCardClasses(severity) {
    switch (severity) {
    case "danger":
      return "rounded border border-red-500/35 bg-red-500/10 px-3 py-3 text-red-700 dark:text-red-300"
    case "warning":
      return "rounded border border-amber-500/35 bg-amber-500/10 px-3 py-3 text-amber-700 dark:text-amber-300"
    default:
      return "rounded border border-sky-500/35 bg-sky-500/10 px-3 py-3 text-sky-700 dark:text-sky-300"
    }
  }

  formatTimestamp(value) {
    if (!value) return "-"

    try {
      return new Intl.DateTimeFormat(undefined, {
        dateStyle: "medium",
        timeStyle: "short"
      }).format(new Date(value))
    } catch (_error) {
      return String(value)
    }
  }

  escapeHtml(value) {
    const div = document.createElement("div")
    div.textContent = value == null ? "" : String(value)
    return div.innerHTML || "-"
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
