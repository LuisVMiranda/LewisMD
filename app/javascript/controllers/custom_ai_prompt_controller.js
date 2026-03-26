import { Controller } from "@hotwired/stimulus"
import { get, patch, post } from "@rails/request.js"

export default class extends Controller {
  static targets = ["dialog", "promptInput", "selectionHint", "providerBadge", "optionSelect", "optionStatus"]

  connect() {
    this.abortController = null
    this.aiOptions = []
    this.defaultOption = null
    this.savedOption = null
    this.currentOption = null
    this.selectionStates = { grammar: null, custom_prompt: null }
    this.invalidSavedSelection = false
    this.aiConfigLoaded = false
    this.aiConfigLoadFailed = false
  }

  // Opens the modal and fetches the selected text
  async openModal() {
    const appController = this.getAppController()
    if (!appController) return
    
    // Only allow for markdown files
    if (!appController.isMarkdownFile()) {
      appController.showTemporaryMessage(window.t("errors.ai_markdown_only"))
      return
    }

    const editorController = appController.getCodemirrorController()
    const editor = editorController.editor
    const selection = editor.state.selection.main
    
    // Fallback exactly to Mock Test 1 setup
    if (selection.empty) {
      this.selectedText = editor.state.doc.toString()
      this.selectionRange = { from: 0, to: editor.state.doc.length }
      this.selectionHintTarget.textContent = window.t("dialogs.custom_ai.hint_document")
    } else {
      this.selectedText = editor.state.sliceDoc(selection.from, selection.to)
      this.selectionRange = { from: selection.from, to: selection.to }
      this.selectionHintTarget.textContent = window.t("dialogs.custom_ai.hint_selection")
    }

    this.promptInputTarget.value = ""
    await this.loadAiChoices()
    this.dialogTarget.showModal()
    this.promptInputTarget.focus()
  }

  close() {
    this.dialogTarget.close()
  }

  handleKeydown(event) {
    // CMD/CTRL + Enter to generate
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault()
      this.generate()
    }
  }

  onOptionChanged() {
    this.currentOption = this.readSelectedOption()
    this.renderOptionStatus()
  }

  async generate() {
    const prompt = this.promptInputTarget.value.trim()
    if (!prompt) {
      alert(window.t("errors.no_prompt_provided"))
      return
    }

    // Capture states
    const textSnapshot = this.selectedText
    const rangeSnapshot = this.selectionRange
    const aiOption = this.readSelectedOption()

    if (aiOption) {
      const saved = this.savedOptionKey()
      const selected = this.optionKey(aiOption)
      if (saved !== selected) {
        const preferenceResult = await this.persistSelection(aiOption)
        if (preferenceResult === false) {
          this.getAppController()?.showTemporaryMessage(window.t("dialogs.custom_ai.preference_save_failed"), 3500, true)
        }
      }
    }

    // Close prompt modal
    this.close()

    // Borrow processing layout from grammar
    const aiGrammarController = this.getGrammarController()
    if (!aiGrammarController) return

    aiGrammarController.dispatch("processing-started")
    if (aiGrammarController.hasProcessingOverlayTarget) {
      if (aiGrammarController.hasProcessingProviderTarget) {
        aiGrammarController.processingProviderTarget.textContent = aiOption?.label || window.t("dialogs.custom_ai.processing_provider")
      }
      aiGrammarController.processingOverlayTarget.classList.remove("hidden")
    }

    // Mock Test 3: Network Drop Fallbacks
    try {
      this.abortController = new AbortController()

      const response = await post("/ai/generate_custom", {
        body: this.buildGenerateBody(textSnapshot, prompt, aiOption),
        responseKind: "json",
        signal: this.abortController.signal
      })

      const data = await response.json

      if (data.error) {
        alert(`${window.t("errors.failed_to_process_ai")}: ${data.error}`)
        aiGrammarController.cleanup()
        return
      }

      // Hide processing overlay before opening diff dialog
      if (aiGrammarController.hasProcessingOverlayTarget) {
        aiGrammarController.processingOverlayTarget.classList.add("hidden")
      }

      // Send to diff engine with custom range tracker (Mock Test 4 resolved)
      // openWithCustomResponse is synchronous — it calls showModal() directly.
      aiGrammarController.openWithCustomResponse(
        data.original, 
        data.corrected, 
        data.provider, 
        data.model, 
        rangeSnapshot
      )

      // Restore editor and AI button state now that dialog is shown
      aiGrammarController.cleanup()
    } catch (e) {
      if (e.name === "AbortError") {
        console.log("AI prompt cancelled")
      } else {
        console.error("AI prompt failed:", e)
        alert(window.t("errors.connection_lost"))
      }
      aiGrammarController.cleanup()
    } finally {
      this.abortController = null
    }
  }

  getAppController() {
    const appElement = document.querySelector('[data-controller~="app"]')
    return appElement ? this.application.getControllerForElementAndIdentifier(appElement, 'app') : null
  }

  getGrammarController() {
    const el = document.querySelector('[data-controller~="ai-grammar"]')
    return el ? this.application.getControllerForElementAndIdentifier(el, 'ai-grammar') : null
  }

  async loadAiChoices() {
    this.aiConfigLoadFailed = false
    this.setSelectLoadingState()

    try {
      const response = await get("/ai/config", { responseKind: "json" })
      if (!response.ok) throw new Error("config request failed")

      const data = await response.json
      this.aiOptions = Array.isArray(data.available_options) ? data.available_options : []
      this.savedOption = data.saved_selections?.custom_prompt || null
      this.selectionStates = data.selection_states || { grammar: null, custom_prompt: null }
      this.invalidSavedSelection = Boolean(this.selectionStates.custom_prompt?.invalid)
      this.defaultOption = data.default_option || data.current_selection || this.aiOptions[0] || null
      this.currentOption = this.findMatchingOption(this.savedOption) ||
        this.findMatchingOption(this.defaultOption) ||
        this.aiOptions[0] ||
        null
      this.aiConfigLoaded = true
    } catch (error) {
      console.debug("AI config options unavailable:", error)
      this.aiOptions = []
      this.savedOption = null
      this.defaultOption = null
      this.currentOption = null
      this.selectionStates = { grammar: null, custom_prompt: null }
      this.invalidSavedSelection = false
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
        ? window.t("dialogs.custom_ai.using_default_setup")
        : window.t("dialogs.custom_ai.no_available_options")
      this.optionSelectTarget.appendChild(option)
      this.optionSelectTarget.disabled = true
      this.optionStatusTarget.textContent = this.aiConfigLoadFailed
        ? window.t("dialogs.custom_ai.using_default_setup")
        : window.t("dialogs.custom_ai.no_available_options")
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

  renderOptionStatus() {
    if (!this.hasOptionStatusTarget || !this.hasProviderBadgeTarget) return

    if (!this.currentOption) {
      this.optionStatusTarget.textContent = this.aiConfigLoadFailed
        ? window.t("dialogs.custom_ai.using_default_setup")
        : window.t("dialogs.custom_ai.no_available_options")
      this.providerBadgeTarget.classList.add("hidden")
      return
    }

    this.providerBadgeTarget.textContent = this.currentOption.label
    this.providerBadgeTarget.classList.remove("hidden")

    if (this.invalidSavedSelection) {
      this.optionStatusTarget.textContent = window.t("dialogs.custom_ai.invalid_saved_choice", { label: this.currentOption.label })
    } else if (this.savedOptionKey() === this.optionKey(this.currentOption)) {
      this.optionStatusTarget.textContent = window.t("dialogs.custom_ai.saved_choice", { label: this.currentOption.label })
    } else if (this.defaultOption && this.optionKey(this.defaultOption) === this.optionKey(this.currentOption)) {
      this.optionStatusTarget.textContent = window.t("dialogs.custom_ai.default_choice", { label: this.currentOption.label })
    } else {
      this.optionStatusTarget.textContent = window.t("dialogs.custom_ai.selected_choice", { label: this.currentOption.label })
    }
  }

  buildGenerateBody(text, prompt, aiOption) {
    const body = {
      selected_text: text,
      prompt: prompt
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

  savedOptionKey() {
    return this.optionKey(this.savedOption)
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

  async persistSelection(aiOption) {
    try {
      const response = await patch("/ai/preferences", {
        body: {
          feature: "custom_prompt",
          provider: aiOption.provider,
          model: aiOption.model
        },
        responseKind: "json"
      })
      const data = await response.json
      if (!response.ok || data.error) return false

      this.savedOption = data.selection || aiOption
      this.selectionStates = data.selection_states || this.selectionStates
      this.invalidSavedSelection = false
      this.currentOption = this.readSelectedOption() || aiOption
      this.renderOptionStatus()
      return true
    } catch (error) {
      console.debug("AI preference save failed:", error)
      return false
    }
  }
}
