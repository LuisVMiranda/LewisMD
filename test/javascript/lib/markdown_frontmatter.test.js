/**
 * @vitest-environment jsdom
 */
import { describe, it, expect } from "vitest"
import { stripMarkdownFrontmatter } from "../../../app/javascript/lib/markdown_frontmatter.js"

describe("stripMarkdownFrontmatter", () => {
  it("strips YAML frontmatter and preserves the line offset", () => {
    const markdown = `---
title: Test
tags:
  - demo
---

# Heading
`

    expect(stripMarkdownFrontmatter(markdown)).toEqual({
      content: "# Heading\n",
      frontmatterLines: 6
    })
  })

  it("strips TOML frontmatter and preserves the line offset", () => {
    const markdown = `+++
title = "Test"
draft = true
+++

# Heading
`

    expect(stripMarkdownFrontmatter(markdown)).toEqual({
      content: "# Heading\n",
      frontmatterLines: 5
    })
  })

  it("returns the original content when the closing delimiter is missing", () => {
    const markdown = `---
title: Test

# Heading
`

    expect(stripMarkdownFrontmatter(markdown)).toEqual({
      content: markdown,
      frontmatterLines: 0
    })
  })

  it("returns empty content when frontmatter consumes the whole file", () => {
    const markdown = `---
title: Test
---`

    expect(stripMarkdownFrontmatter(markdown)).toEqual({
      content: "",
      frontmatterLines: 3
    })
  })
})
