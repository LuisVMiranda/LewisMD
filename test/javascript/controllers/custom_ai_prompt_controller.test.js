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
  let appController

  beforeEach(async () => {
    setupJsdomGlobals()
    window.t = vi.fn((key, vars = {}) => {
      const translations = {
        "errors.ai_markdown_only": "Markdown only",
        "errors.no_prompt_provided": "No prompt provided",
        "errors.connection_lost": "Connection lost",
        "dialogs.custom_ai.hint_document": "Entire note",
        "dialogs.custom_ai.hint_selection": "Selected text",
        "dialogs.custom_ai.processing_provider": "AI",
        "dialogs.custom_ai.loading_options": "Loading available AI options...",
        "dialogs.custom_ai.saved_choice": "Saved for future custom prompts: %{label}",
        "dialogs.custom_ai.default_choice": "Using your default AI option: %{label}",
        "dialogs.custom_ai.invalid_saved_choice": "Your saved AI choice is no longer available. Using your default AI option: %{label}",
        "dialogs.custom_ai.selected_choice": "Selected for this prompt: %{label}",
        "dialogs.custom_ai.using_default_setup": "Couldn't load AI choices. This prompt will use your default AI setup.",
        "dialogs.custom_ai.no_available_options": "No configured AI options are available right now.",
        "dialogs.custom_ai.preference_save_failed": "Couldn't save this AI choice. It will be used for this prompt only."
      }

      const template = translations[key] || key
      return Object.entries(vars).reduce(
        (output, [name, value]) => output.replace(`%{${name}}`, value),
        template
      )
    })

    document.body.innerHTML = `
      <div data-controller="custom-ai-prompt">
        <dialog data-custom-ai-prompt-target="dialog"></dialog>
        <textarea data-custom-ai-prompt-target="promptInput"></textarea>
        <p data-custom-ai-prompt-target="selectionHint"></p>
        <select data-custom-ai-prompt-target="optionSelect"></select>
        <p data-custom-ai-prompt-target="optionStatus"></p>
        <span data-custom-ai-prompt-target="providerBadge" class="hidden"></span>
      </div>
    `

    HTMLDialogElement.prototype.showModal = vi.fn(function () {
      this.open = true
    })
    HTMLDialogElement.prototype.close = vi.fn(function () {
      this.open = false
    })

    appController = {
      isMarkdownFile: () => true,
      getCodemirrorController: () => ({
        editor: {
          state: {
            selection: { main: { empty: true, from: 0, to: 0 } },
            doc: {
              toString: () => "",
              length: 0
            }
          }
        }
      }),
      showTemporaryMessage: vi.fn()
    }

    element = document.querySelector('[data-controller="custom-ai-prompt"]')
    application = Application.start()
    application.register("custom-ai-prompt", CustomAiPromptController)

    await new Promise((resolve) => setTimeout(resolve, 0))
    controller = application.getControllerForElementAndIdentifier(element, "custom-ai-prompt")
    controller.getAppController = vi.fn(() => appController)
  })

  afterEach(() => {
    application.stop()
    vi.restoreAllMocks()
  })

  function aiConfigResponse(overrides = {}) {
    return {
      enabled: true,
      available_options: [
        {
          provider: "openai",
          model: "gpt-4o-mini",
          label: "OpenAI · gpt-4o-mini",
          provider_label: "OpenAI"
        },
        {
          provider: "anthropic",
          model: "claude-sonnet-4-20250514",
          label: "Anthropic · claude-sonnet-4-20250514",
          provider_label: "Anthropic"
        }
      ],
      default_option: {
        provider: "openai",
        model: "gpt-4o-mini",
        label: "OpenAI · gpt-4o-mini",
        provider_label: "OpenAI"
      },
      selection_states: {
        grammar: { feature: "grammar", configured: false, valid: false, invalid: false },
        custom_prompt: { feature: "custom_prompt", configured: false, valid: false, invalid: false }
      },
      saved_selections: {
        grammar: null,
        custom_prompt: null
      },
      ...overrides
    }
  }

  function response(json, ok = true, status = 200) {
    return {
      ok,
      status,
      json: () => Promise.resolve(json)
    }
  }

  it("loads ai options on open and preselects the saved custom prompt choice", async () => {
    global.fetch = vi.fn().mockResolvedValueOnce(response(aiConfigResponse({
      saved_selections: {
        grammar: null,
        custom_prompt: {
          provider: "anthropic",
          model: "claude-sonnet-4-20250514",
          label: "Anthropic · claude-sonnet-4-20250514",
          provider_label: "Anthropic"
        }
      }
    })))

    await controller.openModal()

    expect(controller.dialogTarget.showModal).toHaveBeenCalled()
    expect(controller.optionSelectTarget.options).toHaveLength(2)
    expect(controller.optionSelectTarget.value).toBe("anthropic::claude-sonnet-4-20250514")
    expect(controller.optionStatusTarget.textContent).toBe(
      "Saved for future custom prompts: Anthropic · claude-sonnet-4-20250514"
    )
    expect(controller.providerBadgeTarget.textContent).toBe("Anthropic · claude-sonnet-4-20250514")
    expect(controller.selectionHintTarget.textContent).toBe("Entire note")
  })

  it("submits the selected provider and model with the custom prompt request", async () => {
    controller.getGrammarController = vi.fn(() => ({
      dispatch: vi.fn(),
      hasProcessingOverlayTarget: true,
      processingOverlayTarget: document.createElement("div"),
      hasProcessingProviderTarget: true,
      processingProviderTarget: document.createElement("span"),
      openWithCustomResponse: vi.fn(),
      cleanup: vi.fn()
    }))

    global.fetch = vi.fn()
      .mockResolvedValueOnce(response(aiConfigResponse({
        saved_selections: {
          grammar: null,
          custom_prompt: {
            provider: "anthropic",
            model: "claude-sonnet-4-20250514",
            label: "Anthropic · claude-sonnet-4-20250514",
            provider_label: "Anthropic"
          }
        }
      })))
      .mockResolvedValueOnce(response({
        original: "",
        corrected: "# Intro\n\nStarted from scratch.",
        provider: "anthropic",
        model: "claude-sonnet-4-20250514"
      }))

    await controller.openModal()
    controller.promptInputTarget.value = "Write an introduction"

    await controller.generate()

    expect(global.fetch).toHaveBeenCalledTimes(2)
    expect(global.fetch.mock.calls[1][0]).toBe("/ai/generate_custom")

    const requestBody = JSON.parse(global.fetch.mock.calls[1][1].body)
    expect(requestBody).toEqual({
      selected_text: "",
      prompt: "Write an introduction",
      provider: "anthropic",
      model: "claude-sonnet-4-20250514"
    })
  })

  it("continues with the selected ai option when saving the preference fails", async () => {
    controller.getGrammarController = vi.fn(() => ({
      dispatch: vi.fn(),
      hasProcessingOverlayTarget: true,
      processingOverlayTarget: document.createElement("div"),
      hasProcessingProviderTarget: true,
      processingProviderTarget: document.createElement("span"),
      openWithCustomResponse: vi.fn(),
      cleanup: vi.fn()
    }))

    global.fetch = vi.fn()
      .mockResolvedValueOnce(response(aiConfigResponse()))
      .mockResolvedValueOnce(response({ error: "save failed" }, false, 422))
      .mockResolvedValueOnce(response({
        original: "",
        corrected: "Updated by Claude.",
        provider: "anthropic",
        model: "claude-sonnet-4-20250514"
      }))

    await controller.openModal()
    controller.optionSelectTarget.value = "anthropic::claude-sonnet-4-20250514"
    controller.onOptionChanged()
    controller.promptInputTarget.value = "Rewrite this professionally"

    await controller.generate()

    expect(global.fetch).toHaveBeenCalledTimes(3)
    expect(global.fetch.mock.calls[1][0]).toBe("/ai/preferences")
    expect(global.fetch.mock.calls[2][0]).toBe("/ai/generate_custom")
    expect(appController.showTemporaryMessage).toHaveBeenCalledWith(
      "Couldn't save this AI choice. It will be used for this prompt only.",
      3500,
      true
    )

    const requestBody = JSON.parse(global.fetch.mock.calls[2][1].body)
    expect(requestBody.provider).toBe("anthropic")
    expect(requestBody.model).toBe("claude-sonnet-4-20250514")
  })

  it("falls back to the default ai setup when loading choices fails", async () => {
    controller.getGrammarController = vi.fn(() => ({
      dispatch: vi.fn(),
      hasProcessingOverlayTarget: true,
      processingOverlayTarget: document.createElement("div"),
      hasProcessingProviderTarget: true,
      processingProviderTarget: document.createElement("span"),
      openWithCustomResponse: vi.fn(),
      cleanup: vi.fn()
    }))

    global.fetch = vi.fn()
      .mockRejectedValueOnce(new Error("config unavailable"))
      .mockResolvedValueOnce(response({
        original: "",
        corrected: "Fallback output.",
        provider: "openai",
        model: "gpt-4o-mini"
      }))

    await controller.openModal()

    expect(controller.optionSelectTarget.disabled).toBe(true)
    expect(controller.optionStatusTarget.textContent).toBe(
      "Couldn't load AI choices. This prompt will use your default AI setup."
    )

    controller.promptInputTarget.value = "Keep going"
    await controller.generate()

    expect(global.fetch).toHaveBeenCalledTimes(2)
    const requestBody = JSON.parse(global.fetch.mock.calls[1][1].body)
    expect(requestBody).toEqual({
      selected_text: "",
      prompt: "Keep going"
    })
  })

  it("falls back to the default option when the saved custom prompt choice is no longer available", async () => {
    global.fetch = vi.fn().mockResolvedValueOnce(response(aiConfigResponse({
      selection_states: {
        grammar: { feature: "grammar", configured: false, valid: false, invalid: false },
        custom_prompt: {
          feature: "custom_prompt",
          configured: true,
          valid: false,
          invalid: true,
          provider: "anthropic",
          model: "claude-opus-old"
        }
      }
    })))

    await controller.openModal()

    expect(controller.optionSelectTarget.value).toBe("openai::gpt-4o-mini")
    expect(controller.optionStatusTarget.textContent).toContain(
      "Your saved AI choice is no longer available. Using your default AI option:"
    )
    expect(controller.optionStatusTarget.textContent).toContain("gpt-4o-mini")
  })
})
