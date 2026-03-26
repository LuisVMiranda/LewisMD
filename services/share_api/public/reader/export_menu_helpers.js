export const COPY_ITEMS = [
  { id: "copy-html", key: "copy_note" }
]

export const MARKDOWN_COPY_ITEM = { id: "copy-markdown", key: "copy_markdown" }

export const EXPORT_GROUP_ITEM = { id: "toggle-export-group", key: "export_files", expandable: true }

export const EXPORT_ITEMS = [
  { id: "export-html", key: "export_html" },
  { id: "export-txt", key: "export_txt" },
  { id: "print-pdf", key: "export_pdf" }
]

export const SHARE_CREATE_ITEMS = [
  { id: "create-share-link", key: "create_share_link", divider: true }
]

export const SHARE_ACTIVE_ITEMS = [
  { id: "copy-share-link", key: "copy_share_link", divider: true },
  { id: "refresh-share-link", key: "refresh_share_link" },
  { id: "disable-share-link", key: "disable_share_link", destructive: true }
]

export function buildExportMenuItems({
  markdownCopyable = true,
  shareState = {},
  exportGroupExpanded = false
} = {}) {
  const normalizedShareState = {
    shareable: Boolean(shareState.shareable),
    active: Boolean(shareState.active),
    url: shareState.url || null
  }

  const items = [ ...COPY_ITEMS ]

  if (markdownCopyable) {
    items.push(MARKDOWN_COPY_ITEM)
  }

  items.push(EXPORT_GROUP_ITEM)

  if (exportGroupExpanded) {
    items.push(...EXPORT_ITEMS.map((item) => ({ ...item, nested: true })))
  }

  if (normalizedShareState.shareable) {
    items.push(...(normalizedShareState.active ? SHARE_ACTIVE_ITEMS : SHARE_CREATE_ITEMS))
  }

  return items
}

export function renderExportMenuHtml({
  items,
  expanded = false,
  controllerIdentifier = "export-menu",
  translate = (key) => key
}) {
  return items.map((item) => `
    <button
      type="button"
      role="menuitem"
      class="w-full px-3 py-2 text-left text-sm hover:bg-[var(--theme-bg-hover)] flex items-center justify-between gap-2 ${item.divider ? "border-t border-[var(--theme-border)] mt-1 pt-3" : ""} ${item.destructive ? "text-red-600 dark:text-red-400" : ""} ${item.nested ? "pl-7 text-[var(--theme-text-muted)]" : ""}"
      ${item.expandable ? "" : `data-action-id="${item.id}"`}
      data-action="click->${controllerIdentifier}#${item.expandable ? "toggleExportGroup" : "select"}"
    >
      <span>${translate(`export_menu.${item.key}`)}</span>
      ${item.expandable ? `
        <svg class="w-3 h-3 shrink-0 transition-transform ${expanded ? "rotate-180" : ""}" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
        </svg>
      ` : ""}
    </button>
  `).join("")
}
