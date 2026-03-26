export const AVAILABLE_LOCALES = [
  { id: "en", name: "English", flag: "us" },
  { id: "pt-BR", name: "Portugu\u00eas (Brasil)", flag: "br" },
  { id: "pt-PT", name: "Portugu\u00eas (Portugal)", flag: "pt" },
  { id: "es", name: "Espa\u00f1ol", flag: "es" },
  { id: "he", name: "\u05e2\u05d1\u05e8\u05d9\u05ea", flag: "il" },
  { id: "ja", name: "\u65e5\u672c\u8a9e", flag: "jp" },
  { id: "ko", name: "\ud55c\uad6d\uc5b4", flag: "kr" }
]

const FLAGS = {
  us: `<span class="text-base">\ud83c\uddfa\ud83c\uddf8</span>`,
  br: `<span class="text-base">\ud83c\udde7\ud83c\uddf7</span>`,
  pt: `<span class="text-base">\ud83c\uddf5\ud83c\uddf9</span>`,
  es: `<span class="text-base">\ud83c\uddea\ud83c\uddf8</span>`,
  il: `<span class="text-base">\ud83c\uddee\ud83c\uddf1</span>`,
  jp: `<span class="text-base">\ud83c\uddef\ud83c\uddf5</span>`,
  kr: `<span class="text-base">\ud83c\uddf0\ud83c\uddf7</span>`
}

export function localeNameFor(localeId, locales = AVAILABLE_LOCALES) {
  return locales.find((locale) => locale.id === localeId)?.name || "English"
}

export function localeFlagMarkup(flagCode) {
  return FLAGS[flagCode] || ""
}

export function buildLocaleUrl(localeId, currentUrl = window.location.href) {
  const url = new URL(currentUrl)
  url.searchParams.set("locale", localeId)
  return url.toString()
}

export function renderLocaleMenuHtml({
  locales = AVAILABLE_LOCALES,
  currentLocaleId,
  action = "click->locale#selectLocale"
} = {}) {
  return locales.map((locale) => `
    <button
      type="button"
      class="w-full px-3 py-2 text-left text-sm hover:bg-[var(--theme-bg-hover)] flex items-center justify-between gap-2"
      data-locale="${locale.id}"
      data-action="${action}"
    >
      <span class="flex items-center gap-2">
        ${localeFlagMarkup(locale.flag)}
        ${locale.name}
      </span>
      <svg class="w-4 h-4 checkmark ${locale.id !== currentLocaleId ? "opacity-0" : ""}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
      </svg>
    </button>
  `).join("")
}
