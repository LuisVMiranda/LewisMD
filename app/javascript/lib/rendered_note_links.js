import { rewriteNoteHref } from "lib/url_utils"

export function rewriteNoteLinksInHtml(html, currentNotePath = null) {
  if (!html) return ""
  if (typeof document === "undefined") return html

  const container = document.createElement("div")
  container.innerHTML = html

  container.querySelectorAll("a[href]").forEach((anchor) => {
    const rewrittenHref = rewriteNoteHref(anchor.getAttribute("href"), currentNotePath)

    if (rewrittenHref) {
      anchor.setAttribute("href", rewrittenHref)
    }
  })

  return container.innerHTML
}
