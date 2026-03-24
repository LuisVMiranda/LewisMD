/**
 * @vitest-environment jsdom
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { downloadBlobFile, downloadExportFile } from "../../../app/javascript/lib/browser_export_utils.js"

describe("browser_export_utils", () => {
  let originalCreateObjectURL
  let originalRevokeObjectURL
  let clickSpy

  beforeEach(() => {
    originalCreateObjectURL = URL.createObjectURL
    originalRevokeObjectURL = URL.revokeObjectURL
    URL.createObjectURL = vi.fn(() => "blob:test-download")
    URL.revokeObjectURL = vi.fn()
    clickSpy = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => {})
  })

  afterEach(() => {
    URL.createObjectURL = originalCreateObjectURL
    URL.revokeObjectURL = originalRevokeObjectURL
    clickSpy.mockRestore()
    document.body.innerHTML = ""
  })

  it("downloads blobs through a temporary anchor and revokes the object URL", async () => {
    const blob = new Blob(["backup"], { type: "application/zip" })

    expect(downloadBlobFile("alpha-backup.zip", blob)).toBe(true)
    expect(clickSpy).toHaveBeenCalledTimes(1)

    const link = clickSpy.mock.instances.at(-1)
    expect(link.href).toBe("blob:test-download")
    expect(link.download).toBe("alpha-backup.zip")

    await new Promise((resolve) => setTimeout(resolve, 0))

    expect(URL.createObjectURL).toHaveBeenCalledWith(blob)
    expect(URL.revokeObjectURL).toHaveBeenCalledWith("blob:test-download")
  })

  it("wraps string content in a blob for export downloads", async () => {
    expect(downloadExportFile("alpha.txt", "Hello", "text/plain;charset=utf-8")).toBe(true)
    expect(clickSpy).toHaveBeenCalledTimes(1)

    const [blob] = URL.createObjectURL.mock.calls.at(-1)
    expect(blob).toBeInstanceOf(Blob)
    expect(blob.type).toBe("text/plain;charset=utf-8")
    expect(blob.size).toBe(5)
  })
})
