import { rewriteNoteHref } from "lib/url_utils"
import { fuzzyScore } from "lib/text_utils"

const DIACRITIC_PATTERN = /[\u0300-\u036f]/g
const EXTERNAL_SCHEME_PATTERN = /^[a-zA-Z][a-zA-Z\d+.-]*:/
const SAFE_APP_PREFIXES = [
  "/notes/",
  "/backup/",
  "/templates/",
  "/folders/",
  "/images/",
  "/youtube/",
  "/ai/",
  "/config",
  "/translations",
  "/shares/",
  "/s/",
  "/logs/",
  "/up"
]

function toForwardSlashes(path) {
  return String(path ?? "").replace(/\\/g, "/")
}

function trimLeadingSlashes(path) {
  return String(path ?? "").replace(/^\/+/, "")
}

function splitSegments(path) {
  return toForwardSlashes(path).split("/").filter(Boolean)
}

function withoutMarkdownExtension(path) {
  return String(path ?? "").replace(/\.md$/i, "")
}

function basename(path) {
  const segments = splitSegments(path)
  return segments[segments.length - 1] || ""
}

function parentDirectory(path) {
  const segments = splitSegments(path)
  if (segments.length <= 1) return ""

  return segments.slice(0, -1).join("/")
}

function foldForSearch(value) {
  return String(value ?? "")
    .normalize("NFD")
    .replace(DIACRITIC_PATTERN, "")
    .toLowerCase()
}

function lastSearchSegment(destinationText) {
  const normalized = String(destinationText ?? "").trim()
  if (!normalized) return ""

  const segments = normalized.split("/")
  return segments[segments.length - 1] || ""
}

function isMarkdownNotePath(path) {
  return /\.md$/i.test(String(path ?? ""))
}

function needsMarkdownDestinationWrapper(path) {
  return /[\s()]/.test(String(path ?? ""))
}

export function formatMarkdownLinkDestination(path) {
  const normalizedPath = String(path ?? "")
  if (!normalizedPath) return ""
  if (!needsMarkdownDestinationWrapper(normalizedPath)) return normalizedPath

  return `<${normalizedPath}>`
}

function hasSafeAppPrefix(path) {
  return SAFE_APP_PREFIXES.some((prefix) => path === prefix || path.startsWith(prefix))
}

function shouldSuppressAutocomplete(destinationText) {
  const normalized = String(destinationText ?? "").trim()
  if (!normalized) return false
  if (normalized.startsWith("#") || normalized.startsWith("?")) return true
  if (normalized.startsWith("//")) return true
  if (EXTERNAL_SCHEME_PATTERN.test(normalized)) return true
  if (normalized.startsWith("/") && hasSafeAppPrefix(normalized)) return true

  return false
}

function scoreCandidate(note, foldedQuery) {
  const noteName = withoutMarkdownExtension(basename(note.path))
  const notePath = withoutMarkdownExtension(note.path)
  const foldedName = foldForSearch(noteName)
  const foldedPath = foldForSearch(notePath)
  const basenameFuzzyScore = fuzzyScore(foldedName, foldedQuery)
  const pathFuzzyScore = fuzzyScore(foldedPath, foldedQuery)
  const basenameIncludes = foldedName.includes(foldedQuery)
  const pathIncludes = foldedPath.includes(foldedQuery)

  if (!basenameIncludes && !pathIncludes && basenameFuzzyScore <= 0 && pathFuzzyScore <= 0) {
    return 0
  }

  let score = 0

  if (foldedName === foldedQuery) score += 1600
  else if (foldedName.startsWith(foldedQuery)) score += 1200
  else if (basenameIncludes) score += 900

  if (foldedPath === foldedQuery) score += 300
  else if (foldedPath.startsWith(foldedQuery)) score += 220
  else if (pathIncludes) score += 120

  score += basenameFuzzyScore * 25
  score += pathFuzzyScore * 5
  score += Math.max(0, 40 - noteName.length)

  return score
}

export function buildRelativeNoteLinkPath(currentNotePath, targetNotePath) {
  const normalizedTarget = trimLeadingSlashes(toForwardSlashes(targetNotePath))
  if (!isMarkdownNotePath(normalizedTarget)) return ""

  const targetWithoutExtension = withoutMarkdownExtension(normalizedTarget)
  const currentPath = trimLeadingSlashes(toForwardSlashes(currentNotePath))
  if (!isMarkdownNotePath(currentPath)) return `/${targetWithoutExtension}`

  const currentDirectorySegments = splitSegments(withoutMarkdownExtension(currentPath)).slice(0, -1)
  const targetSegments = splitSegments(targetWithoutExtension)

  let sharedSegmentCount = 0
  while (
    sharedSegmentCount < currentDirectorySegments.length &&
    sharedSegmentCount < targetSegments.length &&
    currentDirectorySegments[sharedSegmentCount] === targetSegments[sharedSegmentCount]
  ) {
    sharedSegmentCount += 1
  }

  const upwardSegments = Array.from(
    { length: currentDirectorySegments.length - sharedSegmentCount },
    () => ".."
  )
  const downwardSegments = targetSegments.slice(sharedSegmentCount)
  const relativeSegments = [...upwardSegments, ...downwardSegments]

  return relativeSegments.join("/")
}

export function rankNoteLinkCandidates(notes, query, currentNotePath = null, limit = 3) {
  const normalizedQuery = foldForSearch(lastSearchSegment(query).trim())
  if (!normalizedQuery) return []

  const currentPath = trimLeadingSlashes(toForwardSlashes(currentNotePath))

  return Array.from(notes || [])
    .filter((note) => isMarkdownNotePath(note?.path))
    .filter((note) => trimLeadingSlashes(toForwardSlashes(note.path)) !== currentPath)
    .map((note) => {
      const normalizedPath = trimLeadingSlashes(toForwardSlashes(note.path))
      const score = scoreCandidate(note, normalizedQuery)
      if (score <= 0) return null

      return {
        path: normalizedPath,
        label: withoutMarkdownExtension(basename(normalizedPath)),
        detail: parentDirectory(withoutMarkdownExtension(normalizedPath)),
        insertText: formatMarkdownLinkDestination(
          buildRelativeNoteLinkPath(currentPath, normalizedPath)
        ),
        score
      }
    })
    .filter(Boolean)
    .sort((left, right) => {
      if (right.score !== left.score) return right.score - left.score
      if ((left.detail || "").length !== (right.detail || "").length) {
        return (left.detail || "").length - (right.detail || "").length
      }
      return left.path.localeCompare(right.path)
    })
    .slice(0, limit)
}

export function normalizeMarkdownNoteLinkDestinations(markdown, currentNotePath = null) {
  const source = String(markdown ?? "")
  if (!source.includes("](")) return source

  return source.replace(/(?<!!)\[([^\]\n]+)\]\(([^)\n]+)\)/g, (match, label, destination) => {
    const normalizedDestination = String(destination ?? "").trim()
    if (!normalizedDestination) return match
    if (normalizedDestination.startsWith("<") && normalizedDestination.endsWith(">")) return match
    if (!/\s/.test(normalizedDestination)) return match
    if (/["']/.test(normalizedDestination)) return match
    if (!rewriteNoteHref(normalizedDestination, currentNotePath)) return match

    return `[${label}](<${normalizedDestination}>)`
  })
}

export function findInlineMarkdownLinkDestination(lineText, cursorOffset) {
  const text = String(lineText ?? "")
  const offset = Math.max(0, Math.min(cursorOffset, text.length))

  for (let scanIndex = offset; scanIndex >= 0; scanIndex -= 1) {
    const markerIndex = text.lastIndexOf("](", scanIndex)
    if (markerIndex === -1) return null

    const labelStart = text.lastIndexOf("[", markerIndex)
    if (labelStart === -1) return null
    if (labelStart > 0 && text[labelStart - 1] === "!") {
      scanIndex = labelStart - 1
      continue
    }

    const destinationStart = markerIndex + 2
    const destinationEnd = text.indexOf(")", destinationStart)
    const normalizedDestinationEnd = destinationEnd === -1 ? text.length : destinationEnd
    if (offset < destinationStart || offset > normalizedDestinationEnd) {
      scanIndex = markerIndex - 1
      continue
    }

    const textBeforeCursor = text.slice(destinationStart, offset)
    if (textBeforeCursor.includes(")")) {
      scanIndex = markerIndex - 1
      continue
    }

    const destinationText = text.slice(destinationStart, normalizedDestinationEnd)
    if (shouldSuppressAutocomplete(destinationText)) return null

    return {
      from: destinationStart,
      to: normalizedDestinationEnd,
      query: textBeforeCursor,
      destinationText
    }
  }

  return null
}
