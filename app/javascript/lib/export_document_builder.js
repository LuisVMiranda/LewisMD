import { escapeHtmlString } from "lib/text_utils"

export const EXPORT_THEME_VARIABLES = [
  "--theme-bg-primary",
  "--theme-bg-secondary",
  "--theme-bg-tertiary",
  "--theme-border",
  "--theme-text-primary",
  "--theme-text-secondary",
  "--theme-text-muted",
  "--theme-accent",
  "--theme-accent-hover",
  "--theme-code-bg",
  "--theme-heading-1",
  "--theme-heading-2",
  "--theme-heading-3",
  "--font-mono",
  "--font-sans"
]

function normalizeCssValue(value) {
  return String(value ?? "").trim()
}

function normalizeExtension(extension) {
  return String(extension ?? "").replace(/^\./, "").trim().toLowerCase()
}

function buildThemeVariableBlock(theme = {}) {
  const lines = Object.entries(theme.variables || {})
    .map(([name, value]) => [name, normalizeCssValue(value)])
    .filter(([, value]) => Boolean(value))
    .map(([name, value]) => `  ${name}: ${value};`)

  return lines.join("\n")
}

function ensureTrailingNewline(value) {
  if (!value) return ""
  return value.endsWith("\n") ? value : `${value}\n`
}

export function captureExportThemeSnapshot(rootElement = document.documentElement) {
  const computedStyle = window.getComputedStyle(rootElement)
  const variables = EXPORT_THEME_VARIABLES.reduce((snapshot, variableName) => {
    const value = normalizeCssValue(computedStyle.getPropertyValue(variableName))
    if (value) snapshot[variableName] = value
    return snapshot
  }, {})

  return {
    colorScheme: rootElement.classList.contains("dark") ? "dark" : "light",
    variables
  }
}

export function buildStandaloneExportDocument(payload, {
  theme = {},
  language = "en",
  documentTitle = payload?.title || "Untitled"
} = {}) {
  const title = escapeHtmlString(documentTitle)
  const lang = escapeHtmlString(language || "en")
  const themeId = escapeHtmlString(payload?.themeId || "")
  const fontFamily = normalizeCssValue(payload?.typography?.fontFamily) || "var(--font-sans, system-ui, sans-serif)"
  const fontSize = normalizeCssValue(payload?.typography?.fontSize) || "16px"
  const colorScheme = theme.colorScheme === "dark" ? "dark" : "light"
  const themeVariables = buildThemeVariableBlock(theme)

  return `<!DOCTYPE html>
<html lang="${lang}" data-theme="${themeId}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="${colorScheme}">
  <title>${title}</title>
  <style>
    :root {
${themeVariables}
      --export-font-family: ${fontFamily};
      --export-font-size: ${fontSize};
    }

    html {
      min-height: 100%;
      color-scheme: ${colorScheme};
      background: var(--theme-bg-primary, #ffffff);
    }

    *,
    *::before,
    *::after {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      min-height: 100vh;
      background: var(--theme-bg-primary, #ffffff);
      color: var(--theme-text-secondary, #1f2937);
      font-family: var(--export-font-family);
      overflow-wrap: anywhere;
      -webkit-print-color-adjust: exact;
      print-color-adjust: exact;
    }

    .export-shell {
      min-height: 100vh;
      padding:
        clamp(1.25rem, 2vw + 0.9rem, 3rem)
        clamp(0.95rem, 1.6vw + 0.65rem, 1.5rem);
      background:
        linear-gradient(180deg, var(--theme-bg-secondary, #f8fafc) 0%, var(--theme-bg-primary, #ffffff) 18rem);
    }

    .export-article {
      width: min(100%, 72ch);
      max-width: min(100%, 72ch);
      margin: 0 auto;
      font-size: var(--export-font-size);
      line-height: 1.75;
      color: var(--theme-text-secondary, #1f2937);
      font-family: var(--export-font-family);
      overflow-wrap: break-word;
    }

    .export-article > :first-child {
      margin-top: 0;
    }

    .export-article > :last-child {
      margin-bottom: 0;
    }

    .export-article h1,
    .export-article h2,
    .export-article h3,
    .export-article h4,
    .export-article h5,
    .export-article h6 {
      color: var(--theme-text-primary, #111827);
      font-weight: 600;
      line-height: 1.3;
      margin-top: 2em;
      margin-bottom: 0.75em;
    }

    .export-article h1 {
      font-size: 2em;
      margin-top: 0;
      padding-bottom: 0.3em;
      border-bottom: 1px solid var(--theme-border, #d1d5db);
      color: var(--theme-heading-1, var(--theme-text-primary, #111827));
    }

    .export-article h2 {
      font-size: 1.5em;
      padding-bottom: 0.25em;
      border-bottom: 1px solid var(--theme-border, #d1d5db);
      color: var(--theme-heading-2, var(--theme-text-primary, #111827));
    }

    .export-article h3 {
      font-size: 1.25em;
      color: var(--theme-heading-3, var(--theme-text-primary, #111827));
    }

    .export-article h4 {
      font-size: 1.1em;
    }

    .export-article h5,
    .export-article h6 {
      font-size: 1em;
    }

    .export-article h6 {
      color: var(--theme-text-muted, #6b7280);
    }

    .export-article p {
      margin-top: 1.25em;
      margin-bottom: 1.25em;
    }

    .export-article a {
      color: var(--theme-accent, #2563eb);
      text-decoration: underline;
      text-underline-offset: 2px;
    }

    .export-article a:hover {
      color: var(--theme-accent-hover, var(--theme-accent, #1d4ed8));
    }

    .export-article ul,
    .export-article ol {
      margin-top: 1.25em;
      margin-bottom: 1.25em;
      padding-left: 1.5em;
    }

    .export-article li {
      margin-top: 0.5em;
      margin-bottom: 0.5em;
    }

    .export-article ul {
      list-style-type: disc;
    }

    .export-article ol {
      list-style-type: decimal;
    }

    .export-article code {
      background: var(--theme-code-bg, #f3f4f6);
      color: var(--theme-text-primary, #111827);
      font-family: var(--font-mono, ui-monospace, monospace);
      padding: 0.2em 0.4em;
      border-radius: 0.25rem;
      font-size: 0.875em;
      font-weight: 500;
    }

    .export-article pre {
      background: var(--theme-code-bg, #f3f4f6);
      color: var(--theme-text-primary, #111827);
      font-family: var(--font-mono, ui-monospace, monospace);
      border-radius: 0.5rem;
      overflow-x: auto;
      padding: 1em;
      margin-top: 1.5em;
      margin-bottom: 1.5em;
      font-size: 0.875em;
      line-height: 1.7;
    }

    .export-article pre code {
      background: transparent;
      padding: 0;
      color: inherit;
      font-family: inherit;
      font-weight: normal;
    }

    .export-article .code-copy-btn {
      display: none !important;
    }

    .export-article blockquote {
      border-left: 4px solid var(--theme-accent, #2563eb);
      padding-left: 1em;
      margin-top: 1.5em;
      margin-bottom: 1.5em;
      color: var(--theme-text-muted, #6b7280);
      font-style: italic;
    }

    .export-article hr {
      border: none;
      border-top: 1px solid var(--theme-border, #d1d5db);
      margin-top: 2em;
      margin-bottom: 2em;
    }

    .export-article img {
      border-radius: 0.5rem;
      margin-top: 1.5em;
      margin-bottom: 1.5em;
      max-width: 100%;
      height: auto;
    }

    .export-article table {
      width: 100%;
      margin-top: 1.5em;
      margin-bottom: 1.5em;
      border-collapse: collapse;
      font-size: 0.875em;
    }

    .export-article th,
    .export-article td {
      border: 1px solid var(--theme-border, #d1d5db);
      padding: 0.625em 1em;
      text-align: left;
    }

    .export-article th {
      background: var(--theme-bg-tertiary, #f3f4f6);
      font-weight: 600;
    }

    .export-article strong {
      font-weight: 600;
      color: var(--theme-text-primary, #111827);
    }

    .export-article .embed-container,
    .export-article .video-player {
      background: var(--theme-bg-tertiary, #f3f4f6);
    }

    .export-article .embed-container {
      position: relative;
      width: 100%;
      padding-bottom: 56.25%;
      height: 0;
      overflow: hidden;
      margin-top: 1.5em;
      margin-bottom: 1.5em;
      border-radius: 0.5rem;
    }

    .export-article .embed-container iframe {
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      border: 0;
      border-radius: 0.5rem;
    }

    .export-article .video-player {
      width: 100%;
      max-width: 100%;
      height: auto;
      margin-top: 1.5em;
      margin-bottom: 1.5em;
      border-radius: 0.5rem;
    }

    @media (max-width: 1023px) {
      .export-shell {
        padding:
          clamp(1.1rem, 1.5vw + 0.9rem, 1.8rem)
          clamp(0.9rem, 1.3vw + 0.7rem, 1.2rem);
      }
    }

    @media (max-width: 768px) {
      .export-shell {
        padding: 1.15rem 0.9rem 1.8rem;
      }

      .export-article {
        line-height: 1.65;
      }

      .export-article table {
        display: block;
        overflow-x: auto;
        -webkit-overflow-scrolling: touch;
        font-size: 0.8125em;
      }
    }

    @page {
      margin: 16mm 18mm;
    }

    @media print {
      html {
        color-scheme: light !important;
      }

      html,
      body {
        background: #ffffff !important;
      }

      body {
        color: #374151 !important;
      }

      .export-shell {
        min-height: auto;
        padding: 0;
        background: #ffffff !important;
      }

      .export-article {
        max-width: none;
        color: #374151 !important;
      }

      .export-article h1,
      .export-article h2,
      .export-article h3,
      .export-article h4,
      .export-article h5,
      .export-article h6 {
        color: #111827 !important;
        border-color: #d1d5db !important;
      }

      .export-article strong,
      .export-article b {
        color: #111827 !important;
      }

      .export-article a {
        color: #1f2937 !important;
      }

      .export-article a[href]::after {
        content: " (" attr(href) ")";
        font-size: 0.8em;
        color: #6b7280 !important;
      }

      .export-article code,
      .export-article pre {
        color: #111827 !important;
      }

      .export-article code {
        background: #f3f4f6 !important;
      }

      .export-article pre {
        background: #f8fafc !important;
        border: 1px solid #d1d5db;
        white-space: pre-wrap;
      }

      .export-article blockquote {
        border-left-color: #9ca3af !important;
        color: #4b5563 !important;
      }

      .export-article th,
      .export-article td {
        border-color: #d1d5db !important;
        color: #1f2937 !important;
      }

      .export-article th {
        background: #f3f4f6 !important;
        color: #111827 !important;
      }

      .export-article img,
      .export-article pre,
      .export-article blockquote,
      .export-article table,
      .export-article .embed-container,
      .export-article .video-player {
        break-inside: avoid;
        page-break-inside: avoid;
      }

      .export-article h1,
      .export-article h2,
      .export-article h3 {
        page-break-after: avoid;
      }
    }
  </style>
</head>
<body>
  <main class="export-shell">
    <article class="export-article">
      ${payload?.html || ""}
    </article>
  </main>
</body>
</html>`
}

export function buildPlainTextExport(payload) {
  const normalized = String(payload?.plainText ?? "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")

  return ensureTrailingNewline(normalized)
}

export function buildExportFilename(payload, extension) {
  const normalizedExtension = normalizeExtension(extension) || "txt"
  const sourceName = String(payload?.path || payload?.title || "untitled")
    .split("/")
    .pop()
    .replace(/\.[^.]+$/, "")
  const safeName = sourceName
    .replace(/[<>:"/\\|?*\u0000-\u001F]/g, "-")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^\.+/, "")
    .replace(/[. -]+$/, "")
    .trim() || "untitled"

  return `${safeName}.${normalizedExtension}`
}
