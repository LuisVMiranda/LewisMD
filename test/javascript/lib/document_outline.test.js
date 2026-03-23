/**
 * @vitest-environment jsdom
 */
import { describe, it, expect } from "vitest"
import { buildDocumentOutline } from "../../../app/javascript/lib/document_outline.js"

describe("buildDocumentOutline", () => {
  it("extracts ATX headings with source lines", () => {
    expect(buildDocumentOutline("# Title\n\n## Section\nBody")).toEqual([
      { level: 1, text: "Title", line: 1 },
      { level: 2, text: "Section", line: 3 }
    ])
  })

  it("accounts for stripped frontmatter in reported line numbers", () => {
    const markdown = [
      "---",
      "title: Example",
      "---",
      "",
      "# Heading",
      "## Subheading"
    ].join("\n")

    expect(buildDocumentOutline(markdown)).toEqual([
      { level: 1, text: "Heading", line: 5 },
      { level: 2, text: "Subheading", line: 6 }
    ])
  })

  it("supports setext headings and ignores levels deeper than h4", () => {
    const markdown = [
      "Title",
      "=====",
      "",
      "Section",
      "-----",
      "",
      "##### Hidden"
    ].join("\n")

    expect(buildDocumentOutline(markdown)).toEqual([
      { level: 1, text: "Title", line: 1 },
      { level: 2, text: "Section", line: 4 }
    ])
  })

  it("ignores headings inside fenced code blocks", () => {
    const markdown = [
      "# Visible",
      "",
      "```md",
      "## Hidden",
      "```",
      "",
      "## Also Visible"
    ].join("\n")

    expect(buildDocumentOutline(markdown)).toEqual([
      { level: 1, text: "Visible", line: 1 },
      { level: 2, text: "Also Visible", line: 7 }
    ])
  })

  it("keeps repeated headings and normalizes inline markdown", () => {
    const markdown = [
      "## [Alpha](https://example.com)",
      "",
      "## `Alpha`"
    ].join("\n")

    expect(buildDocumentOutline(markdown)).toEqual([
      { level: 2, text: "Alpha", line: 1 },
      { level: 2, text: "Alpha", line: 3 }
    ])
  })
})
