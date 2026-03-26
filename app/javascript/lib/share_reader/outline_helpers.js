const OUTLINE_HEADING_SELECTOR = ".export-article h1, .export-article h2, .export-article h3, .export-article h4"
const OUTLINE_ACTIVE_OFFSET = 96

function normalizeOutlineText(value) {
  return String(value || "").replace(/\s+/g, " ").trim()
}

function outlineIdBase(text, fallbackIndex = 0) {
  const normalized = normalizeOutlineText(text)
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")

  return normalized || `section-${fallbackIndex + 1}`
}

export function collectOutlineEntries(frameDocument) {
  if (!frameDocument?.querySelectorAll) return []

  const usedIds = new Map()

  return Array.from(frameDocument.querySelectorAll(OUTLINE_HEADING_SELECTOR))
    .map((heading, index) => {
      const text = normalizeOutlineText(heading.textContent)
      if (!text) return null

      const level = Number.parseInt(heading.tagName.slice(1), 10)
      const existingId = normalizeOutlineText(heading.id)
      const baseId = existingId || outlineIdBase(text, index)
      const occurrence = (usedIds.get(baseId) || 0) + 1
      usedIds.set(baseId, occurrence)

      const id = occurrence > 1 ? `${baseId}-${occurrence}` : baseId
      heading.id = id

      return {
        id,
        level,
        text,
        element: heading
      }
    })
    .filter(Boolean)
}

export function findActiveOutlineIndex(entries, frameWindow, offset = OUTLINE_ACTIVE_OFFSET) {
  if (!Array.isArray(entries) || entries.length === 0) return -1

  const scrollElement = frameWindow?.document?.scrollingElement || frameWindow?.document?.documentElement || null
  if (scrollElement && frameWindow?.innerHeight) {
    const maxScrollTop = Math.max(0, scrollElement.scrollHeight - frameWindow.innerHeight)
    if (scrollElement.scrollTop >= maxScrollTop - 4) return entries.length - 1
  }

  let activeIndex = 0

  entries.forEach((entry, index) => {
    if (entry?.element?.getBoundingClientRect && entry.element.getBoundingClientRect().top <= offset) {
      activeIndex = index
    }
  })

  return activeIndex
}
