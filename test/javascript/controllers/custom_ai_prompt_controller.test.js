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
  let diffController

  beforeEach(async () => {
    setupJsdomGlobals()
    window.t = vi.fn((key, vars = {}) => {
      const translations = {
        "errors.ai_markdown_only": "Markdown only",
        "errors.no_file_open": "No file open",
        "errors.no_text_to_check": "No text to check",
        "errors.no_prompt_provided": "No prompt provided",
        "errors.failed_to_process_ai": "Failed to process AI",
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
        "dialogs.custom_ai.preference_save_failed": "Couldn't save this AI choice. It will be used for this prompt only.",
        "dialogs.ai_diff.saved_choice": "Saved for future grammar checks: %{label}",
        "dialogs.ai_diff.default_choice": "Using your default AI option: %{label}",
        "dialogs.ai_diff.invalid_saved_choice": "Your saved AI choice is no longer available. Using your default AI option: %{label}",
        "dialogs.ai_diff.selected_choice": "Selected for this grammar check: %{label}",
        "dialogs.ai_diff.using_default_setup": "Couldn't load AI choices. This grammar check will use your default AI setup.",
        "dialogs.ai_diff.preference_save_failed": "Couldn't save this AI choice. It will be used for this grammar check only.",
        "dialogs.ai_assist.run_grammar": "Run Grammar Check",
        "dialogs.ai_assist.run_prompt": "Run Prompt"
      }

      const template = translations[key] || key
      return Object.entries(vars).reduce(
        (output, [name, value]) => output.replace(`%{${name}}`, value),
        template
      )
    })

    window.alert = vi.fn()
    global.alert = window.alert

    document.body.innerHTML = `
      <div data-controller="custom-ai-prompt">
        <dialog data-custom-ai-prompt-target="dialog"></dialog>
        <button data-custom-ai-prompt-target="grammarModeButton" data-mode="grammar"></button>
        <button data-custom-ai-prompt-target="promptModeButton" data-mode="custom_prompt"></button>
        <div data-custom-ai-prompt-target="promptSection" class="hidden"></div>
        <textarea data-custom-ai-prompt-target="promptInput"></textarea>
        <p data-custom-ai-prompt-target="selectionHint" class="hidden"></p>
        <select data-custom-ai-prompt-target="optionSelect"></select>
        <p data-custom-ai-prompt-target="optionStatus"></p>
        <span data-custom-ai-prompt-target="providerBadge" class="hidden"></span>
        <button data-custom-ai-prompt-target="runButton"></button>
      </div>
    `

    HTMLDialogElement.prototype.showModal = vi.fn(function () {
      this.open = true
    })
    HTMLDialogElement.prototype.close = vi.fn(function () {
      this.open = false
    })

    appController = {
      currentFile: "notes/test.md",
      isMarkdownFile: () => true,
      getCodemirrorController: () => ({
        editor: {
          state: {
            selection: { main: { empty: true, from: 0, to: 0 } },
            doc: {
              toString: () => "Hello wrold",
              length: 11
            },
            sliceDoc: () => "Hello wrold"
          },
        },
        getValue: () => "Hello wrold"
      }),
      getAutosaveController: () => ({ saveTimeout: true, saveNow: vi.fn().mockResolvedValue(undefined) }),
      showTemporaryMessage: vi.fn()
    }

    diffController = {
      showConfigNotice: vi.fn(),
      startProcessing: vi.fn(),
      stopProcessing: vi.fn(),
      openWithResponse: vi.fn()
    }

    element = document.querySelector('[data-controller="custom-ai-prompt"]')
    application = Application.start()
    application.register("custom-ai-prompt", CustomAiPromptController)

    await new Promise((resolve) => setTimeout(resolve, 0))
    controller = application.getControllerForElementAndIdentifier(element, "custom-ai-prompt")
    controller.getAppController = vi.fn(() => appController)
    controller.getDiffController = vi.fn(() => diffController)
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

  it("opens in grammar mode by default and hides prompt-only controls", async () => {
    global.fetch = vi.fn().mockResolvedValueOnce(response(aiConfigResponse()))

    await controller.openModal("grammar")

    expect(controller.dialogTarget.showModal).toHaveBeenCalled()
    expect(controller.currentMode).toBe("grammar")
    expect(controller.promptSectionTarget.classList.contains("hidden")).toBe(true)
    expect(controller.selectionHintTarget.classList.contains("hidden")).toBe(true)
    expect(controller.runButtonTarget.textContent).toBe("Run Grammar Check")
  })

  it("opens in custom prompt mode and shows the selection hint", async () => {
    global.fetch = vi.fn().mockResolvedValueOnce(response(aiConfigResponse()))

    await controller.openModal("custom_prompt")

    expect(controller.currentMode).toBe("custom_prompt")
    expect(controller.promptSectionTarget.classList.contains("hidden")).toBe(false)
    expect(controller.selectionHintTarget.classList.contains("hidden")).toBe(false)
    expect(controller.selectionHintTarget.textContent).toBe("Entire note")
    expect(controller.runButtonTarget.textContent).toBe("Run Prompt")
  })

  it("switches the selected AI option when changing modes", async () => {
    global.fetch = vi.fn().mockResolvedValueOnce(response(aiConfigResponse({
      saved_selections: {
        grammar: {
          provider: "openai",
          model: "gpt-4o-mini",
          label: "OpenAI · gpt-4o-mini",
          provider_label: "OpenAI"
        },
        custom_prompt: {
          provider: "anthropic",
          model: "claude-sonnet-4-20250514",
          label: "Anthropic · claude-sonnet-4-20250514",
          provider_label: "Anthropic"
        }
      }
    })))

    await controller.openModal("grammar")
    expect(controller.optionSelectTarget.value).toBe("openai::gpt-4o-mini")

    controller.setMode("custom_prompt")

    expect(controller.optionSelectTarget.value).toBe("anthropic::claude-sonnet-4-20250514")
    expect(controller.optionStatusTarget.textContent).toContain("Anthropic · claude-sonnet-4-20250514")
  })

  it("shows the AI config notice instead of the assist dialog when AI is disabled", async () => {
    global.fetch = vi.fn().mockResolvedValueOnce(response(aiConfigResponse({ enabled: false })))

    await controller.openModal("grammar")

    expect(diffController.showConfigNotice).toHaveBeenCalled()
    expect(controller.dialogTarget.showModal).not.toHaveBeenCalled()
  })

  it("allows vertical prompt resizing up to three times the base height", async () => {
    global.fetch = vi.fn().mockResolvedValueOnce(response(aiConfigResponse()))
    controller.basePromptInputHeight = null
    controller.measurePromptInputBaseHeight = vi.fn(() => 60)

    await controller.openModal("custom_prompt")

    expect(controller.promptInputTarget.style.resize).toBe("vertical")
    expect(controller.promptInputTarget.style.overflowY).toBe("auto")
    expect(controller.promptInputTarget.style.minHeight).toBe("60px")
    expect(controller.promptInputTarget.style.maxHeight).toBe("180px")
  })

  it("runs grammar check with the selected provider and model", async () => {
    global.fetch = vi.fn()
      .mockResolvedValueOnce(response(aiConfigResponse({
        saved_selections: {
          grammar: {
            provider: "anthropic",
            model: "claude-sonnet-4-20250514",
            label: "Anthropic · claude-sonnet-4-20250514",
            provider_label: "Anthropic"
          },
          custom_prompt: null
        }
      })))
      .mockResolvedValueOnce(response({
        original: "Hello wrold",
        corrected: "Hello world",
        provider: "anthropic",
        model: "claude-sonnet-4-20250514"
      }))

    await controller.openModal("grammar")
    await controller.run()

    expect(global.fetch).toHaveBeenCalledTimes(2)
    expect(global.fetch.mock.calls[1][0]).toBe("/ai/fix_grammar")
    expect(JSON.parse(global.fetch.mock.calls[1][1].body)).toEqual({
      path: "notes/test.md",
      provider: "anthropic",
      model: "claude-sonnet-4-20250514"
    })
    expect(diffController.startProcessing).toHaveBeenCalledWith("Anthropic · claude-sonnet-4-20250514")
    expect(diffController.openWithResponse).toHaveBeenCalledWith(
      "Hello wrold",
      "Hello world",
      "anthropic",
      "claude-sonnet-4-20250514",
      null,
      "dialogs.ai_diff.title"
    )
  })

  it("runs custom prompts and forwards the replacement range to the diff controller", async () => {
    global.fetch = vi.fn()
      .mockResolvedValueOnce(response(aiConfigResponse()))
      .mockResolvedValueOnce(response({
        selection: {
          provider: "anthropic",
          model: "claude-sonnet-4-20250514",
          label: "Anthropic · claude-sonnet-4-20250514",
          provider_label: "Anthropic"
        },
        saved_selections: {
          grammar: null,
          custom_prompt: {
            provider: "anthropic",
            model: "claude-sonnet-4-20250514",
            label: "Anthropic · claude-sonnet-4-20250514",
            provider_label: "Anthropic"
          }
        }
      }))
      .mockResolvedValueOnce(response({
        original: "Hello wrold",
        corrected: "Hello world",
        provider: "anthropic",
        model: "claude-sonnet-4-20250514"
      }))

    await controller.openModal("custom_prompt")
    controller.optionSelectTarget.value = "anthropic::claude-sonnet-4-20250514"
    controller.onOptionChanged()
    controller.promptInputTarget.value = "Rewrite this professionally"

    await controller.run()

    expect(global.fetch).toHaveBeenCalledTimes(3)
    expect(global.fetch.mock.calls[1][0]).toBe("/ai/preferences")
    expect(global.fetch.mock.calls[2][0]).toBe("/ai/generate_custom")
    expect(JSON.parse(global.fetch.mock.calls[2][1].body)).toEqual({
      selected_text: "Hello wrold",
      prompt: "Rewrite this professionally",
      provider: "anthropic",
      model: "claude-sonnet-4-20250514"
    })
    expect(diffController.openWithResponse).toHaveBeenCalledWith(
      "Hello wrold",
      "Hello world",
      "anthropic",
      "claude-sonnet-4-20250514",
      { from: 0, to: 11 },
      "dialogs.custom_ai.title"
    )
  })

  it("shows a temporary warning and still runs with defaults when AI config loading fails", async () => {
    global.fetch = vi.fn()
      .mockRejectedValueOnce(new Error("config unavailable"))
      .mockResolvedValueOnce(response({
        original: "Hello wrold",
        corrected: "Hello world",
        provider: "openai",
        model: "gpt-4o-mini"
      }))

    await controller.openModal("grammar")
    await controller.run()

    expect(appController.showTemporaryMessage).toHaveBeenCalledWith(
      "Couldn't load AI choices. This grammar check will use your default AI setup.",
      3500,
      true
    )
    expect(JSON.parse(global.fetch.mock.calls[1][1].body)).toEqual({
      path: "notes/test.md"
    })
  })

  it("alerts when trying to run a custom prompt without instructions", async () => {
    global.fetch = vi.fn().mockResolvedValueOnce(response(aiConfigResponse()))

    await controller.openModal("custom_prompt")
    await controller.run()

    expect(window.alert).toHaveBeenCalledWith("No prompt provided")
  })
})
