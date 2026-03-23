/**
 * @vitest-environment jsdom
 */
import { describe, it, expect } from "vitest"
import { buildRenderedDocumentPayload } from "../../../app/javascript/lib/rendered_document_payload"

describe("buildRenderedDocumentPayload", () => {
  it("builds a normalized payload from preview-derived inputs", () => {
    expect(buildRenderedDocumentPayload({
      title: "  Weekly Notes  ",
      path: "notes/week.md",
      html: "<h1>Weekly Notes</h1>",
      plainText: "Line 1\r\nLine 2",
      themeId: "  nord  ",
      typography: {
        zoom: 124.6,
        fontFamily: "  Georgia, serif  ",
        fontSize: " 18px "
      }
    })).toEqual({
      source: "preview",
      title: "Weekly Notes",
      path: "notes/week.md",
      html: "<h1>Weekly Notes</h1>",
      plainText: "Line 1\nLine 2",
      themeId: "nord",
      typography: {
        zoom: 125,
        fontFamily: "Georgia, serif",
        fontSize: "18px"
      }
    })
  })

  it("derives a title from the note path when one is not provided", () => {
    expect(buildRenderedDocumentPayload({
      path: "projects/roadmap.md",
      html: "",
      plainText: ""
    }).title).toBe("roadmap")
  })

  it("falls back to Untitled when there is no title or path", () => {
    expect(buildRenderedDocumentPayload().title).toBe("Untitled")
  })
})
