import { Controller } from "@hotwired/stimulus"

const MODE_TONES = {
  raw: "muted",
  preview: "accent",
  reading: "accent",
  typewriter: "accent"
}

const SAVE_TONES = {
  idle: "muted",
  saved: "muted",
  unsaved: "accent",
  offline: "error",
  error: "error"
}

const PUBLISH_TONES = {
  public: "accent",
  private: "muted",
  stale: "error"
}

export default class extends Controller {
  static targets = [
    "strip",
    "modeChip",
    "saveChip",
    "publishChip",
    "recoveryChip",
    "lineMetric",
    "selectionMetric",
    "zoomMetric"
  ]

  connect() {
    this.currentState = null
    this.autosaveState = this.defaultAutosaveState()
    this.boundTranslationsLoaded = () => this.render()
    window.addEventListener("frankmd:translations-loaded", this.boundTranslationsLoaded)
    this.hideStrip()
  }

  disconnect() {
    if (this.boundTranslationsLoaded) {
      window.removeEventListener("frankmd:translations-loaded", this.boundTranslationsLoaded)
    }
  }

  onStateChanged(event) {
    this.currentState = event.detail?.state || null
    this.render()
  }

  onAutosaveStatus(event) {
    this.autosaveState = event.detail || this.defaultAutosaveState()
    this.render()
  }

  defaultAutosaveState() {
    return {
      status: "idle",
      hasUnsavedChanges: false,
      currentFile: null
    }
  }

  shouldShowStrip() {
    return Boolean(this.currentState?.path && this.currentState?.isMarkdown)
  }

  render() {
    if (!this.shouldShowStrip()) {
      this.hideStrip()
      return
    }

    this.showStrip()
    this.renderModeChip()
    this.renderSaveChip()
    this.renderPublishChip()
    this.renderRecoveryChip()
    this.renderLineMetric()
    this.renderSelectionMetric()
    this.renderZoomMetric()
  }

  renderModeChip() {
    const mode = this.currentState?.mode || "raw"
    this.modeChipTarget.textContent = `${window.t("status_strip.mode_prefix")}: ${window.t(`status_strip.modes.${mode}`)}`
    this.modeChipTarget.dataset.tone = MODE_TONES[mode] || "muted"
  }

  renderSaveChip() {
    const status = this.currentSaveStatus()
    this.saveChipTarget.textContent = this.saveStatusLabel(status)
    this.saveChipTarget.dataset.tone = SAVE_TONES[status] || "muted"
    this.saveChipTarget.classList.remove("hidden")
  }

  renderPublishChip() {
    const status = this.currentPublishStatus()
    this.publishChipTarget.textContent = this.publishStatusLabel(status)
    this.publishChipTarget.dataset.tone = PUBLISH_TONES[status] || "muted"
    this.publishChipTarget.classList.remove("hidden")
  }

  renderRecoveryChip() {
    const hasRecovery = Boolean(this.currentState?.recoveryAvailable)
    this.recoveryChipTarget.textContent = hasRecovery ? window.t("status_strip.recovery_available") : ""
    this.recoveryChipTarget.dataset.tone = hasRecovery ? "accent" : "muted"
    this.recoveryChipTarget.classList.toggle("hidden", !hasRecovery)
  }

  renderLineMetric() {
    const { cursorLine, totalLines } = this.currentState || {}
    const hasLineMetric = Number.isInteger(cursorLine) && Number.isInteger(totalLines)
    const text = hasLineMetric ? `${window.t("status_strip.metrics.line")} ${cursorLine}/${totalLines}` : ""

    this.setMetric(this.lineMetricTarget, text)
  }

  renderSelectionMetric() {
    const hasSelection = Boolean(this.currentState?.hasSelection) && this.currentState?.selectionLength > 0
    const text = hasSelection
      ? `${window.t("status_strip.metrics.selection")} ${this.currentState.selectionLength}`
      : ""

    this.setMetric(this.selectionMetricTarget, text)
  }

  renderZoomMetric() {
    const showZoom = Boolean(this.currentState?.previewVisible) && this.currentState?.previewZoom != null
    const text = showZoom
      ? `${window.t("status_strip.metrics.zoom")} ${this.currentState.previewZoom}%`
      : ""

    this.setMetric(this.zoomMetricTarget, text)
  }

  currentSaveStatus() {
    if (!this.currentState?.path) return "idle"

    const { currentFile, status } = this.autosaveState || this.defaultAutosaveState()
    if (currentFile && currentFile !== this.currentState.path) return "idle"

    return status || "idle"
  }

  saveStatusLabel(status) {
    switch (status) {
      case "unsaved":
        return window.t("status_strip.save.unsaved")
      case "offline":
        return window.t("status_strip.save.offline")
      case "error":
        return window.t("status_strip.save.error")
      case "saved":
      case "idle":
      default:
        return window.t("status_strip.save.saved")
    }
  }

  currentPublishStatus() {
    if (!this.currentState?.shareable) return "private"
    if (this.currentState?.shareStale) return "stale"
    if (this.currentState?.shareActive) return "public"

    return "private"
  }

  publishStatusLabel(status) {
    switch (status) {
      case "public":
        return window.t("status_strip.publish.public")
      case "stale":
        return window.t("status_strip.publish.stale")
      case "private":
      default:
        return window.t("status_strip.publish.private")
    }
  }

  onPublishChipClick() {
    if (!this.currentState?.shareable) return

    this.dispatch("publish-clicked", {
      detail: {
        status: this.currentPublishStatus(),
        url: this.currentState?.shareUrl || null
      }
    })
  }

  setMetric(target, text) {
    target.textContent = text
    target.classList.toggle("hidden", !text)
  }

  hideStrip() {
    if (this.hasStripTarget) {
      this.stripTarget.classList.add("hidden")
    }
  }

  showStrip() {
    if (this.hasStripTarget) {
      this.stripTarget.classList.remove("hidden")
    }
  }
}
