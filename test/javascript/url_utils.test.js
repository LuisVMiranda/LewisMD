import { describe, it, expect } from "vitest"
import {
  encodePath,
  rewriteNoteHref,
  extractYouTubeId
} from "../../app/javascript/lib/url_utils.js"

describe("encodePath", () => {
  it("encodes path segments", () => {
    expect(encodePath("hello world/test file.md")).toBe("hello%20world/test%20file.md")
  })

  it("preserves forward slashes", () => {
    expect(encodePath("a/b/c")).toBe("a/b/c")
  })

  it("encodes special characters", () => {
    expect(encodePath("file#1.md")).toBe("file%231.md")
    expect(encodePath("file?query.md")).toBe("file%3Fquery.md")
  })

  it("handles empty path", () => {
    expect(encodePath("")).toBe("")
    expect(encodePath(null)).toBe("")
    expect(encodePath(undefined)).toBe("")
  })

  it("handles deeply nested paths", () => {
    expect(encodePath("a/b/c/d/e.md")).toBe("a/b/c/d/e.md")
  })

  it("encodes unicode characters", () => {
    expect(encodePath("café/résumé.md")).toBe("caf%C3%A9/r%C3%A9sum%C3%A9.md")
  })
})

describe("extractYouTubeId", () => {
  it("extracts ID from standard watch URL", () => {
    expect(extractYouTubeId("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
      .toBe("dQw4w9WgXcQ")
  })

  it("extracts ID from short URL", () => {
    expect(extractYouTubeId("https://youtu.be/dQw4w9WgXcQ"))
      .toBe("dQw4w9WgXcQ")
  })

  it("extracts ID from embed URL", () => {
    expect(extractYouTubeId("https://www.youtube.com/embed/dQw4w9WgXcQ"))
      .toBe("dQw4w9WgXcQ")
  })

  it("extracts ID from v/ URL", () => {
    expect(extractYouTubeId("https://www.youtube.com/v/dQw4w9WgXcQ"))
      .toBe("dQw4w9WgXcQ")
  })

  it("returns the ID if just passed an ID", () => {
    expect(extractYouTubeId("dQw4w9WgXcQ")).toBe("dQw4w9WgXcQ")
  })

  it("returns null for non-YouTube URLs", () => {
    expect(extractYouTubeId("https://vimeo.com/123456")).toBeNull()
  })

  it("returns null for invalid URLs", () => {
    expect(extractYouTubeId("not a url")).toBeNull()
  })

  it("returns null for empty input", () => {
    expect(extractYouTubeId("")).toBeNull()
    expect(extractYouTubeId(null)).toBeNull()
    expect(extractYouTubeId(undefined)).toBeNull()
  })

  it("handles URL with additional parameters", () => {
    expect(extractYouTubeId("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=30s"))
      .toBe("dQw4w9WgXcQ")
  })

  it("handles URL without www", () => {
    expect(extractYouTubeId("https://youtube.com/watch?v=dQw4w9WgXcQ"))
      .toBe("dQw4w9WgXcQ")
  })
})

describe("rewriteNoteHref", () => {
  it("rewrites root note paths to LewisMD note routes", () => {
    expect(rewriteNoteHref("/Personal/Studies/Español/2026/Study_Syllabus_A2"))
      .toBe("/notes/Personal/Studies/Espa%C3%B1ol/2026/Study_Syllabus_A2.md")
  })

  it("rewrites relative note paths against the current note directory", () => {
    expect(rewriteNoteHref("Study_Syllabus_A2", "Personal/Studies/Español/2026/Lesson_01.md"))
      .toBe("/notes/Personal/Studies/Espa%C3%B1ol/2026/Study_Syllabus_A2.md")
  })

  it("resolves parent directory note paths", () => {
    expect(rewriteNoteHref("../Glossary", "Personal/Studies/Español/2026/Lesson_01.md"))
      .toBe("/notes/Personal/Studies/Espa%C3%B1ol/Glossary.md")
  })

  it("preserves query strings and anchors when rewriting note paths", () => {
    expect(rewriteNoteHref("./Study_Syllabus_A2?view=compact#goals", "Personal/Studies/Español/2026/Lesson_01.md"))
      .toBe("/notes/Personal/Studies/Espa%C3%B1ol/2026/Study_Syllabus_A2.md?view=compact#goals")
  })

  it("keeps existing app routes unchanged", () => {
    expect(rewriteNoteHref("/notes/Personal/Studies/Espa%C3%B1ol/2026/Study_Syllabus_A2.md"))
      .toBe("/notes/Personal/Studies/Espa%C3%B1ol/2026/Study_Syllabus_A2.md")
  })

  it("does not rewrite external, anchor, or non-note file links", () => {
    expect(rewriteNoteHref("https://example.com")).toBeNull()
    expect(rewriteNoteHref("#section-2")).toBeNull()
    expect(rewriteNoteHref("appendix.pdf", "Personal/Studies/Español/2026/Lesson_01.md")).toBeNull()
    expect(rewriteNoteHref("/images/example.png")).toBe("/images/example.png")
  })
})
