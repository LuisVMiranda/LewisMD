/**
 * @vitest-environment jsdom
 */
import { describe, it, expect } from "vitest"
import { defaultKeymap } from "@codemirror/commands"
import { searchKeymap } from "@codemirror/search"
import {
  EDITOR_EXTRA_SHORTCUT_GROUPS,
  EDITOR_EXTRA_SHORTCUTS,
  getEditorExtraShortcut,
  getEditorExtraShortcutsByGroup
} from "../../../app/javascript/lib/editor_extra_shortcuts"

describe("EDITOR_EXTRA_SHORTCUTS", () => {
  it("contains the curated hidden editor actions worth documenting", () => {
    expect(EDITOR_EXTRA_SHORTCUTS.map((shortcut) => shortcut.id)).toEqual([
      "duplicateLineDown",
      "duplicateLineUp",
      "moveLineDown",
      "moveLineUp",
      "deleteLine",
      "insertBlankLine",
      "toggleLineComment",
      "toggleBlockComment",
      "selectNextOccurrence",
      "selectAllOccurrences"
    ])
  })

  it("keeps ids, bindings, and label keys unique", () => {
    const ids = EDITOR_EXTRA_SHORTCUTS.map((shortcut) => shortcut.id)
    const bindings = EDITOR_EXTRA_SHORTCUTS.map((shortcut) => `${shortcut.source}:${shortcut.binding}`)
    const labelKeys = EDITOR_EXTRA_SHORTCUTS.map((shortcut) => shortcut.labelKey)

    expect(new Set(ids).size).toBe(ids.length)
    expect(new Set(bindings).size).toBe(bindings.length)
    expect(new Set(labelKeys).size).toBe(labelKeys.length)
  })

  it("matches bindings that LewisMD actually enables through CodeMirror keymaps", () => {
    const sources = { defaultKeymap, searchKeymap }

    for (const shortcut of EDITOR_EXTRA_SHORTCUTS) {
      const binding = sources[shortcut.source].find((entry) => entry.key === shortcut.binding)

      expect(
        binding,
        `${shortcut.id} should exist in ${shortcut.source} as ${shortcut.binding}`
      ).toBeDefined()
    }
  })
})

describe("editor extra shortcut helpers", () => {
  it("returns shortcuts grouped for future Help UI sections", () => {
    expect(getEditorExtraShortcutsByGroup(EDITOR_EXTRA_SHORTCUT_GROUPS.editing).map((shortcut) => shortcut.id)).toEqual([
      "duplicateLineDown",
      "duplicateLineUp",
      "moveLineDown",
      "moveLineUp",
      "deleteLine",
      "insertBlankLine"
    ])

    expect(getEditorExtraShortcutsByGroup(EDITOR_EXTRA_SHORTCUT_GROUPS.selection).map((shortcut) => shortcut.id)).toEqual([
      "toggleLineComment",
      "toggleBlockComment",
      "selectNextOccurrence",
      "selectAllOccurrences"
    ])
  })

  it("returns a shortcut by id and null for unknown ids", () => {
    expect(getEditorExtraShortcut("duplicateLineDown")).toEqual(expect.objectContaining({
      display: "Shift+Alt+Down",
      command: "copyLineDown"
    }))

    expect(getEditorExtraShortcut("missing-shortcut")).toBeNull()
  })
})
