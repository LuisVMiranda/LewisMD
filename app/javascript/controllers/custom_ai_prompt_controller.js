import { Controller } from "@hotwired/stimulus"
import { post } from "@rails/request.js"

export default class extends Controller {
  static targets = ["dialog", "promptInput", "selectionHint", "providerBadge"]

  connect() {
    this.abortController = null
  }

  // Opens the modal and fetches the selected text
  openModal() {
    const appController = this.getAppController()
    if (!appController) return
    
    // Only allow for markdown files
    if (!appController.isMarkdownFile()) {
      appController.showTemporaryMessage(window.t("errors.ai_markdown_only") || "AI is only available for markdown files")
      return
    }

    const editorController = appController.getCodemirrorController()
    const editor = editorController.editor
    const selection = editor.state.selection.main
    
    // Fallback exactly to Mock Test 1 setup
    if (selection.empty) {
      this.selectedText = editor.state.doc.toString()
      this.selectionRange = { from: 0, to: editor.state.doc.length }
      this.selectionHintTarget.textContent = window.t("dialogs.custom_ai.hint_document", { default: "No text selected. Analzying entire document..." })
    } else {
      this.selectedText = editor.state.sliceDoc(selection.from, selection.to)
      this.selectionRange = { from: selection.from, to: selection.to }
      this.selectionHintTarget.textContent = window.t("dialogs.custom_ai.hint_selection", { default: "Analyzing highlighted selection..." })
    }

    this.promptInputTarget.value = ""
    this.dialogTarget.showModal()
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

  async generate() {
    const prompt = this.promptInputTarget.value.trim()
    if (!prompt) {
      alert(window.t("errors.no_prompt_provided") || "Please provide AI instructions.")
      return
    }

    // Capture states
    const textSnapshot = this.selectedText
    const rangeSnapshot = this.selectionRange

    // Close prompt modal
    this.close()

    // Borrow processing layout from grammar
    const aiGrammarController = this.getGrammarController()
    if (!aiGrammarController) return

    aiGrammarController.dispatch("processing-started")
    if (aiGrammarController.hasProcessingOverlayTarget) {
      if (aiGrammarController.hasProcessingProviderTarget) {
        aiGrammarController.processingProviderTarget.textContent = "AI (Custom Prompt)"
      }
      aiGrammarController.processingOverlayTarget.classList.remove("hidden")
    }

    // Mock Test 3: Network Drop Fallbacks
    try {
      this.abortController = new AbortController()

      const response = await post("/ai/generate_custom", {
        body: { 
          selected_text: textSnapshot,
          prompt: prompt
        },
        responseKind: "json",
        signal: this.abortController.signal
      })

      const data = await response.json

      if (data.error) {
        alert(`${window.t("errors.failed_to_process_ai") || "AI Request Failed"}: ${data.error}`)
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
        alert(window.t("errors.connection_lost") || "Connection lost. Please check your internet and try your prompt again.")
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
}
