/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import HelpController from "../../../app/javascript/controllers/help_controller.js"

describe("HelpController", () => {
  let application, controller, element

  beforeEach(() => {
    document.body.innerHTML = `
      <div data-controller="help">
        <dialog data-help-target="helpDialog">
          <button
            type="button"
            data-help-target="tabMarkdown"
            data-tab="markdown"
          ></button>
          <button
            type="button"
            data-help-target="tabShortcuts"
            data-tab="shortcuts"
          ></button>
          <button
            type="button"
            data-help-target="tabEditorExtras"
            data-tab="editor-extras"
          ></button>
          <div data-help-target="panelMarkdown"></div>
          <div data-help-target="panelShortcuts" class="hidden"></div>
          <div data-help-target="panelEditorExtras" class="hidden"></div>
        </dialog>
        <dialog data-help-target="aboutDialog"></dialog>
      </div>
    `

    // Mock showModal and close for dialog
    HTMLDialogElement.prototype.showModal = vi.fn(function () {
      this.open = true
    })
    HTMLDialogElement.prototype.close = vi.fn(function () {
      this.open = false
    })

    element = document.querySelector('[data-controller="help"]')
    application = Application.start()
    application.register("help", HelpController)

    return new Promise((resolve) => {
      setTimeout(() => {
        controller = application.getControllerForElementAndIdentifier(element, "help")
        resolve()
      }, 0)
    })
  })

  afterEach(() => {
    application.stop()
    vi.restoreAllMocks()
  })

  describe("openHelp()", () => {
    it("shows the help dialog", () => {
      controller.openHelp()

      expect(controller.helpDialogTarget.showModal).toHaveBeenCalled()
    })

    it("resets to the markdown tab when opening help", () => {
      controller.switchToTab("editor-extras")

      controller.openHelp()

      expect(controller.currentTab).toBe("markdown")
      expect(controller.panelMarkdownTarget.classList.contains("hidden")).toBe(false)
      expect(controller.panelShortcutsTarget.classList.contains("hidden")).toBe(true)
      expect(controller.panelEditorExtrasTarget.classList.contains("hidden")).toBe(true)
    })
  })

  describe("closeHelp()", () => {
    it("closes the help dialog", () => {
      controller.openHelp()
      controller.closeHelp()

      expect(controller.helpDialogTarget.close).toHaveBeenCalled()
    })
  })

  describe("openAbout()", () => {
    it("shows the about dialog", () => {
      controller.openAbout()

      expect(controller.aboutDialogTarget.showModal).toHaveBeenCalled()
    })
  })

  describe("closeAbout()", () => {
    it("closes the about dialog", () => {
      controller.openAbout()
      controller.closeAbout()

      expect(controller.aboutDialogTarget.close).toHaveBeenCalled()
    })
  })

  describe("onKeydown()", () => {
    it("closes help dialog on Escape", () => {
      controller.openHelp()
      const event = { key: "Escape" }

      controller.onKeydown(event)

      expect(controller.helpDialogTarget.close).toHaveBeenCalled()
    })

    it("closes about dialog on Escape", () => {
      controller.openAbout()
      const event = { key: "Escape" }

      controller.onKeydown(event)

      expect(controller.aboutDialogTarget.close).toHaveBeenCalled()
    })

    it("does nothing for other keys", () => {
      controller.openHelp()
      const closeSpy = vi.spyOn(controller.helpDialogTarget, "close")
      closeSpy.mockClear()

      const event = { key: "Enter" }
      controller.onKeydown(event)

      expect(closeSpy).not.toHaveBeenCalled()
    })
  })

  describe("setupDialogClickOutside()", () => {
    it("closes dialog when clicking on backdrop", () => {
      controller.openHelp()

      // Simulate click on the dialog element itself (backdrop)
      const clickEvent = new MouseEvent("click", { bubbles: true })
      Object.defineProperty(clickEvent, "target", { value: controller.helpDialogTarget })
      controller.helpDialogTarget.dispatchEvent(clickEvent)

      expect(controller.helpDialogTarget.close).toHaveBeenCalled()
    })
  })

  describe("tab navigation", () => {
    it("includes editor extras in the tab order", () => {
      expect(controller.getTabOrder()).toEqual(["markdown", "shortcuts", "editor-extras"])
    })

    it("switches to the editor extras tab", () => {
      controller.switchToTab("editor-extras")

      expect(controller.currentTab).toBe("editor-extras")
      expect(controller.panelMarkdownTarget.classList.contains("hidden")).toBe(true)
      expect(controller.panelShortcutsTarget.classList.contains("hidden")).toBe(true)
      expect(controller.panelEditorExtrasTarget.classList.contains("hidden")).toBe(false)
      expect(controller.tabEditorExtrasTarget.getAttribute("aria-selected")).toBe("true")
      expect(controller.panelEditorExtrasTarget.innerHTML).toContain("Shift+Alt+Down")
      expect(controller.panelEditorExtrasTarget.innerHTML).toContain("Duplicate line down")
      expect(controller.panelEditorExtrasTarget.innerHTML).toContain("Ctrl+/")
    })

    it("ignores unknown tab names", () => {
      controller.switchToTab("markdown")
      controller.switchToTab("missing-tab")

      expect(controller.currentTab).toBe("markdown")
    })

    it("cycles through all three tabs with arrow keys", () => {
      const preventDefault = vi.fn()

      controller.switchToTab("markdown")
      controller.onTabKeydown({ key: "ArrowRight", preventDefault })
      expect(controller.currentTab).toBe("shortcuts")

      controller.onTabKeydown({ key: "ArrowRight", preventDefault })
      expect(controller.currentTab).toBe("editor-extras")

      controller.onTabKeydown({ key: "ArrowRight", preventDefault })
      expect(controller.currentTab).toBe("markdown")

      expect(preventDefault).toHaveBeenCalled()
    })

    it("cycles through all three tabs with the mouse wheel", () => {
      const preventDefault = vi.fn()

      controller.switchToTab("markdown")
      controller.onTabWheel({ deltaY: 10, deltaX: 0, preventDefault })
      expect(controller.currentTab).toBe("shortcuts")

      controller.onTabWheel({ deltaY: 10, deltaX: 0, preventDefault })
      expect(controller.currentTab).toBe("editor-extras")

      controller.onTabWheel({ deltaY: -10, deltaX: 0, preventDefault })
      expect(controller.currentTab).toBe("shortcuts")

      expect(preventDefault).toHaveBeenCalled()
    })

    it("re-renders the editor extras panel when translations load", () => {
      const previousT = window.t
      window.t = vi.fn((key) => ({
        "dialogs.help.editor_extras.editing": "Editing Translated",
        "dialogs.help.editor_extras.duplicate_line_down": "Duplicate line down translated"
      }[key] || key))

      window.dispatchEvent(new CustomEvent("frankmd:translations-loaded"))

      expect(controller.panelEditorExtrasTarget.innerHTML).toContain("Editing Translated")
      expect(controller.panelEditorExtrasTarget.innerHTML).toContain("Duplicate line down translated")

      window.t = previousT
    })
  })
})
