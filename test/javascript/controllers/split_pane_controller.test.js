/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import SplitPaneController from "../../../app/javascript/controllers/split_pane_controller.js"

describe("SplitPaneController", () => {
  let application
  let controller
  let element

  beforeEach(async () => {
    document.body.innerHTML = `
      <div data-controller="split-pane">
        <aside data-split-pane-target="rightPane"></aside>
      </div>
    `

    element = document.querySelector('[data-controller="split-pane"]')
    application = Application.start()
    application.register("split-pane", SplitPaneController)

    await new Promise((resolve) => setTimeout(resolve, 0))
    controller = application.getControllerForElementAndIdentifier(element, "split-pane")
  })

  afterEach(() => {
    application.stop()
    vi.restoreAllMocks()
  })

  it("clamps applied width inside the supported preview bounds", () => {
    controller.applyWidth(12)
    expect(controller.currentWidthPct).toBe(20)
    expect(controller.rightPaneTarget.style.getPropertyValue("--preview-width")).toBe("20%")

    controller.applyWidth(82)
    expect(controller.currentWidthPct).toBe(70)
    expect(controller.rightPaneTarget.style.getPropertyValue("--preview-width")).toBe("70%")
  })

  it("dispatches a rounded width-changed event when dragging ends", () => {
    controller.isDragging = true
    controller.currentWidthPct = 54.6
    const dispatchSpy = vi.spyOn(controller, "dispatch")

    controller.onPointerUp(new Event("pointerup"))

    expect(controller.isDragging).toBe(false)
    expect(dispatchSpy).toHaveBeenCalledWith("width-changed", {
      detail: { width: 55 }
    })
  })
})
