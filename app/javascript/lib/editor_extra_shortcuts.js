// Curated editor-native shortcuts that LewisMD exposes through CodeMirror's
// built-in keymaps. This list is intentionally small and help-focused rather
// than a full dump of every CodeMirror binding.

export const EDITOR_EXTRA_SHORTCUT_GROUPS = Object.freeze({
  editing: "editing",
  selection: "selection"
})

export const EDITOR_EXTRA_SHORTCUT_SECTIONS = Object.freeze([
  {
    group: EDITOR_EXTRA_SHORTCUT_GROUPS.editing,
    titleKey: "dialogs.help.editor_extras.editing",
    defaultTitle: "Editing"
  },
  {
    group: EDITOR_EXTRA_SHORTCUT_GROUPS.selection,
    titleKey: "dialogs.help.editor_extras.selection",
    defaultTitle: "Selection & Comments"
  }
])

export const EDITOR_EXTRA_SHORTCUTS = Object.freeze([
  {
    id: "duplicateLineDown",
    group: EDITOR_EXTRA_SHORTCUT_GROUPS.editing,
    source: "defaultKeymap",
    binding: "Shift-Alt-ArrowDown",
    display: "Shift+Alt+Down",
    command: "copyLineDown",
    labelKey: "dialogs.help.editor_extras.duplicate_line_down",
    defaultLabel: "Duplicate line down"
  },
  {
    id: "duplicateLineUp",
    group: EDITOR_EXTRA_SHORTCUT_GROUPS.editing,
    source: "defaultKeymap",
    binding: "Shift-Alt-ArrowUp",
    display: "Shift+Alt+Up",
    command: "copyLineUp",
    labelKey: "dialogs.help.editor_extras.duplicate_line_up",
    defaultLabel: "Duplicate line up"
  },
  {
    id: "moveLineDown",
    group: EDITOR_EXTRA_SHORTCUT_GROUPS.editing,
    source: "defaultKeymap",
    binding: "Alt-ArrowDown",
    display: "Alt+Down",
    command: "moveLineDown",
    labelKey: "dialogs.help.editor_extras.move_line_down",
    defaultLabel: "Move line down"
  },
  {
    id: "moveLineUp",
    group: EDITOR_EXTRA_SHORTCUT_GROUPS.editing,
    source: "defaultKeymap",
    binding: "Alt-ArrowUp",
    display: "Alt+Up",
    command: "moveLineUp",
    labelKey: "dialogs.help.editor_extras.move_line_up",
    defaultLabel: "Move line up"
  },
  {
    id: "deleteLine",
    group: EDITOR_EXTRA_SHORTCUT_GROUPS.editing,
    source: "defaultKeymap",
    binding: "Shift-Mod-k",
    display: "Ctrl+Shift+K",
    command: "deleteLine",
    labelKey: "dialogs.help.editor_extras.delete_line",
    defaultLabel: "Delete line"
  },
  {
    id: "insertBlankLine",
    group: EDITOR_EXTRA_SHORTCUT_GROUPS.editing,
    source: "defaultKeymap",
    binding: "Mod-Enter",
    display: "Ctrl+Enter",
    command: "insertBlankLine",
    labelKey: "dialogs.help.editor_extras.insert_blank_line",
    defaultLabel: "Insert blank line"
  },
  {
    id: "toggleLineComment",
    group: EDITOR_EXTRA_SHORTCUT_GROUPS.selection,
    source: "defaultKeymap",
    binding: "Mod-/",
    display: "Ctrl+/",
    command: "toggleComment",
    labelKey: "dialogs.help.editor_extras.toggle_line_comment",
    defaultLabel: "Toggle line comment"
  },
  {
    id: "toggleBlockComment",
    group: EDITOR_EXTRA_SHORTCUT_GROUPS.selection,
    source: "defaultKeymap",
    binding: "Alt-A",
    display: "Shift+Alt+A",
    command: "toggleBlockComment",
    labelKey: "dialogs.help.editor_extras.toggle_block_comment",
    defaultLabel: "Toggle block comment"
  },
  {
    id: "selectNextOccurrence",
    group: EDITOR_EXTRA_SHORTCUT_GROUPS.selection,
    source: "searchKeymap",
    binding: "Mod-d",
    display: "Ctrl+D",
    command: "selectNextOccurrence",
    labelKey: "dialogs.help.editor_extras.select_next_occurrence",
    defaultLabel: "Select next occurrence"
  },
  {
    id: "selectAllOccurrences",
    group: EDITOR_EXTRA_SHORTCUT_GROUPS.selection,
    source: "searchKeymap",
    binding: "Mod-Shift-l",
    display: "Ctrl+Shift+L",
    command: "selectSelectionMatches",
    labelKey: "dialogs.help.editor_extras.select_all_occurrences",
    defaultLabel: "Select all occurrences"
  }
])

export function getEditorExtraShortcutsByGroup(group) {
  return EDITOR_EXTRA_SHORTCUTS.filter((shortcut) => shortcut.group === group)
}

export function getEditorExtraShortcut(id) {
  return EDITOR_EXTRA_SHORTCUTS.find((shortcut) => shortcut.id === id) || null
}
