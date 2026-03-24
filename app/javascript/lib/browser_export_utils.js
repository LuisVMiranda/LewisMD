function triggerFileDownload(filename, url) {
  const link = document.createElement("a")

  link.href = url
  link.download = filename
  link.rel = "noopener"
  link.style.display = "none"

  document.body.appendChild(link)
  link.click()

  setTimeout(() => {
    link.remove()
    URL.revokeObjectURL(url)
  }, 0)

  return true
}

export function downloadBlobFile(filename, blob) {
  return triggerFileDownload(filename, URL.createObjectURL(blob))
}

export function downloadExportFile(filename, content, contentType) {
  const blob = new Blob([content], { type: contentType })
  return downloadBlobFile(filename, blob)
}

export async function waitForDocumentImages(frameDocument, timeoutMs = 5000) {
  const images = Array.from(frameDocument?.images || [])
  if (images.length === 0) return

  await Promise.race([
    Promise.all(images.map((image) => {
      if (image.complete) return Promise.resolve()

      return new Promise((resolve) => {
        const settle = () => {
          image.removeEventListener("load", settle)
          image.removeEventListener("error", settle)
          resolve()
        }

        image.addEventListener("load", settle, { once: true })
        image.addEventListener("error", settle, { once: true })
      })
    })),
    new Promise((resolve) => setTimeout(resolve, timeoutMs))
  ])
}

export async function waitForExportDocumentAssets(frameWindow, timeoutMs = 5000) {
  const frameDocument = frameWindow?.document
  if (!frameDocument) return

  try {
    if (frameDocument.fonts?.ready) {
      await frameDocument.fonts.ready
    }
  } catch {
    // Fonts should not block export if the browser cannot resolve them.
  }

  await waitForDocumentImages(frameDocument, timeoutMs)

  if (typeof frameWindow.requestAnimationFrame === "function") {
    await new Promise((resolve) => frameWindow.requestAnimationFrame(() => resolve()))
  }
}

export function printStandaloneDocument(documentHtml, {
  timeoutMs = 5000,
  onError = () => {}
} = {}) {
  if (!documentHtml) return false

  const iframe = document.createElement("iframe")
  const documentBlob = new Blob([documentHtml], { type: "text/html;charset=utf-8" })
  const documentUrl = URL.createObjectURL(documentBlob)
  let cleanupTimeout = null
  let afterPrintHandler = null

  const cleanup = () => {
    if (cleanupTimeout) clearTimeout(cleanupTimeout)
    cleanupTimeout = null

    if (afterPrintHandler && iframe.contentWindow) {
      iframe.contentWindow.removeEventListener("afterprint", afterPrintHandler)
    }

    URL.revokeObjectURL(documentUrl)
    iframe.remove()
  }

  iframe.setAttribute("aria-hidden", "true")
  iframe.style.position = "fixed"
  iframe.style.right = "0"
  iframe.style.bottom = "0"
  iframe.style.width = "0"
  iframe.style.height = "0"
  iframe.style.opacity = "0"
  iframe.style.pointerEvents = "none"
  iframe.style.border = "0"

  iframe.onload = async () => {
    const frameWindow = iframe.contentWindow
    if (!frameWindow) {
      cleanup()
      onError()
      return
    }

    afterPrintHandler = () => cleanup()
    frameWindow.addEventListener("afterprint", afterPrintHandler, { once: true })

    cleanupTimeout = setTimeout(() => cleanup(), timeoutMs)

    try {
      await waitForExportDocumentAssets(frameWindow, timeoutMs)
      frameWindow.focus()
      frameWindow.print()
    } catch (error) {
      console.error("Failed to open print dialog", error)
      cleanup()
      onError()
    }
  }

  // Assign the final document URL before attaching the iframe so the first load
  // event always corresponds to the populated export document instead of about:blank.
  iframe.src = documentUrl
  document.body.appendChild(iframe)
  return true
}
