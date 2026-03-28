import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static STORAGE_PREFIX = "frankmd:backup:"

  save(path, content) {
    const key = this.constructor.STORAGE_PREFIX + path
    try {
      localStorage.setItem(key, JSON.stringify({ content, timestamp: Date.now() }))
    } catch (e) {
      console.warn("localStorage backup failed:", e)
    }
  }

  check(path, serverContent) {
    const key = this.constructor.STORAGE_PREFIX + path
    const raw = localStorage.getItem(key)
    if (!raw) return null
    try {
      const data = JSON.parse(raw)
      if (data.content === serverContent) {
        this.clear(path)
        return null
      }
      return data
    } catch {
      this.clear(path)
      return null
    }
  }

  clear(path) {
    localStorage.removeItem(this.constructor.STORAGE_PREFIX + path)
  }

  rename(oldPath, newPath) {
    if (!oldPath || !newPath || oldPath === newPath) return false

    const oldKey = this.constructor.STORAGE_PREFIX + oldPath
    const newKey = this.constructor.STORAGE_PREFIX + newPath
    const backup = localStorage.getItem(oldKey)
    if (backup === null) return false

    try {
      localStorage.setItem(newKey, backup)
      localStorage.removeItem(oldKey)
      return true
    } catch (e) {
      console.warn("localStorage backup rename failed:", e)
      return false
    }
  }

  clearAll() {
    const prefix = this.constructor.STORAGE_PREFIX
    const keys = []
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i)
      if (key.startsWith(prefix)) keys.push(key)
    }
    keys.forEach(k => localStorage.removeItem(k))
  }
}
