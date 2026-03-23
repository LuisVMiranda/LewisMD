/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, vi } from "vitest"
import { inlineSameOriginImages } from "../../../app/javascript/lib/export_image_embedder.js"

describe("inlineSameOriginImages", () => {
  it("inlines same-origin preview images as data URLs", async () => {
    const html = '<p><img src="/images/preview/photo.png" alt="Photo"></p>'
    const blob = {
      type: "image/png",
      arrayBuffer: () => Promise.resolve(new TextEncoder().encode("png-binary").buffer)
    }
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      blob: () => Promise.resolve(blob)
    })

    const result = await inlineSameOriginImages(html, {
      baseUrl: "http://localhost:7591/notes/test.md",
      fetchImpl
    })

    expect(fetchImpl).toHaveBeenCalledWith("http://localhost:7591/images/preview/photo.png", {
      credentials: "same-origin"
    })
    expect(result).toContain('src="data:image/png;base64,')
    expect(result).not.toContain('/images/preview/photo.png')
  })

  it("leaves remote images untouched", async () => {
    const html = '<p><img src="https://example.com/remote.png" alt="Remote"></p>'
    const fetchImpl = vi.fn()

    const result = await inlineSameOriginImages(html, {
      baseUrl: "http://localhost:7591/notes/test.md",
      fetchImpl
    })

    expect(fetchImpl).not.toHaveBeenCalled()
    expect(result).toContain('src="https://example.com/remote.png"')
  })

  it("returns the original HTML when a same-origin fetch fails", async () => {
    const html = '<p><img src="/images/preview/missing.png" alt="Missing"></p>'
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: false
    })

    const result = await inlineSameOriginImages(html, {
      baseUrl: "http://localhost:7591/notes/test.md",
      fetchImpl
    })

    expect(result).toContain('src="/images/preview/missing.png"')
  })
})
