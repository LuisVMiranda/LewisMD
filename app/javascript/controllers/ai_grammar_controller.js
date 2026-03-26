import { Controller } from "@hotwired/stimulus"
import { get, patch, post } from "@rails/request.js"
import { computeWordDiff } from "lib/diff_utils"

// AI Grammar Controller
// Handles AI-powered grammar checking with diff view
// Dispatches ai-grammar:accepted event with corrected text

export default class extends Controller {
  static targets = [
    "dialog",
    "configNotice",
    "diffContent",
    "originalText",
    "correctedText",
    "correctedDiff",
    "providerBadge",
    "editToggle",
    "selectionControls",
    "selectionPrompt",
    "optionSelect",
    "optionStatus",
    "runButton",
    "processingOverlay",
    "processingProvider"
  ]

  connect() {
    this.aiEnabled = false
    this.aiProvider = null
    this.aiModel = null
    this.aiAbortController = null
    this.currentFilePath = null
    this.availableOptions = []
    this.defaultOption = null
    this.savedSelections = { grammar: null, custom_prompt: null }
    this.selectionStates = { grammar: null, custom_prompt: null }
    this.currentOption = null
    this.aiConfigLoadFailed = false
    this.invalidSavedSelection = false

    this.checkAiAvailability()
  }

  async checkAiAvailability() {
    try {
      const response = await get("/ai/config", { responseKind: "json" })
      this.aiConfigLoadFailed = false
      if (response.ok) {
        const data = await response.json
        this.aiEnabled = data.enabled
        this.aiProvider = data.provider
        this.aiModel = data.model
        this.availableOptions = Array.isArray(data.available_options) ? data.available_options : []
        this.defaultOption = data.default_option || data.current_selection || this.availableOptions[0] || null
        this.savedSelections = data.saved_selections || { grammar: null, custom_prompt: null }
        this.selectionStates = data.selection_states || { grammar: null, custom_prompt: null }
        this.invalidSavedSelection = Boolean(this.selectionState("grammar")?.invalid)
        this.currentOption = this.findMatchingOption(this.savedSelections.grammar) ||
          this.findMatchingOption(this.defaultOption) ||
          this.availableOptions[0] ||
          null
      }
    } catch (e) {
      console.debug("AI config check failed:", e)
      this.aiConfigLoadFailed = true
      this.aiEnabled = false
      this.aiProvider = null
      this.aiModel = null
      this.availableOptions = []
      this.defaultOption = null
      this.savedSelections = { grammar: null, custom_prompt: null }
      this.selectionStates = { grammar: null, custom_prompt: null }
      this.currentOption = null
      this.invalidSavedSelection = false
    }
  }

  // Called by app_controller with file path
  async open(filePath) {
    // Hide provider badge initially
    if (this.hasProviderBadgeTarget) {
      this.providerBadgeTarget.classList.add("hidden")
    }

    await this.checkAiAvailability()

    if (!filePath) {
      alert(window.t("errors.no_file_open"))
      return
    }

    this.currentFilePath = filePath

    if (this.aiConfigLoadFailed) {
      this.hideSelectionControls()
      this.configNoticeTarget.classList.add("hidden")
      this.diffContentTarget.classList.add("hidden")
      this.getAppController()?.showTemporaryMessage(window.t("dialogs.ai_diff.using_default_setup"), 3500, true)
      await this.runGrammarCheck(null, { persistSelection: false })
      return
    }

    // If AI is not configured, show the config notice
    if (!this.aiEnabled) {
      this.hideSelectionControls()
      this.configNoticeTarget.classList.remove("hidden")
      this.diffContentTarget.classList.add("hidden")
      this.dialogTarget.showModal()
      return
    }

    this.currentOption = this.findMatchingOption(this.savedSelections.grammar) ||
      this.findMatchingOption(this.defaultOption) ||
      this.availableOptions[0] ||
      null

    if (this.invalidSavedSelection && this.currentOption) {
      this.getAppController()?.showTemporaryMessage(
        window.t("dialogs.ai_diff.invalid_saved_choice", { label: this.currentOption.label }),
        4000,
        true
      )
    }

    if (this.shouldPromptForSelection()) {
      this.showSelectionChooser()
      return
    }

    await this.runGrammarCheck(this.currentOption)
  }

  shouldPromptForSelection() {
    return this.availableOptions.length > 1 && !this.savedSelections?.grammar && !this.invalidSavedSelection
  }

  showSelectionChooser() {
    this.configNoticeTarget.classList.add("hidden")
    this.diffContentTarget.classList.add("hidden")
    this.renderSelectionControls("chooser")
    this.dialogTarget.showModal()
  }

  hideSelectionControls() {
    if (this.hasSelectionControlsTarget) {
      this.selectionControlsTarget.classList.add("hidden")
    }
  }

  renderSelectionControls(mode = "result") {
    if (!this.hasSelectionControlsTarget || !this.hasOptionSelectTarget || !this.hasOptionStatusTarget || !this.hasRunButtonTarget) {
      return
    }

    const shouldShow = this.availableOptions.length > 1
    if (!shouldShow) {
      this.hideSelectionControls()
      return
    }

    this.selectionControlsTarget.classList.remove("hidden")
    this.selectionPromptTarget.textContent = mode === "chooser"
      ? window.t("dialogs.ai_diff.chooser_prompt")
      : window.t("dialogs.ai_diff.rerun_prompt")
    this.runButtonTarget.textContent = mode === "chooser"
      ? window.t("dialogs.ai_diff.run_check")
      : window.t("dialogs.ai_diff.run_again")

    this.optionSelectTarget.innerHTML = ""
    this.availableOptions.forEach((optionData) => {
      const option = document.createElement("option")
      option.value = this.optionKey(optionData)
      option.textContent = optionData.label
      option.dataset.provider = optionData.provider
      option.dataset.model = optionData.model
      this.optionSelectTarget.appendChild(option)
    })

    if (this.currentOption) {
      this.optionSelectTarget.value = this.optionKey(this.currentOption)
    }

    this.optionSelectTarget.disabled = this.availableOptions.length <= 1
    this.renderOptionStatus()
  }

  onOptionChanged() {
    this.currentOption = this.readSelectedOption()
    this.renderOptionStatus()
  }

  async runSelectedOption() {
    await this.runGrammarCheck(this.currentOption, { persistSelection: true })
  }

  async runGrammarCheck(selection = null, { persistSelection = true } = {}) {
    const effectiveSelection = selection || this.currentOption

    // Dispatch event to notify app controller (e.g., to disable editor, update button state)
    this.dispatch("processing-started")

    // Show processing overlay
    if (this.hasProcessingOverlayTarget) {
      if (this.hasProcessingProviderTarget && effectiveSelection?.label) {
        this.processingProviderTarget.textContent = effectiveSelection.label
      } else if (this.hasProcessingProviderTarget && this.aiProvider && this.aiModel) {
        this.processingProviderTarget.textContent = `${this.aiProvider}: ${this.aiModel}`
      } else if (this.hasProcessingProviderTarget) {
        this.processingProviderTarget.textContent = "AI"
      }
      this.processingOverlayTarget.classList.remove("hidden")
    }

    // Setup abort controller for ESC key cancellation
    this.aiAbortController = new AbortController()
    this.boundHandleEscKey = (e) => {
      if (e.key === "Escape" && this.aiAbortController) {
        this.aiAbortController.abort()
      }
    }
    document.addEventListener("keydown", this.boundHandleEscKey)

    try {
      if (effectiveSelection && persistSelection) {
        const savedKey = this.optionKey(this.savedSelections.grammar)
        const selectedKey = this.optionKey(effectiveSelection)

        if (savedKey !== selectedKey) {
          const preferenceSaved = await this.persistSelection(effectiveSelection)
          if (!preferenceSaved) {
            this.getAppController()?.showTemporaryMessage(window.t("dialogs.ai_diff.preference_save_failed"), 3500, true)
          }
        }
      }

      const response = await post("/ai/fix_grammar", {
        body: this.buildRequestBody(effectiveSelection),
        responseKind: "json",
        signal: this.aiAbortController.signal
      })

      const data = await response.json

      if (data.error) {
        alert(`${window.t("errors.failed_to_process_ai")}: ${data.error}`)
        return
      }

      // Show provider badge
      if (this.hasProviderBadgeTarget && data.provider && data.model) {
        this.providerBadgeTarget.textContent = `${data.provider}: ${data.model}`
        this.providerBadgeTarget.classList.remove("hidden")
      }
      this.currentOption = this.findMatchingOption({ provider: data.provider, model: data.model }) || effectiveSelection

      // Populate and show dialog with diff content
      this.configNoticeTarget.classList.add("hidden")
      this.diffContentTarget.classList.remove("hidden")
      this.diffContentTarget.classList.add("flex")
      this.renderSelectionControls("result")

      // Compute and display diff
      const diff = computeWordDiff(data.original, data.corrected)
      this.originalTextTarget.innerHTML = this.renderDiffOriginal(diff)
      this.correctedDiffTarget.innerHTML = this.renderDiffCorrected(diff)
      this.correctedTextTarget.value = data.corrected

      // Reset to diff view mode
      this.correctedDiffTarget.classList.remove("hidden")
      this.correctedTextTarget.classList.add("hidden")
      if (this.hasEditToggleTarget) {
        this.editToggleTarget.textContent = window.t("common.edit")
      }

      this.dialogTarget.showModal()
    } catch (e) {
      if (e.name === "AbortError") {
        console.log("AI request cancelled by user")
      } else {
        console.error("AI request failed:", e)
        alert(window.t("errors.failed_to_process_ai"))
      }
    } finally {
      this.cleanup()
    }
  }

  // Called by custom_ai_prompt_controller
  openWithCustomResponse(original, corrected, provider, model, range = null) {
    this.replacementRange = range
    this.hideSelectionControls()

    if (this.hasProviderBadgeTarget && provider && model) {
      this.providerBadgeTarget.textContent = `${provider}: ${model}`
      this.providerBadgeTarget.classList.remove("hidden")
    }

    this.configNoticeTarget.classList.add("hidden")
    this.diffContentTarget.classList.remove("hidden")
    this.diffContentTarget.classList.add("flex")

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

  cleanup() {
    document.removeEventListener("keydown", this.boundHandleEscKey)
    this.aiAbortController = null

    if (this.hasProcessingOverlayTarget) {
      this.processingOverlayTarget.classList.add("hidden")
    }

    // Dispatch event to notify app controller (e.g., to re-enable editor, restore button state)
    this.dispatch("processing-ended")
  }

  close() {
    this.dialogTarget.close()
  }

  toggleEditMode() {
    const isEditing = !this.correctedTextTarget.classList.contains("hidden")

    if (isEditing) {
      // Switch to diff view
      this.correctedTextTarget.classList.add("hidden")
      this.correctedDiffTarget.classList.remove("hidden")
      this.editToggleTarget.textContent = window.t("common.edit")
    } else {
      // Switch to edit view
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

  // Render diff for the original text column (shows deletions)
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

  // Render diff for the corrected text column (shows additions)
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

  escapeHtml(text) {
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;")
  }

  buildRequestBody(selection) {
    const body = { path: this.currentFilePath }

    if (selection) {
      body.provider = selection.provider
      body.model = selection.model
    }

    return body
  }

  optionKey(option) {
    return option ? `${option.provider}::${option.model}` : ""
  }

  findMatchingOption(option) {
    if (!option) return null

    return this.availableOptions.find((candidate) => this.optionKey(candidate) === this.optionKey(option)) || null
  }

  selectionState(feature) {
    return this.selectionStates?.[feature] || null
  }

  readSelectedOption() {
    if (!this.hasOptionSelectTarget) return null

    const selectedOption = this.optionSelectTarget.selectedOptions[0]
    if (!selectedOption?.dataset.provider || !selectedOption.dataset.model) return null

    return this.findMatchingOption({
      provider: selectedOption.dataset.provider,
      model: selectedOption.dataset.model
    })
  }

  renderOptionStatus() {
    if (!this.hasOptionStatusTarget) return

    if (!this.currentOption) {
      this.optionStatusTarget.textContent = ""
      return
    }

    const currentKey = this.optionKey(this.currentOption)
    const savedKey = this.optionKey(this.savedSelections.grammar)
    const defaultKey = this.optionKey(this.defaultOption)

    if (this.invalidSavedSelection) {
      this.optionStatusTarget.textContent = window.t("dialogs.ai_diff.invalid_saved_choice", { label: this.currentOption.label })
    } else if (savedKey && savedKey === currentKey) {
      this.optionStatusTarget.textContent = window.t("dialogs.ai_diff.saved_choice", { label: this.currentOption.label })
    } else if (defaultKey && defaultKey === currentKey) {
      this.optionStatusTarget.textContent = window.t("dialogs.ai_diff.default_choice", { label: this.currentOption.label })
    } else {
      this.optionStatusTarget.textContent = window.t("dialogs.ai_diff.selected_choice", { label: this.currentOption.label })
    }
  }

  async persistSelection(selection) {
    try {
      const response = await patch("/ai/preferences", {
        body: {
          feature: "grammar",
          provider: selection.provider,
          model: selection.model
        },
        responseKind: "json"
      })
      const data = await response.json
      if (!response.ok || data.error) return false

      this.savedSelections = data.saved_selections || this.savedSelections
      this.selectionStates = data.selection_states || this.selectionStates
      this.invalidSavedSelection = false
      this.currentOption = this.findMatchingOption(data.selection) || selection
      this.renderOptionStatus()
      return true
    } catch (error) {
      console.debug("AI grammar preference save failed:", error)
      return false
    }
  }

  getAppController() {
    const appElement = document.querySelector('[data-controller~="app"]')
    return appElement ? this.application.getControllerForElementAndIdentifier(appElement, "app") : null
  }
}
