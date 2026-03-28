import { Controller } from "@hotwired/stimulus"
import { get, patch, post } from "@rails/request.js"

export default class extends Controller {
  static targets = [
    "dialog",
    "grammarModeButton",
    "promptModeButton",
    "promptSection",
    "promptInput",
    "selectionHint",
    "providerBadge",
    "optionSelect",
    "optionStatus",
    "runButton"
  ]

  connect() {
    this.abortController = null
    this.boundHandleEscKey = null
    this.aiEnabled = false
    this.aiOptions = []
    this.defaultOption = null
    this.savedSelections = { grammar: null, custom_prompt: null }
    this.selectionStates = { grammar: null, custom_prompt: null }
    this.currentOption = null
    this.currentMode = "grammar"
    this.aiConfigLoaded = false
    this.aiConfigLoadFailed = false
    this.basePromptInputHeight = null
    this.currentFilePath = null
    this.selectedText = ""
    this.selectionRange = null

    this.configurePromptInputResize()
    this.updateModeUi()
  }

  disconnect() {
    this.clearAbortWatcher()
  }

  async openModal(mode = "grammar") {
    const appController = this.getAppController()
    if (!appController) return

    if (!appController.isMarkdownFile()) {
      appController.showTemporaryMessage(window.t("errors.ai_markdown_only"))
      return
    }

    this.captureEditorContext(appController)
    this.promptInputTarget.value = ""
    this.setMode(mode)
    await this.loadAiChoices()

    if (!this.aiConfigLoadFailed && !this.aiEnabled) {
      this.getDiffController()?.showConfigNotice()
      return
    }

    this.dialogTarget.showModal()
    this.configurePromptInputResize()
    this.focusPrimaryInput()
  }

  close() {
    this.dialogTarget.close()
  }

  handleKeydown(event) {
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault()
      this.run()
    }
  }

  switchMode(event) {
    this.setMode(event.currentTarget.dataset.mode)
  }

  setMode(mode) {
    this.currentMode = mode === "custom_prompt" ? "custom_prompt" : "grammar"
    this.syncCurrentOptionForMode()
    this.updateModeUi()
  }

  updateModeUi() {
    const isPromptMode = this.currentMode === "custom_prompt"

    if (this.hasGrammarModeButtonTarget) {
      this.toggleModeButton(this.grammarModeButtonTarget, !isPromptMode)
    }

    if (this.hasPromptModeButtonTarget) {
      this.toggleModeButton(this.promptModeButtonTarget, isPromptMode)
    }

    if (this.hasPromptSectionTarget) {
      this.promptSectionTarget.classList.toggle("hidden", !isPromptMode)
    }

    if (this.hasSelectionHintTarget) {
      this.selectionHintTarget.classList.toggle("hidden", !isPromptMode)
    }

    if (this.hasRunButtonTarget) {
      this.runButtonTarget.textContent = isPromptMode
        ? window.t("dialogs.ai_assist.run_prompt")
        : window.t("dialogs.ai_assist.run_grammar")
    }
  }

  toggleModeButton(button, active) {
    button.classList.toggle("bg-[var(--theme-accent)]", active)
    button.classList.toggle("text-[var(--theme-accent-text)]", active)
    button.classList.toggle("hover:bg-[var(--theme-bg-hover)]", !active)
    button.classList.toggle("text-[var(--theme-text-secondary)]", !active)
  }

  focusPrimaryInput() {
    if (this.currentMode === "custom_prompt") {
      this.promptInputTarget.focus()
      return
    }

    this.optionSelectTarget.focus()
  }

  captureEditorContext(appController) {
    this.currentFilePath = appController.currentFile

    const editorController = appController.getCodemirrorController()
    const editor = editorController.editor
    const selection = editor.state.selection.main

    if (selection.empty) {
      this.selectedText = editor.state.doc.toString()
      this.selectionRange = { from: 0, to: editor.state.doc.length }
      this.selectionHintTarget.textContent = window.t("dialogs.custom_ai.hint_document")
    } else {
      this.selectedText = editor.state.sliceDoc(selection.from, selection.to)
      this.selectionRange = { from: selection.from, to: selection.to }
      this.selectionHintTarget.textContent = window.t("dialogs.custom_ai.hint_selection")
    }
  }

  onOptionChanged() {
    this.currentOption = this.readSelectedOption()
    this.renderOptionStatus()
  }

  async run() {
    if (this.currentMode === "custom_prompt") {
      await this.runCustomPrompt()
      return
    }

    await this.runGrammarCheck()
  }

  async runGrammarCheck() {
    const appController = this.getAppController()
    const diffController = this.getDiffController()
    if (!appController || !diffController) return

    if (!this.currentFilePath) {
      alert(window.t("errors.no_file_open"))
      return
    }

    const editorText = appController.getCodemirrorController()?.getValue?.() || ""
    if (!editorText.trim()) {
      alert(window.t("errors.no_text_to_check"))
      return
    }

    const autosaveController = appController.getAutosaveController?.()
    if (autosaveController?.saveTimeout) {
      await autosaveController.saveNow()
    }

    const aiOption = this.readSelectedOption()
    await this.runRequest({
      feature: "grammar",
      option: aiOption,
      fallbackMessageKey: "dialogs.ai_diff.using_default_setup",
      preferenceFailureKey: "dialogs.ai_diff.preference_save_failed",
      processingLabel: aiOption?.label || window.t("dialogs.custom_ai.processing_provider"),
      request: () => post("/ai/fix_grammar", {
        body: this.buildGrammarBody(aiOption),
        responseKind: "json",
        signal: this.abortController.signal
      }),
      onSuccess: (data) => {
        diffController.openWithResponse(
          data.original,
          data.corrected,
          data.provider,
          data.model,
          null,
          "dialogs.ai_diff.title"
        )
      }
    })
  }

  async runCustomPrompt() {
    const prompt = this.promptInputTarget.value.trim()
    if (!prompt) {
      alert(window.t("errors.no_prompt_provided"))
      return
    }

    const diffController = this.getDiffController()
    if (!diffController) return

    const textSnapshot = this.selectedText
    const rangeSnapshot = this.selectionRange
    const aiOption = this.readSelectedOption()

    await this.runRequest({
      feature: "custom_prompt",
      option: aiOption,
      fallbackMessageKey: "dialogs.custom_ai.using_default_setup",
      preferenceFailureKey: "dialogs.custom_ai.preference_save_failed",
      processingLabel: aiOption?.label || window.t("dialogs.custom_ai.processing_provider"),
      request: () => post("/ai/generate_custom", {
        body: this.buildGenerateBody(textSnapshot, prompt, aiOption),
        responseKind: "json",
        signal: this.abortController.signal
      }),
      onSuccess: (data) => {
        diffController.openWithResponse(
          data.original,
          data.corrected,
          data.provider,
          data.model,
          rangeSnapshot,
          "dialogs.custom_ai.title"
        )
      }
    })
  }

  async runRequest({ feature, option, fallbackMessageKey, preferenceFailureKey, processingLabel, request, onSuccess }) {
    const appController = this.getAppController()
    const diffController = this.getDiffController()
    if (!diffController) return

    if (this.aiConfigLoadFailed) {
      appController?.showTemporaryMessage(window.t(fallbackMessageKey), 3500, true)
    }

    if (!this.aiConfigLoadFailed && !this.aiEnabled) {
      this.close()
      diffController.showConfigNotice()
      return
    }

    if (option) {
      const savedKey = this.optionKey(this.savedSelections[feature])
      const selectedKey = this.optionKey(option)

      if (savedKey !== selectedKey) {
        const preferenceSaved = await this.persistSelection(feature, option)
        if (!preferenceSaved) {
          appController?.showTemporaryMessage(window.t(preferenceFailureKey), 3500, true)
        }
      }
    }

    this.close()
    diffController.startProcessing(processingLabel)
    this.startAbortWatcher()

    try {
      const response = await request()
      const data = await response.json

      if (data.error) {
        alert(`${window.t("errors.failed_to_process_ai")}: ${data.error}`)
        return
      }

      onSuccess(data)
    } catch (error) {
      if (error?.name === "AbortError") {
        console.log("AI request cancelled")
      } else {
        console.error("AI request failed:", error)
        alert(this.currentMode === "custom_prompt"
          ? window.t("errors.connection_lost")
          : window.t("errors.failed_to_process_ai"))
      }
    } finally {
      this.clearAbortWatcher()
      diffController.stopProcessing()
    }
  }

  startAbortWatcher() {
    this.abortController = new AbortController()
    this.boundHandleEscKey = (event) => {
      if (event.key === "Escape" && this.abortController) {
        this.abortController.abort()
      }
    }
    document.addEventListener("keydown", this.boundHandleEscKey)
  }

  clearAbortWatcher() {
    document.removeEventListener("keydown", this.boundHandleEscKey)
    this.boundHandleEscKey = null
    this.abortController = null
  }

  async loadAiChoices() {
    this.aiConfigLoadFailed = false
    this.setSelectLoadingState()

    try {
      const response = await get("/ai/config", { responseKind: "json" })
      if (!response.ok) throw new Error("config request failed")

      const data = await response.json
      this.aiEnabled = data.enabled
      this.aiOptions = Array.isArray(data.available_options) ? data.available_options : []
      this.savedSelections = data.saved_selections || { grammar: null, custom_prompt: null }
      this.selectionStates = data.selection_states || { grammar: null, custom_prompt: null }
      this.defaultOption = data.default_option || data.current_selection || this.aiOptions[0] || null
      this.syncCurrentOptionForMode()
      this.aiConfigLoaded = true
    } catch (error) {
      console.debug("AI config options unavailable:", error)
      this.aiEnabled = false
      this.aiOptions = []
      this.savedSelections = { grammar: null, custom_prompt: null }
      this.selectionStates = { grammar: null, custom_prompt: null }
      this.defaultOption = null
      this.currentOption = null
      this.aiConfigLoaded = false
      this.aiConfigLoadFailed = true
    }

    this.renderAiOptions()
  }

  setSelectLoadingState() {
    if (!this.hasOptionSelectTarget || !this.hasOptionStatusTarget) return

    this.optionSelectTarget.disabled = true
    this.optionSelectTarget.innerHTML = ""
    const option = document.createElement("option")
    option.value = ""
    option.textContent = window.t("dialogs.custom_ai.loading_options")
    this.optionSelectTarget.appendChild(option)
    this.optionStatusTarget.textContent = window.t("dialogs.custom_ai.loading_options")
    this.providerBadgeTarget.classList.add("hidden")
  }

  renderAiOptions() {
    if (!this.hasOptionSelectTarget || !this.hasOptionStatusTarget) return

    this.optionSelectTarget.innerHTML = ""

    if (this.aiOptions.length === 0) {
      const option = document.createElement("option")
      option.value = ""
      option.textContent = this.aiConfigLoadFailed
        ? window.t(this.currentMode === "grammar" ? "dialogs.ai_diff.using_default_setup" : "dialogs.custom_ai.using_default_setup")
        : window.t("dialogs.custom_ai.no_available_options")
      this.optionSelectTarget.appendChild(option)
      this.optionSelectTarget.disabled = true
      this.optionStatusTarget.textContent = option.textContent
      this.providerBadgeTarget.classList.add("hidden")
      return
    }

    this.aiOptions.forEach((optionData) => {
      const option = document.createElement("option")
      option.value = this.optionKey(optionData)
      option.textContent = optionData.label
      option.dataset.provider = optionData.provider
      option.dataset.model = optionData.model
      this.optionSelectTarget.appendChild(option)
    })

    this.optionSelectTarget.disabled = this.aiOptions.length === 1
    this.optionSelectTarget.value = this.currentOption ? this.optionKey(this.currentOption) : this.optionSelectTarget.options[0].value
    this.currentOption = this.readSelectedOption() || this.currentOption
    this.renderOptionStatus()
  }

  syncCurrentOptionForMode() {
    this.currentOption = this.findMatchingOption(this.savedSelections[this.currentMode]) ||
      this.findMatchingOption(this.defaultOption) ||
      this.aiOptions[0] ||
      null

    if (this.aiConfigLoaded) {
      this.renderAiOptions()
    }
  }

  renderOptionStatus() {
    if (!this.hasOptionStatusTarget || !this.hasProviderBadgeTarget) return

    if (!this.currentOption) {
      this.optionStatusTarget.textContent = this.aiConfigLoadFailed
        ? window.t(this.currentMode === "grammar" ? "dialogs.ai_diff.using_default_setup" : "dialogs.custom_ai.using_default_setup")
        : window.t("dialogs.custom_ai.no_available_options")
      this.providerBadgeTarget.classList.add("hidden")
      return
    }

    this.providerBadgeTarget.textContent = this.currentOption.label
    this.providerBadgeTarget.classList.remove("hidden")

    const invalidSavedSelection = Boolean(this.selectionStates?.[this.currentMode]?.invalid)
    const savedOption = this.savedSelections[this.currentMode]
    const savedKey = this.optionKey(savedOption)
    const currentKey = this.optionKey(this.currentOption)
    const defaultKey = this.optionKey(this.defaultOption)
    const translations = this.currentMode === "grammar"
      ? {
          invalid: "dialogs.ai_diff.invalid_saved_choice",
          saved: "dialogs.ai_diff.saved_choice",
          default: "dialogs.ai_diff.default_choice",
          selected: "dialogs.ai_diff.selected_choice"
        }
      : {
          invalid: "dialogs.custom_ai.invalid_saved_choice",
          saved: "dialogs.custom_ai.saved_choice",
          default: "dialogs.custom_ai.default_choice",
          selected: "dialogs.custom_ai.selected_choice"
        }

    if (invalidSavedSelection) {
      this.optionStatusTarget.textContent = window.t(translations.invalid, { label: this.currentOption.label })
    } else if (savedKey && savedKey === currentKey) {
      this.optionStatusTarget.textContent = window.t(translations.saved, { label: this.currentOption.label })
    } else if (defaultKey && defaultKey === currentKey) {
      this.optionStatusTarget.textContent = window.t(translations.default, { label: this.currentOption.label })
    } else {
      this.optionStatusTarget.textContent = window.t(translations.selected, { label: this.currentOption.label })
    }
  }

  buildGrammarBody(aiOption) {
    const body = { path: this.currentFilePath }

    if (aiOption) {
      body.provider = aiOption.provider
      body.model = aiOption.model
    }

    return body
  }

  buildGenerateBody(text, prompt, aiOption) {
    const body = {
      selected_text: text,
      prompt
    }

    if (aiOption) {
      body.provider = aiOption.provider
      body.model = aiOption.model
    }

    return body
  }

  optionKey(option) {
    return option ? `${option.provider}::${option.model}` : ""
  }

  findMatchingOption(option) {
    if (!option) return null

    return this.aiOptions.find((candidate) => this.optionKey(candidate) === this.optionKey(option)) || null
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

  async persistSelection(feature, aiOption) {
    try {
      const response = await patch("/ai/preferences", {
        body: {
          feature,
          provider: aiOption.provider,
          model: aiOption.model
        },
        responseKind: "json"
      })
      const data = await response.json
      if (!response.ok || data.error) return false

      this.savedSelections = data.saved_selections || this.savedSelections
      this.selectionStates = data.selection_states || this.selectionStates
      this.currentOption = this.findMatchingOption(data.selection) || aiOption
      this.renderOptionStatus()
      return true
    } catch (error) {
      console.debug("AI preference save failed:", error)
      return false
    }
  }

  configurePromptInputResize() {
    if (!this.hasPromptInputTarget) return

    const baseHeight = this.basePromptInputHeight || this.measurePromptInputBaseHeight()
    this.basePromptInputHeight = baseHeight

    this.promptInputTarget.style.resize = "vertical"
    this.promptInputTarget.style.overflowY = "auto"
    this.promptInputTarget.style.minHeight = `${baseHeight}px`
    this.promptInputTarget.style.maxHeight = `${Math.round(baseHeight * 3)}px`
  }

  measurePromptInputBaseHeight() {
    const measuredHeight = this.promptInputTarget.getBoundingClientRect().height ||
      this.promptInputTarget.offsetHeight ||
      this.parsePixelValue(window.getComputedStyle(this.promptInputTarget).height)

    if (measuredHeight > 0) return measuredHeight

    const computedStyle = window.getComputedStyle(this.promptInputTarget)
    const rowCount = Number(this.promptInputTarget.getAttribute("rows")) || 3
    const lineHeight = this.parsePixelValue(computedStyle.lineHeight)
    const fontSize = this.parsePixelValue(computedStyle.fontSize) || 16
    const contentLineHeight = lineHeight || fontSize * 1.5
    const paddingHeight = this.parsePixelValue(computedStyle.paddingTop) + this.parsePixelValue(computedStyle.paddingBottom)
    const borderHeight = this.parsePixelValue(computedStyle.borderTopWidth) + this.parsePixelValue(computedStyle.borderBottomWidth)

    return Math.round((rowCount * contentLineHeight) + paddingHeight + borderHeight)
  }

  parsePixelValue(value) {
    const parsed = Number.parseFloat(value)
    return Number.isFinite(parsed) ? parsed : 0
  }

  getAppController() {
    const appElement = document.querySelector('[data-controller~="app"]')
    return appElement ? this.application.getControllerForElementAndIdentifier(appElement, "app") : null
  }

  getDiffController() {
    const element = document.querySelector('[data-controller~="ai-grammar"]')
    return element ? this.application.getControllerForElementAndIdentifier(element, "ai-grammar") : null
  }
}
