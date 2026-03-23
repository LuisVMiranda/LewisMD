function normalizeBaseUrl(baseUrl) {
  try {
    return new URL(baseUrl || window.location.href)
  } catch {
    return new URL(window.location.href)
  }
}

function isAlreadyEmbedded(src) {
  return /^(data|blob):/i.test(String(src || "").trim())
}

function toResolvableImageUrl(src, baseUrl) {
  const rawSrc = String(src ?? "").trim()
  if (!rawSrc || isAlreadyEmbedded(rawSrc)) return null

  try {
    return new URL(rawSrc, baseUrl)
  } catch {
    return null
  }
}

function isSameOriginImageUrl(url, baseUrl) {
  return Boolean(url) &&
    (url.protocol === "http:" || url.protocol === "https:") &&
    url.origin === baseUrl.origin
}

async function blobToDataUrl(blob) {
  const contentType = blob.type || "application/octet-stream"
  const bytes = new Uint8Array(await blob.arrayBuffer())
  let binary = ""

  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    const chunk = bytes.subarray(offset, offset + 0x8000)
    binary += String.fromCharCode(...chunk)
  }

  return `data:${contentType};base64,${btoa(binary)}`
}

async function inlineImageElement(image, { baseUrl, fetchImpl }) {
  const source = image.getAttribute("src")
  const resolvedUrl = toResolvableImageUrl(source, baseUrl)
  if (!isSameOriginImageUrl(resolvedUrl, baseUrl)) return

  try {
    const response = await fetchImpl(resolvedUrl.toString(), {
      credentials: "same-origin"
    })
    if (!response.ok) return

    const blob = await response.blob()
    image.setAttribute("src", await blobToDataUrl(blob))
    image.removeAttribute("srcset")
  } catch (error) {
    console.warn("Failed to inline export image:", resolvedUrl.toString(), error)
  }
}

export async function inlineSameOriginImages(html, {
  baseUrl = window.location.href,
  fetchImpl = window.fetch.bind(window)
} = {}) {
  const markup = String(html ?? "")
  if (!markup.includes("<img")) return markup

  const normalizedBaseUrl = normalizeBaseUrl(baseUrl)
  const container = document.createElement("div")
  container.innerHTML = markup

  const images = Array.from(container.querySelectorAll("img[src]"))
  await Promise.all(images.map((image) => inlineImageElement(image, {
    baseUrl: normalizedBaseUrl,
    fetchImpl
  })))

  return container.innerHTML
}
