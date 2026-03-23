import { Controller } from "@hotwired/stimulus"
import { patch } from "@rails/request.js"
import { encodePath } from "lib/url_utils"
import { undo } from "@codemirror/commands"

export default class extends Controller {
  static targets = ["contentLossBanner", "saveStatus"]
  static outlets = ["codemirror", "offline-backup", "recovery-diff"]

  // Auto-save configuration
  static SAVE_DEBOUNCE_MS = 2000      // Wait 2 seconds after last keystroke
  static SAVE_MAX_INTERVAL_MS = 30000 // Force save every 30 seconds if continuously typing

  connect() {
    this.currentFile = null
    this.saveTimeout = null
    this.saveMaxIntervalTimeout = null
    this.isOffline = false
    this.hasUnsavedChanges = false
    this._isSaving = false
    this._lastSavedContent = null
    this._lastSaveTime = 0
    this._contentLossWarningActive = false
    this._contentLossOverride = false
    this._offlineBackupTimeout = null
    this._lastStatusSignature = null
  }

  disconnect() {
    if (this.saveTimeout) clearTimeout(this.saveTimeout)
    if (this.saveMaxIntervalTimeout) clearTimeout(this.saveMaxIntervalTimeout)
    if (this._offlineBackupTimeout) clearTimeout(this._offlineBackupTimeout)
  }

  // === Controller Getters (via Stimulus Outlets) ===

  getCodemirrorController() { return this.codemirrorOutlets[0] ?? null }
  getOfflineBackupController() { return this.offlineBackupOutlets[0] ?? null }
  getRecoveryDiffController() { return this.recoveryDiffOutlets[0] ?? null }

  emitStatusChanged(status, extra = {}) {
    const detail = {
      status,
      hasUnsavedChanges: this.hasUnsavedChanges,
      currentFile: this.currentFile,
      ...extra
    }
    const signature = JSON.stringify(detail)

    if (signature === this._lastStatusSignature) return

    this._lastStatusSignature = signature
    this.dispatch("status", { detail })
  }

  // === Public API (called by app controller) ===

  setFile(path, content) {
    this.currentFile = path
    this._lastSavedContent = content
    this.hasUnsavedChanges = false
    this.emitStatusChanged("idle")
  }

  checkOfflineBackup(serverContent) {
    const backup = this.getOfflineBackupController()
    if (!backup) return
    const data = backup.check(this.currentFile, serverContent)
    if (!data) return
    const recovery = this.getRecoveryDiffController()
    if (recovery) {
      recovery.open({
        path: this.currentFile,
        serverContent,
        backupContent: data.content,
        backupTimestamp: data.timestamp
      })
    }
  }

  checkContentRestored(currentContent) {
    if (!this._contentLossWarningActive || !this._lastSavedContent) return

    const lostChars = this._lastSavedContent.length - currentContent.length
    const lostPercent = this._lastSavedContent.length > 0 ? lostChars / this._lastSavedContent.length : 0

    if (lostPercent <= 0.2 || lostChars <= 50) {
      this.dismissContentLossWarning()
    }
  }

  // === Offline Backup ===

  scheduleOfflineBackup() {
    if (!this.isOffline || !this.currentFile) return

    if (this._offlineBackupTimeout) clearTimeout(this._offlineBackupTimeout)
    this._offlineBackupTimeout = setTimeout(() => {
      this._offlineBackupTimeout = null
      const cm = this.getCodemirrorController()
      const content = cm ? cm.getValue() : ""
      const backup = this.getOfflineBackupController()
      if (backup) backup.save(this.currentFile, content)
    }, 1000)
  }

  // === Auto Save ===

  scheduleAutoSave() {
    if (this.isOffline) {
      this.hasUnsavedChanges = true
      return
    }

    if (this._contentLossWarningActive) {
      this.hasUnsavedChanges = true
      return
    }

    if (!this.hasUnsavedChanges) {
      this.hasUnsavedChanges = true
      this.showSaveStatus(window.t("status.unsaved"))
      this.emitStatusChanged("unsaved")
    }

    if (this.saveTimeout) {
      clearTimeout(this.saveTimeout)
    }

    this.saveTimeout = setTimeout(() => this.saveNow(), this.constructor.SAVE_DEBOUNCE_MS)

    if (!this.saveMaxIntervalTimeout) {
      this.saveMaxIntervalTimeout = setTimeout(() => {
        this.saveMaxIntervalTimeout = null
        if (this.hasUnsavedChanges) {
          this.saveNow()
        }
      }, this.constructor.SAVE_MAX_INTERVAL_MS)
    }
  }

  async saveNow() {
    if (this.isOffline) {
      this.hasUnsavedChanges = true
      return
    }

    if (!this.currentFile) return
    if (this._isSaving) return

    if (this.saveTimeout) {
      clearTimeout(this.saveTimeout)
      this.saveTimeout = null
    }
    if (this.saveMaxIntervalTimeout) {
      clearTimeout(this.saveMaxIntervalTimeout)
      this.saveMaxIntervalTimeout = null
    }

    const codemirrorController = this.getCodemirrorController()
    const content = codemirrorController ? codemirrorController.getValue() : ""
    const isConfigFile = this.currentFile === ".fed"

    if (content === this._lastSavedContent) {
      this.hasUnsavedChanges = false
      this.showSaveStatus("")
      this.emitStatusChanged("idle")
      return
    }

    if (this._lastSavedContent && !this._contentLossOverride) {
      const lostChars = this._lastSavedContent.length - content.length
      const lostPercent = lostChars / this._lastSavedContent.length

      if (lostPercent > 0.2 && lostChars > 50) {
        this.showContentLossWarning()
        return
      }
    }

    this._isSaving = true
    try {
      const response = await patch(`/notes/${encodePath(this.currentFile)}`, {
        body: { content },
        responseKind: "json"
      })

      if (!response.ok) {
        throw new Error(window.t("errors.failed_to_save"))
      }

      this._lastSavedContent = content
      this._lastSaveTime = Date.now()
      this._contentLossOverride = false
      this.hasUnsavedChanges = false
      const backupController = this.getOfflineBackupController()
      if (backupController) backupController.clear(this.currentFile)
      this.showSaveStatus(window.t("status.saved"))
      this.emitStatusChanged("saved")
      setTimeout(() => this.showSaveStatus(""), 2000)

      if (isConfigFile) {
        this.dispatch("config-saved")
      }

      const freshContent = codemirrorController ? codemirrorController.getValue() : ""
      if (freshContent !== content) {
        this.hasUnsavedChanges = true
        if (!this.isOffline) {
          this.scheduleAutoSave()
        }
      }
    } catch (error) {
      console.error("Error saving:", error)
      this.showSaveStatus(window.t("status.error_saving"), true)
      this.emitStatusChanged("error")
    } finally {
      this._isSaving = false
    }
  }

  // === Connection Status ===

  onConnectionLost() {
    this.isOffline = true

    if (this.saveTimeout) {
      clearTimeout(this.saveTimeout)
      this.saveTimeout = null
      this.hasUnsavedChanges = true
    }
    if (this.saveMaxIntervalTimeout) {
      clearTimeout(this.saveMaxIntervalTimeout)
      this.saveMaxIntervalTimeout = null
    }

    this.dispatch("offline-changed", { detail: { offline: true } })

    this.showSaveStatus(window.t("connection.disconnected"), true)
    this.emitStatusChanged("offline")

    if (this.currentFile) {
      const cm = this.getCodemirrorController()
      const content = cm ? cm.getValue() : ""
      const backup = this.getOfflineBackupController()
      if (backup && content && content !== this._lastSavedContent) {
        backup.save(this.currentFile, content)
      }
    }
  }

  onConnectionRestored() {
    this.isOffline = false
    this.showSaveStatus("")

    if (this.hasUnsavedChanges && this.currentFile) {
      this.saveNow()
      return
    }

    this.emitStatusChanged("idle")
  }

  // === Content Loss Warning ===

  showContentLossWarning() {
    this._contentLossWarningActive = true
    if (this.hasContentLossBannerTarget) {
      this.contentLossBannerTarget.classList.remove("hidden")
      this.contentLossBannerTarget.classList.add("flex")
    }
  }

  dismissContentLossWarning() {
    this._contentLossWarningActive = false
    this._contentLossOverride = false
    if (this.hasContentLossBannerTarget) {
      this.contentLossBannerTarget.classList.add("hidden")
      this.contentLossBannerTarget.classList.remove("flex")
    }
  }

  undoContentLoss() {
    const codemirrorController = this.getCodemirrorController()
    if (codemirrorController) {
      const view = codemirrorController.getEditorView()
      if (view) {
        undo(view)
      }
    }
    this.dismissContentLossWarning()
  }

  saveAnywayAfterWarning() {
    this.dismissContentLossWarning()
    this._contentLossOverride = true
    this.saveNow()
  }

  // === Recovery ===

  onRecoveryResolved(event) {
    const { source, content } = event.detail
    const backup = this.getOfflineBackupController()
    if (backup) backup.clear(this.currentFile)

    if (source === "backup" && content) {
      const cm = this.getCodemirrorController()
      if (cm) cm.setValue(content)
      this._lastSavedContent = null
      this.hasUnsavedChanges = true
      this.emitStatusChanged("unsaved")
      this.scheduleAutoSave()
    }
  }

  // === UI ===

  showSaveStatus(text, isError = false) {
    if (!this.hasSaveStatusTarget) return
    this.saveStatusTarget.textContent = text
    this.saveStatusTarget.classList.toggle("hidden", !text)
    this.saveStatusTarget.classList.toggle("text-red-500", isError)
    this.saveStatusTarget.classList.toggle("dark:text-red-400", isError)
  }

}
