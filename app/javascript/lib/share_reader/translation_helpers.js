export function lookupTranslation(translations, key) {
  const keys = key.split(".")
  let value = translations

  for (const segment of keys) {
    if (value && typeof value === "object" && segment in value) {
      value = value[segment]
    } else {
      return null
    }
  }

  return typeof value === "string" ? value : null
}

export function interpolateTranslation(value, options = {}) {
  return value.replace(/%\{(\w+)\}/g, (match, placeholder) => {
    return options[placeholder] !== undefined ? options[placeholder] : match
  })
}

export function translateKey(key, options = {}, translations = window.frankmdTranslations || {}) {
  const value = lookupTranslation(translations, key)
  return value ? interpolateTranslation(value, options) : key
}

export function installGlobalTranslationHelper(globalObject = window) {
  globalObject.t = function(key, options = {}) {
    return translateKey(key, options, globalObject.frankmdTranslations || {})
  }

  return globalObject.t
}

export function setGlobalTranslations({
  locale,
  translations,
  globalObject = window
}) {
  globalObject.frankmdTranslations = translations || {}
  globalObject.frankmdLocale = locale
}

export function dispatchTranslationsLoaded({
  locale,
  translations,
  globalObject = window
}) {
  globalObject.dispatchEvent(new CustomEvent("frankmd:translations-loaded", {
    detail: { locale, translations }
  }))
}
