/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, beforeEach } from "vitest"
import {
  buildExportFilename,
  buildPlainTextExport,
  buildStandaloneExportDocument,
  captureExportThemeSnapshot
} from "../../../app/javascript/lib/export_document_builder"

describe("export_document_builder", () => {
  beforeEach(() => {
    document.documentElement.className = ""
    document.documentElement.removeAttribute("style")
  })

  it("captures the current theme variables from the document root", () => {
    document.documentElement.classList.add("dark")
    document.documentElement.style.setProperty("--theme-bg-primary", "#111111")
    document.documentElement.style.setProperty("--theme-text-primary", "#f5f5f5")
    document.documentElement.style.setProperty("--font-mono", "JetBrains Mono")

    expect(captureExportThemeSnapshot()).toEqual({
      colorScheme: "dark",
      variables: {
        "--theme-bg-primary": "#111111",
        "--theme-text-primary": "#f5f5f5",
        "--font-mono": "JetBrains Mono"
      }
    })
  })

  it("builds a standalone themed HTML document from a preview payload", () => {
    const html = buildStandaloneExportDocument({
      title: "Weekly & Notes",
      themeId: "nord",
      html: "<h1>Weekly Notes</h1><p>Body</p>",
      typography: {
        fontFamily: "IBM Plex Serif",
        fontSize: "19px"
      }
    }, {
      language: "en-US",
      theme: {
        colorScheme: "dark",
        variables: {
          "--theme-bg-primary": "#0f172a",
          "--theme-accent": "#38bdf8"
        }
      }
    })

    expect(html).toContain("<!DOCTYPE html>")
    expect(html).toContain('<html lang="en-US" data-theme="nord">')
    expect(html).toContain("<title>Weekly &amp; Notes</title>")
    expect(html).toContain("--theme-bg-primary: #0f172a;")
    expect(html).toContain("--theme-accent: #38bdf8;")
    expect(html).toContain("--export-font-family: IBM Plex Serif;")
    expect(html).toContain("--export-font-size: 19px;")
    expect(html).toContain("print-color-adjust: exact;")
    expect(html).toContain("background: #ffffff !important;")
    expect(html).toContain("color: #111827 !important;")
    expect(html).toContain(".export-article th")
    expect(html).toContain(".export-article img")
    expect(html).toContain('.export-article a[href]::after')
    expect(html).toContain("<h1>Weekly Notes</h1><p>Body</p>")
  })

  it("formats plain text exports with normalized trailing newlines", () => {
    expect(buildPlainTextExport({
      plainText: "Line 1\r\nLine 2"
    })).toBe("Line 1\nLine 2\n")
  })

  it("builds safe filenames from the note path", () => {
    expect(buildExportFilename({
      path: "notes/Weekly Notes?.md"
    }, "html")).toBe("Weekly-Notes.html")
  })
})
