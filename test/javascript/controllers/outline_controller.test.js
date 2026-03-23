/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import OutlineController from "../../../app/javascript/controllers/outline_controller.js"

describe("OutlineController", () => {
  let application
  let controller
  let element

  beforeEach(async () => {
    document.body.innerHTML = `
      <div data-controller="outline">
        <div data-outline-target="section" class="hidden">
          <div data-outline-target="list"></div>
          <p data-outline-target="empty" class="hidden">No headings yet</p>
        </div>
      </div>
    `

    element = document.querySelector('[data-controller="outline"]')
    application = Application.start()
    application.register("outline", OutlineController)

    await new Promise((resolve) => setTimeout(resolve, 0))
    controller = application.getControllerForElementAndIdentifier(element, "outline")
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
  })

  it("stays hidden until a markdown outline is provided", () => {
    expect(controller.sectionTarget.classList.contains("hidden")).toBe(true)
  })

  it("renders outline items and marks the active heading", () => {
    controller.update({
      visible: true,
      items: [
        { level: 1, text: "Title", line: 1 },
        { level: 2, text: "Section", line: 5 }
      ]
    })
    controller.setActiveLine(5)

    const items = controller.listTarget.querySelectorAll("[data-line]")
    expect(controller.sectionTarget.classList.contains("hidden")).toBe(false)
    expect(items).toHaveLength(2)
    expect(items[0].textContent).toBe("Title")
    expect(items[1].dataset.active).toBe("true")
  })

  it("shows an empty state when the markdown note has no headings", () => {
    controller.update({ visible: true, items: [] })

    expect(controller.sectionTarget.classList.contains("hidden")).toBe(false)
    expect(controller.emptyTarget.classList.contains("hidden")).toBe(false)
    expect(controller.listTarget.children).toHaveLength(0)
  })

  it("dispatches the selected line number when an item is clicked", () => {
    controller.update({
      visible: true,
      items: [{ level: 2, text: "Section", line: 8 }]
    })

    controller.dispatch = vi.fn()

    controller.select({
      currentTarget: controller.listTarget.querySelector("[data-line='8']")
    })

    expect(controller.dispatch).toHaveBeenCalledWith("selected", {
      detail: { lineNumber: 8 }
    })
  })

  it("fully hides the section again when asked", () => {
    controller.update({
      visible: true,
      items: [{ level: 1, text: "Title", line: 1 }]
    })

    controller.hide()

    expect(controller.sectionTarget.classList.contains("hidden")).toBe(true)
    expect(controller.listTarget.children).toHaveLength(0)
  })
})
