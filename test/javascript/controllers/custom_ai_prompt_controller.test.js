/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
vi.mock("@rails/request.js", async () => await import("../mocks/requestjs.js"))

import { Application } from "@hotwired/stimulus"
import { setupJsdomGlobals } from "../helpers/jsdom_globals.js"
import CustomAiPromptController from "../../../app/javascript/controllers/custom_ai_prompt_controller.js"

describe("CustomAiPromptController", () => {
  let application
  let controller
  let element

  beforeEach(async () => {
    setupJsdomGlobals()
    window.t = vi.fn((key) => ({
      "errors.ai_markdown_only": "Markdown only",
      "dialogs.custom_ai.hint_document": "Entire note",
      "dialogs.custom_ai.hint_selection": "Selected text",
      "dialogs.custom_ai.processing_provider": "AI"
    }[key] || key))

    document.body.innerHTML = `
      <div data-controller="custom-ai-prompt">
        <dialog data-custom-ai-prompt-target="dialog"></dialog>
        <textarea data-custom-ai-prompt-target="promptInput"></textarea>
        <p data-custom-ai-prompt-target="selectionHint"></p>
        <span data-custom-ai-prompt-target="providerBadge"></span>
      </div>
    `

    HTMLDialogElement.prototype.showModal = vi.fn(function () {
      this.open = true
    })
    HTMLDialogElement.prototype.close = vi.fn(function () {
      this.open = false
    })

    element = document.querySelector('[data-controller="custom-ai-prompt"]')
    application = Application.start()
    application.register("custom-ai-prompt", CustomAiPromptController)

    await new Promise((resolve) => setTimeout(resolve, 0))
    controller = application.getControllerForElementAndIdentifier(element, "custom-ai-prompt")
  })

  afterEach(() => {
    application.stop()
    vi.restoreAllMocks()
  })

  it("uses the whole note when no selection exists, even if the note is empty", () => {
    const editor = {
      state: {
        selection: { main: { empty: true, from: 0, to: 0 } },
        doc: {
          toString: () => "",
          length: 0
        }
      }
    }

    controller.getAppController = vi.fn(() => ({
      isMarkdownFile: () => true,
      getCodemirrorController: () => ({ editor }),
      showTemporaryMessage: vi.fn()
    }))

    controller.openModal()

    expect(controller.selectedText).toBe("")
    expect(controller.selectionRange).toEqual({ from: 0, to: 0 })
    expect(controller.selectionHintTarget.textContent).toBe("Entire note")
    expect(controller.dialogTarget.showModal).toHaveBeenCalled()
  })

  it("submits blank selected_text for empty-note prompt generation", async () => {
    controller.selectedText = ""
    controller.selectionRange = { from: 0, to: 0 }
    controller.promptInputTarget.value = "Write an introduction"

    const processingOverlay = document.createElement("div")
    processingOverlay.classList.add("hidden")
    const processingProvider = document.createElement("span")

    controller.getGrammarController = vi.fn(() => ({
      dispatch: vi.fn(),
      hasProcessingOverlayTarget: true,
      processingOverlayTarget: processingOverlay,
      hasProcessingProviderTarget: true,
      processingProviderTarget: processingProvider,
      openWithCustomResponse: vi.fn(),
      cleanup: vi.fn()
    }))

    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({
        original: "",
        corrected: "# Intro\n\nStarted from scratch.",
        provider: "openai",
        model: "gpt-4o-mini"
      })
    })

    await controller.generate()

    expect(global.fetch).toHaveBeenCalledTimes(1)
    expect(global.fetch.mock.calls[0][0]).toBe("/ai/generate_custom")

    const requestBody = JSON.parse(global.fetch.mock.calls[0][1].body)
    expect(requestBody).toEqual({
      selected_text: "",
      prompt: "Write an introduction"
    })
  })
})
