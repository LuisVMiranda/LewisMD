/**
 * @vitest-environment jsdom
 */
import { describe, expect, it } from "vitest"
import {
  collectOutlineEntries,
  findActiveOutlineIndex
} from "../../../../app/javascript/lib/share_reader/outline_helpers.js"

describe("outline_helpers", () => {
  it("collects outline entries from snapshot headings and assigns stable ids", () => {
    const frameDocument = document.implementation.createHTMLDocument("Shared")
    frameDocument.body.innerHTML = `
      <article class="export-article">
        <h1>Overview</h1>
        <p>Summary</p>
        <h2>Overview</h2>
        <h4><span>Deep Dive</span></h4>
      </article>
    `

    const entries = collectOutlineEntries(frameDocument)

    expect(entries.map(({ text, level, id }) => ({ text, level, id }))).toEqual([
      { text: "Overview", level: 1, id: "overview" },
      { text: "Overview", level: 2, id: "overview-2" },
      { text: "Deep Dive", level: 4, id: "deep-dive" }
    ])
  })

  it("returns the deepest heading above the active viewport threshold", () => {
    const frameDocument = document.implementation.createHTMLDocument("Shared")
    frameDocument.body.innerHTML = `
      <article class="export-article">
        <h1>Overview</h1>
        <h2>Details</h2>
        <h3>Appendix</h3>
      </article>
    `

    const headings = Array.from(frameDocument.querySelectorAll("h1, h2, h3"))
    const topOffsets = [ -18, 72, 412 ]
    headings.forEach((heading, index) => {
      Object.defineProperty(heading, "getBoundingClientRect", {
        configurable: true,
        value: () => ({ top: topOffsets[index] })
      })
    })

    const entries = collectOutlineEntries(frameDocument)
    const frameWindow = {
      innerHeight: 900,
      document: {
        scrollingElement: {
          scrollTop: 240,
          scrollHeight: 1800
        }
      }
    }

    expect(findActiveOutlineIndex(entries, frameWindow)).toBe(1)
  })

  it("treats the last heading as active when the iframe is scrolled to the bottom", () => {
    const frameDocument = document.implementation.createHTMLDocument("Shared")
    frameDocument.body.innerHTML = `
      <article class="export-article">
        <h1>Overview</h1>
        <h2>Details</h2>
        <h3>Appendix</h3>
      </article>
    `

    const headings = Array.from(frameDocument.querySelectorAll("h1, h2, h3"))
    headings.forEach((heading) => {
      Object.defineProperty(heading, "getBoundingClientRect", {
        configurable: true,
        value: () => ({ top: 240 })
      })
    })

    const entries = collectOutlineEntries(frameDocument)
    const frameWindow = {
      innerHeight: 900,
      document: {
        scrollingElement: {
          scrollTop: 1100,
          scrollHeight: 2000
        }
      }
    }

    expect(findActiveOutlineIndex(entries, frameWindow)).toBe(2)
  })
})
