function normalizeString(value) {
  const normalized = String(value ?? "").trim()
  return normalized || null
}

function normalizePlainText(value) {
  return String(value ?? "").replace(/\r\n/g, "\n").replace(/\r/g, "\n")
}

function deriveTitle(title, path) {
  const explicitTitle = normalizeString(title)
  if (explicitTitle) return explicitTitle

  const normalizedPath = normalizeString(path)
  if (!normalizedPath) return "Untitled"

  const leaf = normalizedPath.split("/").pop() || normalizedPath
  return leaf.replace(/\.[^.]+$/, "") || "Untitled"
}

function normalizeZoom(value) {
  const zoom = Number(value)
  return Number.isFinite(zoom) ? Math.round(zoom) : null
}

export function buildRenderedDocumentPayload({
  title,
  path,
  html,
  plainText,
  themeId,
  typography = {}
} = {}) {
  return {
    source: "preview",
    title: deriveTitle(title, path),
    path: normalizeString(path),
    html: String(html ?? ""),
    plainText: normalizePlainText(plainText),
    themeId: normalizeString(themeId),
    typography: {
      zoom: normalizeZoom(typography.zoom),
      fontFamily: normalizeString(typography.fontFamily),
      fontSize: normalizeString(typography.fontSize)
    }
  }
}
