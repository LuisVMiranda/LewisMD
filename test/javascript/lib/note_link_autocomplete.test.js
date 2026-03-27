import { describe, it, expect } from "vitest"
import {
  buildRelativeNoteLinkPath,
  findInlineMarkdownLinkDestination,
  formatMarkdownLinkDestination,
  normalizeMarkdownNoteLinkDestinations,
  rankNoteLinkCandidates
} from "../../../app/javascript/lib/note_link_autocomplete.js"

describe("buildRelativeNoteLinkPath", () => {
  it("builds same-folder relative note paths without an extension", () => {
    expect(
      buildRelativeNoteLinkPath(
        "Personal/Studies/Español/2026/Lesson_01.md",
        "Personal/Studies/Español/2026/Practice_Area_A2.md"
      )
    ).toBe("Practice_Area_A2")
  })

  it("builds parent-folder relative note paths", () => {
    expect(
      buildRelativeNoteLinkPath(
        "Folder 1/Folder 2/note2.md",
        "Folder 1/note1.md"
      )
    ).toBe("../note1")
  })

  it("builds sibling-folder relative note paths", () => {
    expect(
      buildRelativeNoteLinkPath(
        "Folder 1/Folder 2/note2.md",
        "Folder 1/Folder 3/note3.md"
      )
    ).toBe("../Folder 3/note3")
  })

  it("falls back to a notes-root absolute path when the current note path is unavailable", () => {
    expect(buildRelativeNoteLinkPath(null, "Folder 1/Folder 2/note2.md")).toBe("/Folder 1/Folder 2/note2")
  })
})

describe("rankNoteLinkCandidates", () => {
  const notes = [
    { path: "Folder 1/Folder 2/Study_Syllabus_A2.md", name: "Study_Syllabus_A2", file_type: "markdown" },
    { path: "Folder 1/Folder 2/Practice_Area_A2.md", name: "Practice_Area_A2", file_type: "markdown" },
    { path: "Folder 1/Folder 3/Study_Syllabus_A2.md", name: "Study_Syllabus_A2", file_type: "markdown" },
    { path: "Folder 1/Folder 4/Study_Guide.md", name: "Study_Guide", file_type: "markdown" },
    { path: "Folder 1/Folder 2/Study_Notes.pdf", name: "Study_Notes.pdf", file_type: "pdf" },
    { path: "Folder 1/Folder 2/Español_Gramática.md", name: "Español_Gramática", file_type: "markdown" }
  ]

  it("caps results at the top three matches", () => {
    const results = rankNoteLinkCandidates(notes, "study", "Folder 1/Folder 2/note2.md")
    expect(results).toHaveLength(3)
  })

  it("prefers basename matches over path-only matches", () => {
    const results = rankNoteLinkCandidates(notes, "practice", "Folder 1/Folder 2/note2.md")
    expect(results[0].label).toBe("Practice_Area_A2")
  })

  it("excludes the current note from the candidates", () => {
    const results = rankNoteLinkCandidates(
      notes,
      "practice",
      "Folder 1/Folder 2/Practice_Area_A2.md"
    )

    expect(results.some((candidate) => candidate.path === "Folder 1/Folder 2/Practice_Area_A2.md")).toBe(false)
  })

  it("preserves original accented characters in inserted paths while matching accent-insensitively", () => {
    const results = rankNoteLinkCandidates(notes, "gramatica", "Folder 1/Folder 2/note2.md")

    expect(results[0]).toMatchObject({
      label: "Español_Gramática",
      insertText: "Español_Gramática"
    })
  })

  it("provides parent-path detail for disambiguation", () => {
    const results = rankNoteLinkCandidates(notes, "syllabus", "Folder 1/Folder 2/note2.md")

    expect(results[0].detail).toBe("Folder 1/Folder 2")
    expect(results[1].detail).toBe("Folder 1/Folder 3")
  })

  it("wraps inserted destinations when the relative path contains spaces", () => {
    const results = rankNoteLinkCandidates(
      [
        { path: "Folder 1/Wise Up/Notes-27.03.md", name: "Notes-27.03", file_type: "markdown" }
      ],
      "notes",
      "Folder 1/Folder 2/Study_Syllabus_A2.md"
    )

    expect(results[0].insertText).toBe("<../Wise Up/Notes-27.03>")
  })
})

describe("formatMarkdownLinkDestination", () => {
  it("keeps simple destinations unchanged", () => {
    expect(formatMarkdownLinkDestination("../Study_Syllabus_A2")).toBe("../Study_Syllabus_A2")
  })

  it("wraps destinations that contain spaces", () => {
    expect(formatMarkdownLinkDestination("../Wise Up/Notes-27.03")).toBe("<../Wise Up/Notes-27.03>")
  })
})

describe("normalizeMarkdownNoteLinkDestinations", () => {
  it("wraps note-like destinations with spaces so markdown renders them as links", () => {
    expect(
      normalizeMarkdownNoteLinkDestinations(
        "[Jump](../Wise Up/Notes-27.03)",
        "Folder 1/Folder 2/Study_Syllabus_A2.md"
      )
    ).toBe("[Jump](<../Wise Up/Notes-27.03>)")
  })

  it("leaves external links untouched", () => {
    expect(normalizeMarkdownNoteLinkDestinations("[Docs](https://example.com/a path)"))
      .toBe("[Docs](https://example.com/a path)")
  })
})

describe("findInlineMarkdownLinkDestination", () => {
  it("detects the current destination token inside an inline markdown link", () => {
    const text = "Practice: [Click here!](Study_Syll)"
    const cursorOffset = text.length - 1

    expect(findInlineMarkdownLinkDestination(text, cursorOffset)).toMatchObject({
      from: 24,
      to: 34,
      query: "Study_Syll",
      destinationText: "Study_Syll"
    })
  })

  it("does not activate for image syntax", () => {
    expect(findInlineMarkdownLinkDestination("![Alt](diagram)", 14)).toBeNull()
  })

  it("does not activate for external urls or anchors", () => {
    expect(findInlineMarkdownLinkDestination("[Site](https://example.com)", 28)).toBeNull()
    expect(findInlineMarkdownLinkDestination("[Jump](#outline)", 15)).toBeNull()
  })
})
