import { stripMarkdownFrontmatter } from "lib/markdown_frontmatter"

const MAX_OUTLINE_LEVEL = 4
const FENCE_PATTERN = /^\s{0,3}(`{3,}|~{3,})/
const ATX_HEADING_PATTERN = /^\s{0,3}(#{1,6})[ \t]+(.+?)[ \t]*#*\s*$/
const SETEXT_HEADING_PATTERN = /^\s{0,3}(=+|-+)[ \t]*$/

export function buildDocumentOutline(markdown) {
  const { content, frontmatterLines } = stripMarkdownFrontmatter(markdown || "")
  if (!content) return []

  const lines = content.split("\n")
  const outline = []
  let activeFence = null

  for (let index = 0; index < lines.length; index++) {
    const line = lines[index]
    const fenceMatch = line.match(FENCE_PATTERN)

    if (fenceMatch) {
      const fence = fenceMatch[1]
      if (!activeFence) {
        activeFence = { marker: fence[0], length: fence.length }
      } else if (fence[0] === activeFence.marker && fence.length >= activeFence.length) {
        activeFence = null
      }
      continue
    }

    if (activeFence) continue

    const atxMatch = line.match(ATX_HEADING_PATTERN)
    if (atxMatch) {
      const level = atxMatch[1].length
      if (level <= MAX_OUTLINE_LEVEL) {
        const text = normalizeHeadingText(atxMatch[2])
        if (text) {
          outline.push({
            level,
            text,
            line: frontmatterLines + index + 1
          })
        }
      }
      continue
    }

    if (index >= lines.length - 1) continue

    const nextLine = lines[index + 1]
    const setextMatch = nextLine.match(SETEXT_HEADING_PATTERN)
    if (!setextMatch || !isSetextHeadingCandidate(line)) continue

    const level = setextMatch[1][0] === "=" ? 1 : 2
    const text = normalizeHeadingText(line)
    if (!text) continue

    outline.push({
      level,
      text,
      line: frontmatterLines + index + 1
    })

    index += 1
  }

  return outline
}

function isSetextHeadingCandidate(line) {
  const trimmed = line.trim()
  if (!trimmed) return false
  if (/^\s{4,}/.test(line)) return false
  if (/^(>|[-*+]\s|\d+[.)]\s)/.test(trimmed)) return false
  return true
}

function normalizeHeadingText(text) {
  return (text || "")
    .replace(/!\[([^\]]*)\]\([^)]+\)/g, "$1")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/[*_~]/g, "")
    .replace(/\\([\\`*_{}[\]()#+\-.!])/g, "$1")
    .trim()
    .replace(/\s+/g, " ")
}
