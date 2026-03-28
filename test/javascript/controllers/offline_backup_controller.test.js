/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import OfflineBackupController from "../../../app/javascript/controllers/offline_backup_controller"

// Provide a minimal localStorage mock if jsdom doesn't have one
function ensureLocalStorage() {
  if (typeof globalThis.localStorage === "undefined" || !globalThis.localStorage.clear) {
    const store = {}
    globalThis.localStorage = {
      getItem: (key) => (key in store ? store[key] : null),
      setItem: (key, value) => { store[key] = String(value) },
      removeItem: (key) => { delete store[key] },
      clear: () => { for (const k of Object.keys(store)) delete store[k] },
      get length() { return Object.keys(store).length },
      key: (i) => Object.keys(store)[i] || null
    }
  }
}

describe("OfflineBackupController", () => {
  let application
  let container
  let controller

  beforeEach(async () => {
    ensureLocalStorage()
    localStorage.clear()

    document.body.innerHTML = `
      <div data-controller="offline-backup"></div>
    `

    container = document.querySelector('[data-controller="offline-backup"]')

    application = Application.start()
    application.register("offline-backup", OfflineBackupController)

    await new Promise((resolve) => setTimeout(resolve, 10))
    controller = application.getControllerForElementAndIdentifier(container, "offline-backup")
  })

  afterEach(() => {
    vi.restoreAllMocks()
    application.stop()
    document.body.innerHTML = ""
    localStorage.clear()
  })

  describe("save()", () => {
    it("writes content and timestamp to localStorage", () => {
      const before = Date.now()
      controller.save("notes/test.md", "hello world")
      const after = Date.now()

      const raw = localStorage.getItem("frankmd:backup:notes/test.md")
      expect(raw).not.toBeNull()

      const data = JSON.parse(raw)
      expect(data.content).toBe("hello world")
      expect(data.timestamp).toBeGreaterThanOrEqual(before)
      expect(data.timestamp).toBeLessThanOrEqual(after)
    })

    it("handles localStorage quota exceeded gracefully", () => {
      const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {})
      const setItemSpy = vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
        throw new DOMException("QuotaExceededError")
      })

      // Should not throw
      expect(() => controller.save("test.md", "content")).not.toThrow()
      expect(warnSpy).toHaveBeenCalledWith("localStorage backup failed:", expect.any(DOMException))
      expect(setItemSpy).toHaveBeenCalled()
    })
  })

  describe("check()", () => {
    it("returns null when no backup exists", () => {
      const result = controller.check("test.md", "server content")
      expect(result).toBeNull()
    })

    it("returns data when backup differs from server content", () => {
      controller.save("test.md", "local backup content")

      const result = controller.check("test.md", "server content")
      expect(result).not.toBeNull()
      expect(result.content).toBe("local backup content")
      expect(result.timestamp).toBeDefined()
    })

    it("returns null and auto-clears when backup matches server content", () => {
      controller.save("test.md", "same content")

      const result = controller.check("test.md", "same content")
      expect(result).toBeNull()

      // Should have been cleared
      expect(localStorage.getItem("frankmd:backup:test.md")).toBeNull()
    })

    it("returns null and auto-clears when backup is corrupt JSON", () => {
      localStorage.setItem("frankmd:backup:test.md", "not valid json{{{")

      const result = controller.check("test.md", "server content")
      expect(result).toBeNull()

      // Should have been cleared
      expect(localStorage.getItem("frankmd:backup:test.md")).toBeNull()
    })
  })

  describe("clear()", () => {
    it("removes backup for a specific path", () => {
      controller.save("test.md", "content")
      controller.save("other.md", "other content")

      controller.clear("test.md")

      expect(localStorage.getItem("frankmd:backup:test.md")).toBeNull()
      expect(localStorage.getItem("frankmd:backup:other.md")).not.toBeNull()
    })
  })

  describe("rename()", () => {
    it("moves a backup record to the renamed path", () => {
      controller.save("drafts/old-name.md", "content")

      expect(controller.rename("drafts/old-name.md", "drafts/new-name.md")).toBe(true)
      expect(localStorage.getItem("frankmd:backup:drafts/old-name.md")).toBeNull()

      const moved = JSON.parse(localStorage.getItem("frankmd:backup:drafts/new-name.md"))
      expect(moved.content).toBe("content")
    })
  })

  describe("clearAll()", () => {
    it("removes all frankmd backup keys", () => {
      controller.save("test.md", "content 1")
      controller.save("folder/note.md", "content 2")
      localStorage.setItem("unrelated-key", "keep me")

      controller.clearAll()

      expect(localStorage.getItem("frankmd:backup:test.md")).toBeNull()
      expect(localStorage.getItem("frankmd:backup:folder/note.md")).toBeNull()
      expect(localStorage.getItem("unrelated-key")).toBe("keep me")
    })
  })
})
