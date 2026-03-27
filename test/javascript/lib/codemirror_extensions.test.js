/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, vi } from "vitest"
import {
  createExtensions,
  createLineNumbers,
  createReadOnlyExtensions,
  LINE_NUMBER_MODES,
  themeCompartment,
  lineNumbersCompartment,
  readOnlyCompartment
} from "../../../app/javascript/lib/codemirror_extensions.js"

describe("codemirror_extensions", () => {
  describe("LINE_NUMBER_MODES", () => {
    it("defines OFF mode as 0", () => {
      expect(LINE_NUMBER_MODES.OFF).toBe(0)
    })

    it("defines ABSOLUTE mode as 1", () => {
      expect(LINE_NUMBER_MODES.ABSOLUTE).toBe(1)
    })

    it("defines RELATIVE mode as 2", () => {
      expect(LINE_NUMBER_MODES.RELATIVE).toBe(2)
    })
  })

  describe("createLineNumbers()", () => {
    it("returns empty array for OFF mode", () => {
      const result = createLineNumbers(LINE_NUMBER_MODES.OFF)
      expect(Array.isArray(result)).toBe(true)
      expect(result.length).toBe(0)
    })

    it("returns extensions array for ABSOLUTE mode", () => {
      const result = createLineNumbers(LINE_NUMBER_MODES.ABSOLUTE)
      expect(Array.isArray(result)).toBe(true)
      expect(result.length).toBeGreaterThan(0)
    })

    it("returns extensions array for RELATIVE mode", () => {
      const result = createLineNumbers(LINE_NUMBER_MODES.RELATIVE)
      expect(Array.isArray(result)).toBe(true)
      expect(result.length).toBeGreaterThan(0)
    })
  })

  describe("createExtensions()", () => {
    it("returns an array of extensions", () => {
      const extensions = createExtensions()
      expect(Array.isArray(extensions)).toBe(true)
      expect(extensions.length).toBeGreaterThan(0)
    })

    it("accepts placeholder text option", () => {
      const extensions = createExtensions({
        placeholderText: "Start writing..."
      })
      expect(extensions.length).toBeGreaterThan(0)
    })

    it("accepts font options", () => {
      const extensions = createExtensions({
        fontFamily: "'Monaco', monospace",
        fontSize: "16px",
        lineHeight: "1.8"
      })
      expect(extensions.length).toBeGreaterThan(0)
    })

    it("accepts line number mode option", () => {
      const extensionsOff = createExtensions({ lineNumberMode: LINE_NUMBER_MODES.OFF })
      const extensionsOn = createExtensions({ lineNumberMode: LINE_NUMBER_MODES.ABSOLUTE })
      expect(extensionsOff).toBeDefined()
      expect(extensionsOn).toBeDefined()
    })

    it("accepts onUpdate callback", () => {
      const onUpdate = vi.fn()
      const extensions = createExtensions({ onUpdate })
      expect(extensions.length).toBeGreaterThan(0)
    })

    it("accepts onSelectionChange callback", () => {
      const onSelectionChange = vi.fn()
      const extensions = createExtensions({ onSelectionChange })
      expect(extensions.length).toBeGreaterThan(0)
    })

    it("accepts onScroll callback", () => {
      const onScroll = vi.fn()
      const extensions = createExtensions({ onScroll })
      expect(extensions.length).toBeGreaterThan(0)
    })

    it("accepts note link autocomplete context callbacks", () => {
      const extensions = createExtensions({
        noteLinkAutocomplete: {
          getCurrentNotePath: () => "notes/example.md",
          getAvailableNotes: () => [{ path: "notes/other.md", file_type: "markdown" }]
        }
      })

      expect(extensions.length).toBeGreaterThan(0)
    })
  })

  describe("createReadOnlyExtensions()", () => {
    it("returns extensions array including read-only", () => {
      const extensions = createReadOnlyExtensions()
      expect(Array.isArray(extensions)).toBe(true)
      expect(extensions.length).toBeGreaterThan(0)
    })

    it("includes all base extensions", () => {
      const baseExtensions = createExtensions()
      const readOnlyExtensions = createReadOnlyExtensions()
      // Read-only extensions should have at least as many extensions as base plus read-only
      expect(readOnlyExtensions.length).toBeGreaterThanOrEqual(baseExtensions.length)
    })
  })

  describe("compartments", () => {
    it("exports themeCompartment", () => {
      expect(themeCompartment).toBeDefined()
      expect(typeof themeCompartment.of).toBe("function")
    })

    it("exports lineNumbersCompartment", () => {
      expect(lineNumbersCompartment).toBeDefined()
      expect(typeof lineNumbersCompartment.of).toBe("function")
    })

    it("exports readOnlyCompartment", () => {
      expect(readOnlyCompartment).toBeDefined()
      expect(typeof readOnlyCompartment.of).toBe("function")
    })
  })
})
