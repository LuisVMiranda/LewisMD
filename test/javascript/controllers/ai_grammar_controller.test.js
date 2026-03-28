/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import { setupJsdomGlobals } from "../helpers/jsdom_globals.js"
import AiGrammarController from "../../../app/javascript/controllers/ai_grammar_controller.js"

describe("AiGrammarController", () => {
  let application
  let controller
  let element

  beforeEach(async () => {
    setupJsdomGlobals()
    window.t = vi.fn((key) => ({
      "common.edit": "Edit",
      "preview.title": "Preview",
      "dialogs.ai_diff.title": "AI Review"
    }[key] || key))

    document.body.innerHTML = `
      <div data-controller="ai-grammar">
        <dialog data-ai-grammar-target="dialog"></dialog>
        <h2 data-ai-grammar-target="dialogTitle"></h2>
        <div data-ai-grammar-target="configNotice" class="hidden"></div>
        <div data-ai-grammar-target="diffContent" class="hidden"></div>
        <div data-ai-grammar-target="originalText"></div>
        <textarea data-ai-grammar-target="correctedText"></textarea>
        <div data-ai-grammar-target="correctedDiff"></div>
        <span data-ai-grammar-target="providerBadge" class="hidden"></span>
        <button data-ai-grammar-target="editToggle"></button>
        <div data-ai-grammar-target="processingOverlay" class="hidden"></div>
        <span data-ai-grammar-target="processingProvider"></span>
      </div>
    `

    HTMLDialogElement.prototype.showModal = vi.fn(function () {
      this.open = true
    })
    HTMLDialogElement.prototype.close = vi.fn(function () {
      this.open = false
    })

    element = document.querySelector('[data-controller="ai-grammar"]')
    application = Application.start()
    application.register("ai-grammar", AiGrammarController)

    await new Promise((resolve) => setTimeout(resolve, 0))
    controller = application.getControllerForElementAndIdentifier(element, "ai-grammar")
  })

  afterEach(() => {
    application.stop()
    vi.restoreAllMocks()
  })

  it("shows the AI config notice dialog", () => {
    controller.showConfigNotice()

    expect(controller.dialogTitleTarget.textContent).toBe("AI Review")
    expect(controller.configNoticeTarget.classList.contains("hidden")).toBe(false)
    expect(controller.diffContentTarget.classList.contains("hidden")).toBe(true)
    expect(controller.dialogTarget.showModal).toHaveBeenCalled()
  })

  it("starts and stops the shared processing overlay", () => {
    const dispatchSpy = vi.spyOn(controller, "dispatch")

    controller.startProcessing("Claude")
    expect(controller.processingOverlayTarget.classList.contains("hidden")).toBe(false)
    expect(controller.processingProviderTarget.textContent).toBe("Claude")
    expect(dispatchSpy).toHaveBeenCalledWith("processing-started")

    controller.stopProcessing()
    expect(controller.processingOverlayTarget.classList.contains("hidden")).toBe(true)
    expect(dispatchSpy).toHaveBeenCalledWith("processing-ended")
  })

  it("opens the diff dialog with provider metadata", () => {
    controller.openWithResponse("Hello wrold", "Hello world", "openai", "gpt-4o-mini")

    expect(controller.dialogTitleTarget.textContent).toBe("AI Review")
    expect(controller.providerBadgeTarget.textContent).toBe("openai: gpt-4o-mini")
    expect(controller.providerBadgeTarget.classList.contains("hidden")).toBe(false)
    expect(controller.correctedTextTarget.value).toBe("Hello world")
    expect(controller.dialogTarget.showModal).toHaveBeenCalled()
  })

  it("keeps replacement range when opening a custom response", () => {
    controller.openWithCustomResponse("Old", "New", "anthropic", "claude", { from: 3, to: 9 }, "dialogs.custom_ai.title")

    expect(controller.replacementRange).toEqual({ from: 3, to: 9 })
    expect(controller.dialogTitleTarget.textContent).toBe("dialogs.custom_ai.title")
  })

  it("switches between diff and edit mode", () => {
    controller.correctedDiffTarget.classList.remove("hidden")
    controller.correctedTextTarget.classList.add("hidden")

    controller.toggleEditMode()

    expect(controller.correctedDiffTarget.classList.contains("hidden")).toBe(true)
    expect(controller.correctedTextTarget.classList.contains("hidden")).toBe(false)
    expect(controller.editToggleTarget.textContent).toBe("Preview")

    controller.toggleEditMode()

    expect(controller.correctedDiffTarget.classList.contains("hidden")).toBe(false)
    expect(controller.correctedTextTarget.classList.contains("hidden")).toBe(true)
    expect(controller.editToggleTarget.textContent).toBe("Edit")
  })

  it("dispatches accepted text with an optional replacement range", () => {
    const dispatchSpy = vi.spyOn(controller, "dispatch")
    controller.replacementRange = { from: 1, to: 4 }
    controller.correctedTextTarget.value = "Updated text"

    controller.accept()

    expect(dispatchSpy).toHaveBeenCalledWith("accepted", {
      detail: { correctedText: "Updated text", range: { from: 1, to: 4 } }
    })
    expect(controller.dialogTarget.close).toHaveBeenCalled()
  })
})
