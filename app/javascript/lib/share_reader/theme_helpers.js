export const BUILTIN_THEMES = [
  { id: "light", name: "Light", icon: "sun" },
  { id: "dark", name: "Dark", icon: "moon" },
  { id: "catppuccin", name: "Catppuccin", icon: "palette" },
  { id: "catppuccin-latte", name: "Catppuccin Latte", icon: "palette" },
  { id: "ethereal", name: "Ethereal", icon: "palette" },
  { id: "everforest", name: "Everforest", icon: "palette" },
  { id: "flexoki-light", name: "Flexoki Light", icon: "palette" },
  { id: "gruvbox", name: "Gruvbox", icon: "palette" },
  { id: "hackerman", name: "Hackerman", icon: "palette" },
  { id: "kanagawa", name: "Kanagawa", icon: "palette" },
  { id: "matte-black", name: "Matte Black", icon: "palette" },
  { id: "nord", name: "Nord", icon: "palette" },
  { id: "osaka-jade", name: "Osaka Jade", icon: "palette" },
  { id: "ristretto", name: "Ristretto", icon: "palette" },
  { id: "rose-pine", name: "Rose Pine", icon: "palette" },
  { id: "solarized-dark", name: "Solarized Dark", icon: "palette" },
  { id: "solarized-light", name: "Solarized Light", icon: "palette" },
  { id: "tokyo-night", name: "Tokyo Night", icon: "palette" }
]

export const LIGHT_THEME_IDS = ["light", "solarized-light", "catppuccin-latte", "rose-pine", "flexoki-light"]

const ICONS = {
  sun: `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" />
  </svg>`,
  moon: `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z" />
  </svg>`,
  palette: `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zm0 0h12a2 2 0 002-2v-4a2 2 0 00-2-2h-2.343M11 7.343l1.657-1.657a2 2 0 012.828 0l2.829 2.829a2 2 0 010 2.828l-8.486 8.485M7 17h.01" />
  </svg>`,
  sync: `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
  </svg>`
}

export function themeNameFor(themeId, themes = BUILTIN_THEMES) {
  return themes.find((theme) => theme.id === themeId)?.name || "Light"
}

export function themeIconMarkup(iconType) {
  return ICONS[iconType] || ICONS.palette
}

export function resolvedThemeId(currentThemeId, prefersDark = false) {
  if (currentThemeId) return currentThemeId
  return prefersDark ? "dark" : "light"
}

export function isDarkTheme(themeId, lightThemeIds = LIGHT_THEME_IDS) {
  return !lightThemeIds.includes(themeId)
}

export function applyThemeToRoot(themeId, rootElement = document.documentElement, lightThemeIds = LIGHT_THEME_IDS) {
  rootElement.setAttribute("data-theme", themeId)
  const darkTheme = isDarkTheme(themeId, lightThemeIds)
  rootElement.classList.toggle("dark", darkTheme)

  return {
    themeId,
    colorScheme: darkTheme ? "dark" : "light"
  }
}

export function buildThemeUrl(themeId, currentUrl = window.location.href) {
  const url = new URL(currentUrl)
  url.searchParams.set("theme", themeId)
  return url.toString()
}

export function renderThemeMenuHtml({
  themes = BUILTIN_THEMES,
  currentThemeId,
  action = "click->theme#selectTheme"
} = {}) {
  return themes.map((theme) => `
    <button
      type="button"
      class="w-full px-3 py-2 text-left text-sm hover:bg-[var(--theme-bg-hover)] flex items-center justify-between gap-2"
      data-theme="${theme.id}"
      data-action="${action}"
    >
      <span class="flex items-center gap-2">
        ${themeIconMarkup(theme.icon)}
        ${theme.name}
      </span>
      <svg class="w-4 h-4 checkmark ${theme.id !== currentThemeId ? "opacity-0" : ""}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
      </svg>
    </button>
  `).join("")
}
