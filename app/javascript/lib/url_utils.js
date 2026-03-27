// URL utility functions - Pure functions for URL manipulation
// Extracted for testability

/**
 * Encode path for URL (encode each segment, preserve slashes)
 * @param {string} path - File path to encode
 * @returns {string} - URL-encoded path
 */
export function encodePath(path) {
  if (!path) return ""
  return path.split("/").map(segment => encodeURIComponent(segment)).join("/")
}

function splitHrefParts(href) {
  const normalized = String(href ?? "").trim()
  const match = normalized.match(/^([^?#]*)(\?[^#]*)?(#.*)?$/)

  return {
    path: match?.[1] || "",
    query: match?.[2] || "",
    hash: match?.[3] || ""
  }
}

function hasExternalScheme(value) {
  return /^[a-zA-Z][a-zA-Z\d+.-]*:/.test(value)
}

function unwrapMarkdownDestination(path) {
  const normalized = String(path ?? "").trim()
  if (normalized.startsWith("<") && normalized.endsWith(">")) {
    return normalized.slice(1, -1)
  }

  return normalized
}

const NON_NOTE_FILE_EXTENSIONS = new Set([
  ".avif",
  ".bmp",
  ".csv",
  ".doc",
  ".docx",
  ".gif",
  ".htm",
  ".html",
  ".jpeg",
  ".jpg",
  ".json",
  ".js",
  ".mov",
  ".mp3",
  ".mp4",
  ".pdf",
  ".png",
  ".ppt",
  ".pptx",
  ".svg",
  ".tar",
  ".txt",
  ".wav",
  ".webm",
  ".webp",
  ".xls",
  ".xlsx",
  ".xml",
  ".yaml",
  ".yml",
  ".zip"
])

function normalizePathSegments(path) {
  const segments = []

  for (const segment of path.split("/")) {
    if (!segment || segment === ".") continue

    if (segment === "..") {
      if (segments.length === 0) return null
      segments.pop()
      continue
    }

    segments.push(segment)
  }

  return segments.join("/")
}

function noteLikeLeaf(leaf) {
  if (!leaf) return false
  if (leaf === ".fed") return true

  const extensionIndex = leaf.lastIndexOf(".")
  if (extensionIndex === -1) return true

  const extension = leaf.slice(extensionIndex).toLowerCase()
  return extension === ".md" || !NON_NOTE_FILE_EXTENSIONS.has(extension)
}

function decodePathSegments(path) {
  return String(path ?? "")
    .split("/")
    .map((segment) => {
      try {
        return decodeURIComponent(segment)
      } catch {
        return segment
      }
    })
    .join("/")
}

function normalizeNotePath(path) {
  const normalized = normalizePathSegments(
    decodePathSegments(String(path ?? "").replace(/\\/g, "/").replace(/^\/+/, ""))
  )
  if (!normalized) return null

  const leaf = normalized.split("/").pop() || ""
  if (!noteLikeLeaf(leaf)) return null
  if (leaf === ".fed" || normalized.toLowerCase().endsWith(".md")) return normalized

  return `${normalized}.md`
}

function isPreservedAppPath(path) {
  if (!path || path === "/") return true

  const preservedPrefixes = [
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

  return preservedPrefixes.some((prefix) => path === prefix || path.startsWith(prefix))
}

function resolveRelativeNotePath(path, currentNotePath) {
  if (path.startsWith("/")) {
    return normalizeNotePath(path)
  }

  const currentDirectory = String(currentNotePath ?? "").split("/").slice(0, -1).join("/")
  const combined = currentDirectory ? `${currentDirectory}/${path}` : path

  return normalizeNotePath(combined)
}

export function rewriteNoteHref(href, currentNotePath = null) {
  const normalizedHref = String(href ?? "").trim()
  if (!normalizedHref) return null
  if (normalizedHref.startsWith("#") || normalizedHref.startsWith("?")) return null
  if (normalizedHref.startsWith("//")) return null
  if (hasExternalScheme(normalizedHref)) return null

  const { path, query, hash } = splitHrefParts(normalizedHref)
  if (!path) return null

  const unwrappedPath = unwrapMarkdownDestination(path)

  if (unwrappedPath.startsWith("/") && isPreservedAppPath(unwrappedPath)) {
    return `${unwrappedPath}${query}${hash}`
  }

  const resolvedNotePath = resolveRelativeNotePath(unwrappedPath, currentNotePath)
  if (!resolvedNotePath) return null

  return `/notes/${encodePath(resolvedNotePath)}${query}${hash}`
}

export function extractNotePathFromLewisUrl(href, currentOrigin = null) {
  const normalizedHref = String(href ?? "").trim()
  if (!normalizedHref) return null

  const origin = currentOrigin || window.location.origin
  const url = new URL(normalizedHref, origin)

  if (url.origin !== origin) return null
  if (!url.pathname.startsWith("/notes/")) return null

  const encodedPath = url.pathname.slice("/notes/".length)
  if (!encodedPath) return null

  return encodedPath.split("/").map((segment) => decodeURIComponent(segment)).join("/")
}

/**
 * Extract YouTube video ID from various URL formats
 * @param {string} url - YouTube URL or video ID
 * @returns {string|null} - 11-character video ID or null
 */
export function extractYouTubeId(url) {
  if (!url) return null

  // Match various YouTube URL formats
  const patterns = [
    /(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/|youtube\.com\/v\/)([a-zA-Z0-9_-]{11})/,
    /^([a-zA-Z0-9_-]{11})$/ // Just the ID
  ]

  for (const pattern of patterns) {
    const match = url.match(pattern)
    if (match) return match[1]
  }

  return null
}
