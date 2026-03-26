/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
vi.mock("@rails/request.js", async () => await import("../mocks/requestjs.js"))

import { Application } from "@hotwired/stimulus"
import { setupJsdomGlobals } from "../helpers/jsdom_globals.js"
import AiGrammarController from "../../../app/javascript/controllers/ai_grammar_controller.js"

describe("AiGrammarController", () => {
  let application
  let controller
  let element
  let appController

  beforeEach(async () => {
    setupJsdomGlobals()
    window.t = vi.fn((key, vars = {}) => {
      const translations = {
        "errors.no_file_open": "No file open",
        "errors.failed_to_process_ai": "Failed to process AI",
        "common.edit": "Edit",
        "preview.title": "Preview",
        "dialogs.ai_diff.provider_label": "AI provider / model",
        "dialogs.ai_diff.chooser_prompt": "Choose which AI option you'd like to use for grammar check. LewisMD will remember your choice for next time.",
        "dialogs.ai_diff.rerun_prompt": "Want to compare another AI option? Pick it here and run the grammar check again.",
        "dialogs.ai_diff.run_check": "Run grammar check",
        "dialogs.ai_diff.run_again": "Run again",
        "dialogs.ai_diff.saved_choice": "Saved for future grammar checks: %{label}",
        "dialogs.ai_diff.default_choice": "Using your default AI option: %{label}",
        "dialogs.ai_diff.invalid_saved_choice": "Your saved AI choice is no longer available. Using your default AI option: %{label}",
        "dialogs.ai_diff.selected_choice": "Selected for this grammar check: %{label}",
        "dialogs.ai_diff.using_default_setup": "Couldn't load AI choices. This grammar check will use your default AI setup.",
        "dialogs.ai_diff.preference_save_failed": "Couldn't save this AI choice. It will be used for this grammar check only."
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
      <div data-controller="ai-grammar">
        <dialog data-ai-grammar-target="dialog"></dialog>
        <div data-ai-grammar-target="configNotice" class="hidden"></div>
        <div data-ai-grammar-target="selectionControls" class="hidden">
          <p data-ai-grammar-target="selectionPrompt"></p>
          <select data-ai-grammar-target="optionSelect"></select>
          <p data-ai-grammar-target="optionStatus"></p>
          <button data-ai-grammar-target="runButton"></button>
        </div>
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

    global.fetch = vi.fn().mockResolvedValue(response(aiConfigResponse({
      enabled: false,
      provider: null,
      model: null,
      available_options: [],
      default_option: null
    })))

    appController = {
      showTemporaryMessage: vi.fn()
    }

    element = document.querySelector('[data-controller="ai-grammar"]')
    application = Application.start()
    application.register("ai-grammar", AiGrammarController)

    await new Promise((resolve) => setTimeout(resolve, 0))
    controller = application.getControllerForElementAndIdentifier(element, "ai-grammar")
    controller.getAppController = vi.fn(() => appController)
    global.fetch.mockClear()
  })

  afterEach(() => {
    application.stop()
    vi.restoreAllMocks()
  })

  function aiConfigResponse(overrides = {}) {
    return {
      enabled: true,
      provider: "openai",
      model: "gpt-4o-mini",
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

  it("shows the chooser when multiple options exist and no grammar preference is saved", async () => {
    global.fetch.mockResolvedValueOnce(response(aiConfigResponse()))

    await controller.open("/path/to/file.md")

    expect(global.fetch).toHaveBeenCalledTimes(1)
    expect(global.fetch.mock.calls[0][0]).toBe("/ai/config")
    expect(controller.selectionControlsTarget.classList.contains("hidden")).toBe(false)
    expect(controller.selectionPromptTarget.textContent).toBe(
      "Choose which AI option you'd like to use for grammar check. LewisMD will remember your choice for next time."
    )
    expect(controller.runButtonTarget.textContent).toBe("Run grammar check")
    expect(controller.optionSelectTarget.value).toBe("openai::gpt-4o-mini")
    expect(controller.optionStatusTarget.textContent).toBe(
      "Using your default AI option: OpenAI · gpt-4o-mini"
    )
    expect(controller.diffContentTarget.classList.contains("hidden")).toBe(true)
    expect(controller.dialogTarget.showModal).toHaveBeenCalled()
  })

  it("runs grammar check immediately with the saved grammar preference", async () => {
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

    await controller.open("/path/to/file.md")

    expect(global.fetch).toHaveBeenCalledTimes(2)
    expect(global.fetch.mock.calls[1][0]).toBe("/ai/fix_grammar")

    const requestBody = JSON.parse(global.fetch.mock.calls[1][1].body)
    expect(requestBody).toEqual({
      path: "/path/to/file.md",
      provider: "anthropic",
      model: "claude-sonnet-4-20250514"
    })
    expect(controller.providerBadgeTarget.textContent).toBe("anthropic: claude-sonnet-4-20250514")
    expect(controller.selectionPromptTarget.textContent).toBe(
      "Want to compare another AI option? Pick it here and run the grammar check again."
    )
    expect(controller.runButtonTarget.textContent).toBe("Run again")
    expect(controller.optionStatusTarget.textContent).toBe(
      "Saved for future grammar checks: Anthropic · claude-sonnet-4-20250514"
    )
    expect(controller.correctedTextTarget.value).toBe("Hello world")
  })

  it("persists the chosen grammar option before running the check", async () => {
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
          grammar: {
            provider: "anthropic",
            model: "claude-sonnet-4-20250514",
            label: "Anthropic · claude-sonnet-4-20250514",
            provider_label: "Anthropic"
          },
          custom_prompt: null
        }
      }))
      .mockResolvedValueOnce(response({
        original: "Hello wrold",
        corrected: "Hello world",
        provider: "anthropic",
        model: "claude-sonnet-4-20250514"
      }))

    await controller.open("/path/to/file.md")
    controller.optionSelectTarget.value = "anthropic::claude-sonnet-4-20250514"
    controller.onOptionChanged()

    await controller.runSelectedOption()

    expect(global.fetch).toHaveBeenCalledTimes(3)
    expect(global.fetch.mock.calls[1][0]).toBe("/ai/preferences")
    expect(global.fetch.mock.calls[2][0]).toBe("/ai/fix_grammar")

    const preferenceBody = JSON.parse(global.fetch.mock.calls[1][1].body)
    expect(preferenceBody).toEqual({
      feature: "grammar",
      provider: "anthropic",
      model: "claude-sonnet-4-20250514"
    })

    const requestBody = JSON.parse(global.fetch.mock.calls[2][1].body)
    expect(requestBody.provider).toBe("anthropic")
    expect(requestBody.model).toBe("claude-sonnet-4-20250514")
    expect(controller.optionStatusTarget.textContent).toBe(
      "Saved for future grammar checks: Anthropic · claude-sonnet-4-20250514"
    )
  })

  it("continues with the selected grammar option when saving the preference fails", async () => {
    global.fetch = vi.fn()
      .mockResolvedValueOnce(response(aiConfigResponse()))
      .mockResolvedValueOnce(response({ error: "save failed" }, false, 422))
      .mockResolvedValueOnce(response({
        original: "Hello wrold",
        corrected: "Hello world",
        provider: "anthropic",
        model: "claude-sonnet-4-20250514"
      }))

    await controller.open("/path/to/file.md")
    controller.optionSelectTarget.value = "anthropic::claude-sonnet-4-20250514"
    controller.onOptionChanged()

    await controller.runSelectedOption()

    expect(global.fetch).toHaveBeenCalledTimes(3)
    expect(global.fetch.mock.calls[1][0]).toBe("/ai/preferences")
    expect(global.fetch.mock.calls[2][0]).toBe("/ai/fix_grammar")
    expect(appController.showTemporaryMessage).toHaveBeenCalledWith(
      "Couldn't save this AI choice. It will be used for this grammar check only.",
      3500,
      true
    )

    const requestBody = JSON.parse(global.fetch.mock.calls[2][1].body)
    expect(requestBody.provider).toBe("anthropic")
    expect(requestBody.model).toBe("claude-sonnet-4-20250514")
  })

  it("falls back to the default ai setup when loading choices fails", async () => {
    global.fetch = vi.fn()
      .mockRejectedValueOnce(new Error("config unavailable"))
      .mockResolvedValueOnce(response({
        original: "Hello wrold",
        corrected: "Hello world",
        provider: "openai",
        model: "gpt-4o-mini"
      }))

    await controller.open("/path/to/file.md")

    expect(appController.showTemporaryMessage).toHaveBeenCalledWith(
      "Couldn't load AI choices. This grammar check will use your default AI setup.",
      3500,
      true
    )
    expect(global.fetch).toHaveBeenCalledTimes(2)
    expect(global.fetch.mock.calls[1][0]).toBe("/ai/fix_grammar")
    expect(JSON.parse(global.fetch.mock.calls[1][1].body)).toEqual({
      path: "/path/to/file.md"
    })
    expect(controller.providerBadgeTarget.textContent).toBe("openai: gpt-4o-mini")
  })

  it("falls back to the default option when the saved grammar choice is no longer available", async () => {
    global.fetch = vi.fn()
      .mockResolvedValueOnce(response(aiConfigResponse({
        selection_states: {
          grammar: {
            feature: "grammar",
            configured: true,
            valid: false,
            invalid: true,
            provider: "anthropic",
            model: "claude-opus-old"
          },
          custom_prompt: { feature: "custom_prompt", configured: false, valid: false, invalid: false }
        }
      })))
      .mockResolvedValueOnce(response({
        selection: {
          provider: "openai",
          model: "gpt-4o-mini",
          label: "OpenAI Â· gpt-4o-mini",
          provider_label: "OpenAI"
        },
        saved_selections: {
          grammar: {
            provider: "openai",
            model: "gpt-4o-mini",
            label: "OpenAI Â· gpt-4o-mini",
            provider_label: "OpenAI"
          },
          custom_prompt: null
        },
        selection_states: {
          grammar: { feature: "grammar", configured: true, valid: true, invalid: false },
          custom_prompt: { feature: "custom_prompt", configured: false, valid: false, invalid: false }
        }
      }))
      .mockResolvedValueOnce(response({
        original: "Hello wrold",
        corrected: "Hello world",
        provider: "openai",
        model: "gpt-4o-mini"
      }))

    await controller.open("/path/to/file.md")

    expect(appController.showTemporaryMessage.mock.calls[0][0]).toContain(
      "Your saved AI choice is no longer available. Using your default AI option:"
    )
    expect(appController.showTemporaryMessage.mock.calls[0][0]).toContain("gpt-4o-mini")
    expect(appController.showTemporaryMessage.mock.calls[0][1]).toBe(4000)
    expect(appController.showTemporaryMessage.mock.calls[0][2]).toBe(true)
    expect(global.fetch).toHaveBeenCalledTimes(3)
    expect(global.fetch.mock.calls[1][0]).toBe("/ai/preferences")
    expect(global.fetch.mock.calls[2][0]).toBe("/ai/fix_grammar")
    expect(JSON.parse(global.fetch.mock.calls[2][1].body)).toEqual({
      path: "/path/to/file.md",
      provider: "openai",
      model: "gpt-4o-mini"
    })
    expect(controller.optionStatusTarget.textContent).toContain("Saved for future grammar checks:")
    expect(controller.optionStatusTarget.textContent).toContain("gpt-4o-mini")
  })

  it("hides grammar selection controls when showing a custom prompt response", () => {
    controller.selectionControlsTarget.classList.remove("hidden")

    controller.openWithCustomResponse("Original", "Corrected", "openai", "gpt-4o-mini")

    expect(controller.selectionControlsTarget.classList.contains("hidden")).toBe(true)
    expect(controller.providerBadgeTarget.textContent).toBe("openai: gpt-4o-mini")
    expect(controller.dialogTarget.showModal).toHaveBeenCalled()
  })

  it("shows an alert when no file path is provided", async () => {
    global.fetch.mockResolvedValueOnce(response(aiConfigResponse()))

    await controller.open(null)

    expect(window.alert).toHaveBeenCalledWith("No file open")
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

  it("dispatches the accepted event with the corrected text", () => {
    const dispatchSpy = vi.spyOn(controller, "dispatch")
    controller.correctedTextTarget.value = "Corrected text content"

    controller.accept()

    expect(dispatchSpy).toHaveBeenCalledWith("accepted", {
      detail: { correctedText: "Corrected text content", range: undefined }
    })
    expect(controller.dialogTarget.close).toHaveBeenCalled()
  })

  it("escapes html and renders diff fragments safely", () => {
    expect(controller.escapeHtml('<script>alert("xss")</script>')).toBe(
      "&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;"
    )
    expect(controller.renderDiffOriginal([{ type: "delete", value: "removed" }])).toBe(
      '<span class="ai-diff-del">removed</span>'
    )
    expect(controller.renderDiffCorrected([{ type: "insert", value: "added" }])).toBe(
      '<span class="ai-diff-add">added</span>'
    )
  })
})
