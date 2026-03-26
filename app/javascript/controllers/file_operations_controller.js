import { Controller } from "@hotwired/stimulus"
import { get, post, patch, destroy } from "@rails/request.js"
import { downloadBlobFile } from "lib/browser_export_utils"
import { encodePath } from "lib/url_utils"

const BUILT_IN_TEMPLATE_METADATA = {
  "daily-note.md": {
    nameKey: "dialogs.templates.built_ins.daily_note.name",
    descriptionKey: "dialogs.templates.built_ins.daily_note.description"
  },
  "meeting-note.md": {
    nameKey: "dialogs.templates.built_ins.meeting_note.name",
    descriptionKey: "dialogs.templates.built_ins.meeting_note.description"
  },
  "article-draft.md": {
    nameKey: "dialogs.templates.built_ins.article_draft.name",
    descriptionKey: "dialogs.templates.built_ins.article_draft.description"
  },
  "journal-entry.md": {
    nameKey: "dialogs.templates.built_ins.journal_entry.name",
    descriptionKey: "dialogs.templates.built_ins.journal_entry.description"
  },
  "changelog.md": {
    nameKey: "dialogs.templates.built_ins.changelog.name",
    descriptionKey: "dialogs.templates.built_ins.changelog.description"
  }
}

// File Operations Controller
// Handles file/folder creation, renaming, deletion and context menu
// Dispatches events: file-created, file-renamed, file-deleted, folder-created

export default class extends Controller {
  static values = {
    backupNoteLabel: String,
    backupFolderLabel: String,
    backupPreparingMessage: String,
    backupStartedMessage: String,
    backupFailedMessage: String
  }

  static targets = [
    "contextMenu",
    "backupMenuItem",
    "backupMenuLabel",
    "templateNoteMenuItem",
    "templateNoteMenuLabel",
    "renameDialog",
    "renameInput",
    "noteTypeDialog",
    "templateDialog",
    "templateList",
    "templateLoading",
    "templateEmpty",
    "templateManagerDialog",
    "templateManagerList",
    "templateManagerNotice",
    "templateFormTitle",
    "templatePathInput",
    "templateContentInput",
    "templateDeleteButton",
    "templateSaveButton",
    "saveTemplateDialog",
    "saveTemplateTitle",
    "saveTemplateNotePath",
    "saveTemplateInput",
    "newItemDialog",
    "newItemTitle",
    "newItemInput"
  ]

  connect() {
    this.contextItem = null
    this.newItemType = null
    this.newItemParent = ""
    this.newItemTemplate = null
    this.contextClickX = 0
    this.contextClickY = 0
    this.templates = []
    this.currentTemplatePath = null
    this.returnToTemplatePicker = false
    this.templateManagerRefreshVersion = 0
    this.currentTemplateSourceNotePath = null
    this.currentTemplateLinkedPath = null
    this.templateManagerNoticeTimeout = null
    this.contextItemTemplateLinked = false
    this.contextItemTemplatePath = null

    this.setupContextMenuClose()
    this.setupDialogClickOutside()
  }

  get expandedFolders() {
    const appEl = document.querySelector('[data-controller~="app"]')
    if (!appEl) return ""
    const app = this.application.getControllerForElementAndIdentifier(appEl, "app")
    return app?.expandedFolders ? [...app.expandedFolders].join(",") : ""
  }

  setupContextMenuClose() {
    this.boundContextMenuClose = (event) => {
      if (!this.hasContextMenuTarget) return
      if (!this.contextMenuTarget.contains(event.target)) {
        this.contextMenuTarget.classList.add("hidden")
      }
    }
    document.addEventListener("click", this.boundContextMenuClose)
  }

  setupDialogClickOutside() {
    const dialogs = [
      this.renameDialogTarget,
      this.newItemDialogTarget,
      this.noteTypeDialogTarget,
      this.templateDialogTarget,
      this.templateManagerDialogTarget,
      this.saveTemplateDialogTarget
    ].filter(d => d)

    dialogs.forEach(dialog => {
      dialog.addEventListener("click", (event) => {
        if (event.target === dialog) {
          dialog.close()
        }
      })
    })
  }

  disconnect() {
    this.clearTemplateManagerNotice({ preserveText: false })
    if (this.boundContextMenuClose) {
      document.removeEventListener("click", this.boundContextMenuClose)
    }
  }

  // Context Menu
  showContextMenu(event) {
    event.preventDefault()
    event.stopPropagation()

    const target = event.currentTarget
    const path = target.dataset.path
    const type = target.dataset.type
    const fileType = target.dataset.fileType

    // Don't show context menu for config files
    if (fileType === "config") return

    this.contextItem = { path, type, fileType }
    this.contextClickX = event.clientX
    this.contextClickY = event.clientY
    this.contextItemTemplateLinked = false
    this.contextItemTemplatePath = null

    // Update menu items based on type
    const renameItem = this.contextMenuTarget.querySelector('[data-action*="renameItem"]')
    const deleteItem = this.contextMenuTarget.querySelector('[data-action*="deleteItem"]')
    const newNoteItem = this.contextMenuTarget.querySelector('[data-action*="newNoteInFolder"]')

    if (renameItem) renameItem.classList.toggle("hidden", false)
    if (deleteItem) deleteItem.classList.toggle("hidden", false)
    if (newNoteItem) newNoteItem.classList.toggle("hidden", type !== "folder")

    const newFolderItem = this.contextMenuTarget.querySelector('[data-action*="newFolderInFolder"]')
    if (newFolderItem) newFolderItem.classList.toggle("hidden", type !== "folder")
    this.updateBackupContextMenuItem()
    this.updateTemplateContextMenuItem()

    // Position and show menu
    this.contextMenuTarget.style.left = `${event.clientX}px`
    this.contextMenuTarget.style.top = `${event.clientY}px`
    this.contextMenuTarget.classList.remove("hidden")

    // Adjust if menu would go off screen
    const menuRect = this.contextMenuTarget.getBoundingClientRect()
    if (menuRect.right > window.innerWidth) {
      this.contextMenuTarget.style.left = `${window.innerWidth - menuRect.width - 10}px`
    }
    if (menuRect.bottom > window.innerHeight) {
      this.contextMenuTarget.style.top = `${window.innerHeight - menuRect.height - 10}px`
    }
  }

  hideContextMenu() {
    if (this.hasContextMenuTarget) {
      this.contextMenuTarget.classList.add("hidden")
    }
  }

  async updateTemplateContextMenuItem() {
    if (!this.hasTemplateNoteMenuItemTarget || !this.hasTemplateNoteMenuLabelTarget) return

    this.templateNoteMenuItemTarget.classList.add("hidden")
    const notePath = this.contextItem?.path
    if (!notePath || this.contextItem?.type !== "file" || this.contextItem?.fileType !== "markdown") return

    try {
      const status = await this.fetchTemplateLinkStatus(notePath)
      if (!this.contextItem || this.contextItem.path !== notePath) return

      this.contextItemTemplateLinked = Boolean(status.linked)
      this.contextItemTemplatePath = status.template_path || null
      this.templateNoteMenuLabelTarget.textContent = window.t(
        this.contextItemTemplateLinked ? "context_menu.delete_template" : "context_menu.save_as_template"
      )
      this.templateNoteMenuItemTarget.classList.remove("hidden")
    } catch (error) {
      console.error("Failed to load template link status:", error)
    }
  }

  updateBackupContextMenuItem() {
    if (!this.hasBackupMenuItemTarget || !this.hasBackupMenuLabelTarget) return

    const itemType = this.contextItem?.type
    const canBackup = itemType === "folder" || itemType === "file"

    this.backupMenuItemTarget.classList.toggle("hidden", !canBackup)
    if (!canBackup) return

    this.backupMenuLabelTarget.textContent = itemType === "folder"
      ? this.backupFolderLabelValue
      : this.backupNoteLabelValue
  }

  async downloadBackup() {
    if (!this.contextItem) return

    const backupType = this.contextItem.type === "folder" ? "folder" : "note"
    const downloadUrl = `/backup/${backupType}/${encodePath(this.contextItem.path)}`
    const fallbackFilename = this.defaultBackupFilename()

    this.hideContextMenu()
    this.showStatusMessage(this.backupPreparingMessageValue || "Preparing backup...")

    try {
      const response = await fetch(downloadUrl, {
        headers: {
          Accept: "application/zip, application/json"
        },
        credentials: "same-origin"
      })

      if (!response.ok) {
        throw new Error(await this.extractBackupError(response))
      }

      const blob = await response.blob()
      const filename = this.extractDownloadFilename(
        response.headers.get("Content-Disposition"),
        fallbackFilename
      )

      downloadBlobFile(filename, blob)
      this.showStatusMessage(this.backupStartedMessageValue || "Backup download started")
    } catch (error) {
      console.error("Failed to download backup:", error)
      this.showStatusMessage(
        error.message || this.backupFailedMessageValue || "Failed to download backup",
        true
      )
    }
  }

  defaultBackupFilename() {
    const itemName = (this.contextItem?.path || "backup")
      .split("/")
      .pop()
      .replace(/\.(md|markdown)$/i, "")

    return `${itemName}-backup.zip`
  }

  async extractBackupError(response) {
    const contentType = response.headers.get("Content-Type") || ""

    if (contentType.includes("application/json")) {
      try {
        const data = await response.json()
        if (data?.error) return data.error
      } catch {
        // Fall through to the generic message below.
      }
    }

    return this.backupFailedMessageValue || "Failed to download backup"
  }

  extractDownloadFilename(contentDisposition, fallbackName) {
    if (!contentDisposition) return fallbackName

    const utf8Match = contentDisposition.match(/filename\*=UTF-8''([^;]+)/i)
    if (utf8Match?.[1]) {
      return decodeURIComponent(utf8Match[1])
    }

    const filenameMatch = contentDisposition.match(/filename="?([^";]+)"?/i)
    return filenameMatch?.[1] || fallbackName
  }

  showStatusMessage(message, error = false, duration = 2500) {
    if (!message) return

    this.dispatch("status-message", {
      detail: {
        message,
        error,
        duration
      }
    })
  }

  // New Note
  newNote() {
    if (this.hasNoteTypeDialogTarget) {
      this.noteTypeDialogTarget.showModal()
    }
  }

  closeNoteTypeDialog() {
    if (this.hasNoteTypeDialogTarget) {
      this.noteTypeDialogTarget.close()
    }
  }

  selectNoteTypeEmpty() {
    this.closeNoteTypeDialog()
    this.openNewItemDialog("note", "", "empty")
  }

  async selectNoteTypeTemplate() {
    this.closeNoteTypeDialog()
    await this.openTemplateDialog()
  }

  selectNoteTypeHugo() {
    this.closeNoteTypeDialog()
    this.openNewItemDialog("note", "", "hugo")
  }

  // New Folder
  newFolder() {
    this.openNewItemDialog("folder", "")
  }

  // New Folder in Folder (from context menu)
  newFolderInFolder() {
    this.hideContextMenu()
    if (!this.contextItem || this.contextItem.type !== "folder") return
    this.openNewItemDialog("folder", this.contextItem.path)
  }

  // New Note in Folder (from context menu)
  newNoteInFolder() {
    this.hideContextMenu()
    if (!this.contextItem || this.contextItem.type !== "folder") return

    if (this.hasNoteTypeDialogTarget) {
      this.noteTypeDialogTarget.showModal()
      // Store parent for after type selection
      this.newItemParent = this.contextItem.path
    }
  }

  async openTemplateDialog() {
    if (!this.hasTemplateDialogTarget) return

    this.renderTemplateLoadingState()
    this.templateDialogTarget.showModal()

    try {
      this.templates = await this.fetchTemplates()
      this.renderTemplateList()
    } catch (error) {
      console.error("Failed to load templates:", error)
      this.renderTemplateEmptyState()
      alert(error.message || window.t("errors.failed_to_load_templates"))
    }
  }

  closeTemplateDialog() {
    if (this.hasTemplateDialogTarget) {
      this.templateDialogTarget.close()
    }
  }

  async fetchTemplates() {
    const response = await get("/templates", { responseKind: "json" })

    if (!response.ok) {
      const data = await response.json
      throw new Error(data.error || window.t("errors.failed_to_load_templates"))
    }

    return await response.json
  }

  async fetchTemplateLinkStatus(notePath) {
    const response = await get(`/templates/status/${encodePath(notePath)}`, { responseKind: "json" })

    if (!response.ok) {
      const data = await response.json
      throw new Error(data.error || window.t("errors.failed_to_load_templates"))
    }

    return await response.json
  }

  renderTemplateLoadingState() {
    this.templateLoadingTarget?.classList.remove("hidden")
    this.templateEmptyTarget?.classList.add("hidden")
    if (this.hasTemplateListTarget) this.templateListTarget.innerHTML = ""
  }

  renderTemplateEmptyState() {
    this.templateLoadingTarget?.classList.add("hidden")
    this.templateEmptyTarget?.classList.remove("hidden")
    if (this.hasTemplateListTarget) this.templateListTarget.innerHTML = ""
  }

  renderTemplateList() {
    this.templateLoadingTarget?.classList.add("hidden")

    if (!this.hasTemplateListTarget || this.templates.length === 0) {
      this.renderTemplateEmptyState()
      return
    }

    this.templateEmptyTarget?.classList.add("hidden")
    this.templateListTarget.innerHTML = this.templates.map((template) => {
      const title = this.escapeHtml(this.templateDisplayName(template))
      const description = this.escapeHtml(this.templateDescription(template))
      const path = this.escapeHtml(template.path)

      return `
        <button
          type="button"
          class="w-full px-3 py-2.5 text-left text-sm rounded-md hover:bg-[var(--theme-bg-hover)] border border-[var(--theme-border)]"
          data-template-path="${path}"
          data-action="click->file-operations#selectTemplate"
        >
          <div class="font-medium text-[var(--theme-text-primary)]">${title}</div>
          <div class="text-xs text-[var(--theme-text-muted)]">${description}</div>
        </button>
      `
    }).join("")
  }

  selectTemplate(event) {
    const templatePath = event.currentTarget.dataset.templatePath
    const template = this.templates.find((entry) => entry.path === templatePath)
    if (!template) return

    this.closeTemplateDialog()
    this.openNewItemDialog("note", "", template.path)

    if (this.hasNewItemInputTarget) {
      this.newItemInputTarget.value = this.defaultNoteNameForTemplate(template)
      this.newItemInputTarget.select()
    }
  }

  async openTemplateManager() {
    if (!this.hasTemplateManagerDialogTarget) return

    this.returnToTemplatePicker = this.hasTemplateDialogTarget && this.templateDialogTarget.open
    if (this.returnToTemplatePicker) this.closeTemplateDialog()

    this.clearTemplateManagerNotice()
    this.templateManagerDialogTarget.showModal()
    await this.refreshTemplateManager({ selectFirst: true })
  }

  async closeTemplateManager() {
    this.clearTemplateManagerNotice()
    if (this.hasTemplateManagerDialogTarget) {
      this.templateManagerDialogTarget.close()
    }

    const shouldReturnToPicker = this.returnToTemplatePicker
    this.returnToTemplatePicker = false

    if (shouldReturnToPicker) {
      await this.openTemplateDialog()
    }
  }

  async refreshTemplateManager(options = {}) {
    const normalizedOptions = options instanceof Event
      ? { selectPath: this.currentTemplatePath, selectFirst: !this.currentTemplatePath }
      : options
    const { selectPath = null, selectFirst = false } = normalizedOptions
    const refreshVersion = ++this.templateManagerRefreshVersion

    try {
      this.templates = await this.fetchTemplates()
      if (refreshVersion !== this.templateManagerRefreshVersion) return

      this.renderTemplateManagerList()

      const pathToLoad = selectPath || this.currentTemplatePath || (selectFirst ? this.templates[0]?.path : null)
      if (pathToLoad) {
        await this.loadTemplateForEditing(pathToLoad, { refreshVersion })
      } else {
        if (refreshVersion !== this.templateManagerRefreshVersion) return
        this.prepareNewTemplate()
      }
    } catch (error) {
      if (refreshVersion && refreshVersion !== this.templateManagerRefreshVersion) return
      console.error("Failed to refresh templates:", error)
      alert(error.message || window.t("errors.failed_to_load_templates"))
    }
  }

  renderTemplateManagerList() {
    if (!this.hasTemplateManagerListTarget) return

    if (this.templates.length === 0) {
      this.templateManagerListTarget.innerHTML = `
        <div class="text-sm text-[var(--theme-text-muted)] px-3 py-2">
          ${this.escapeHtml(window.t("dialogs.templates.empty"))}
        </div>
      `
      return
    }

    this.templateManagerListTarget.innerHTML = this.templates.map((template) => {
      const title = this.escapeHtml(this.templateDisplayName(template))
      const path = this.escapeHtml(template.path)
      const active = template.path === this.currentTemplatePath

      return `
        <button
          type="button"
          class="w-full px-3 py-2 text-left rounded-md border ${active ? "border-[var(--theme-accent)] bg-[var(--theme-bg-hover)]" : "border-[var(--theme-border)] hover:bg-[var(--theme-bg-hover)]"}"
          data-template-path="${path}"
          data-action="click->file-operations#editTemplate"
        >
          <div class="text-sm font-medium text-[var(--theme-text-primary)]">${title}</div>
          <div class="text-xs text-[var(--theme-text-muted)]">${path}</div>
        </button>
      `
    }).join("")
  }

  async editTemplate(event) {
    const templatePath = event.currentTarget.dataset.templatePath
    if (!templatePath) return

    this.templateManagerRefreshVersion += 1
    await this.loadTemplateForEditing(templatePath)
  }

  async loadTemplateForEditing(templatePath, { refreshVersion = null } = {}) {
    this.setTemplateFormBusy(true)

    try {
      const response = await get(`/templates/${encodePath(templatePath)}`, { responseKind: "json" })
      if (!response.ok) {
        const data = await response.json
        throw new Error(data.error || window.t("errors.failed_to_load_templates"))
      }

      const template = await response.json
      if (refreshVersion && refreshVersion !== this.templateManagerRefreshVersion) return

      this.currentTemplatePath = template.path
      this.clearTemplateManagerNotice()

      if (this.hasTemplateFormTitleTarget) {
        this.templateFormTitleTarget.textContent = window.t("dialogs.templates.edit_title")
      }
      if (this.hasTemplatePathInputTarget) {
        this.templatePathInputTarget.value = template.path
        this.templatePathInputTarget.readOnly = false
      }
      if (this.hasTemplateContentInputTarget) {
        this.templateContentInputTarget.value = template.content
      }
      this.templateDeleteButtonTarget?.classList.remove("hidden")
      this.renderTemplateManagerList()
      this.setTemplateFormBusy(false)
    } catch (error) {
      if (refreshVersion && refreshVersion !== this.templateManagerRefreshVersion) return
      this.setTemplateFormBusy(false)
      console.error("Failed to load template:", error)
      alert(error.message || window.t("errors.failed_to_load_templates"))
    }
  }

  newTemplate() {
    this.templateManagerRefreshVersion += 1
    this.prepareNewTemplate()
    this.renderTemplateManagerList()
  }

  prepareNewTemplate() {
    this.currentTemplatePath = null
    this.clearTemplateManagerNotice()
    this.setTemplateFormBusy(false)

    if (this.hasTemplateFormTitleTarget) {
      this.templateFormTitleTarget.textContent = window.t("dialogs.templates.new_title")
    }
    if (this.hasTemplatePathInputTarget) {
      this.templatePathInputTarget.value = ""
      this.templatePathInputTarget.readOnly = false
      this.templatePathInputTarget.focus()
    }
    if (this.hasTemplateContentInputTarget) {
      this.templateContentInputTarget.value = ""
    }
    this.templateDeleteButtonTarget?.classList.add("hidden")
  }

  async submitTemplateSave() {
    if (!this.hasTemplatePathInputTarget || !this.hasTemplateContentInputTarget) return

    const path = this.templatePathInputTarget.value.trim()
    const content = this.templateContentInputTarget.value
    if (!path) {
      alert(window.t("errors.no_file_provided"))
      return
    }

    try {
      let response
      if (this.currentTemplatePath) {
        response = await patch(`/templates/${encodePath(this.currentTemplatePath)}`, {
          body: { content, new_path: path },
          responseKind: "json"
        })
      } else {
        response = await post("/templates", {
          body: { path, content },
          responseKind: "json"
        })
      }

      if (!response.ok) {
        const data = await response.json
        throw new Error(data.error || window.t("errors.failed_to_save"))
      }

      const data = await response.json
      await this.refreshTemplateManager({ selectPath: data.path })
      this.showTemplateManagerNotice(window.t("success.template_saved"))
    } catch (error) {
      console.error("Failed to save template:", error)
      alert(error.message || window.t("errors.failed_to_save"))
    }
  }

  async deleteTemplate() {
    if (!this.currentTemplatePath) return

    const displayName = this.displayNameForTemplatePath(this.currentTemplatePath)
    if (!confirm(window.t("dialogs.templates.delete_confirm", { name: displayName }))) {
      return
    }

    try {
      const response = await destroy(`/templates/${encodePath(this.currentTemplatePath)}`, {
        responseKind: "json"
      })

      if (!response.ok) {
        const data = await response.json
        throw new Error(data.error || window.t("errors.failed_to_delete"))
      }

      this.currentTemplatePath = null
      await this.refreshTemplateManager({ selectFirst: true })
      this.showTemplateManagerNotice(window.t("success.template_deleted"))
    } catch (error) {
      console.error("Failed to delete template:", error)
      alert(error.message || window.t("errors.failed_to_delete"))
    }
  }

  async openSaveTemplateFromNoteDialog(notePath) {
    if (!this.hasSaveTemplateDialogTarget || !this.hasSaveTemplateInputTarget) return
    if (!notePath) return

    try {
      const status = await this.fetchTemplateLinkStatus(notePath)
      this.currentTemplateSourceNotePath = notePath
      this.currentTemplateLinkedPath = status.template_path || null

      if (this.hasSaveTemplateTitleTarget) {
        this.saveTemplateTitleTarget.textContent = window.t(
          status.linked ? "dialogs.templates.save_from_note_update_title" : "dialogs.templates.save_from_note_title"
        )
      }
      if (this.hasSaveTemplateNotePathTarget) {
        this.saveTemplateNotePathTarget.textContent = notePath
      }

      const defaultTemplatePath = status.template_path || notePath
      this.saveTemplateInputTarget.value = defaultTemplatePath.replace(/\.(md|markdown)$/i, "")
      this.saveTemplateDialogTarget.showModal()
      this.saveTemplateInputTarget.focus()
      this.saveTemplateInputTarget.select()
    } catch (error) {
      console.error("Failed to open save template dialog:", error)
      alert(error.message || window.t("errors.failed_to_load_templates"))
    }
  }

  closeSaveTemplateDialog() {
    if (this.hasSaveTemplateDialogTarget) {
      this.saveTemplateDialogTarget.close()
    }
    this.currentTemplateSourceNotePath = null
    this.currentTemplateLinkedPath = null
  }

  async submitSaveTemplateFromNote() {
    if (!this.currentTemplateSourceNotePath || !this.hasSaveTemplateInputTarget) return

    const templatePath = this.saveTemplateInputTarget.value.trim()
    if (!templatePath) {
      alert(window.t("errors.no_file_provided"))
      return
    }

    try {
      const response = await post("/templates/save_from_note", {
        body: {
          note_path: this.currentTemplateSourceNotePath,
          template_path: templatePath
        },
        responseKind: "json"
      })

      if (!response.ok) {
        const data = await response.json
        throw new Error(data.error || window.t("errors.failed_to_save"))
      }

      const data = await response.json
      this.currentTemplateLinkedPath = data.path
      this.closeSaveTemplateDialog()

      if (this.contextItem?.path === data.note_path) {
        this.contextItemTemplateLinked = true
        this.contextItemTemplatePath = data.path
      }
    } catch (error) {
      console.error("Failed to save template from note:", error)
      alert(error.message || window.t("errors.failed_to_save"))
    }
  }

  async handleTemplateContextAction() {
    if (!this.contextItem || this.contextItem.type !== "file") return

    if (this.contextItemTemplateLinked) {
      await this.deleteTemplateForNote(this.contextItem.path)
    } else {
      this.hideContextMenu()
      await this.openSaveTemplateFromNoteDialog(this.contextItem.path)
    }
  }

  async deleteTemplateForNote(notePath) {
    try {
      const status = await this.fetchTemplateLinkStatus(notePath)
      const displayName = this.displayNameForTemplatePath(status.template_path || notePath)
      if (!confirm(window.t("dialogs.templates.delete_linked_confirm", { name: displayName }))) {
        return
      }

      const response = await destroy("/templates/save_from_note", {
        body: { note_path: notePath },
        responseKind: "json"
      })

      if (!response.ok) {
        const data = await response.json
        throw new Error(data.error || window.t("errors.failed_to_delete"))
      }

      this.hideContextMenu()
      this.contextItemTemplateLinked = false
      this.contextItemTemplatePath = null
    } catch (error) {
      console.error("Failed to delete linked template:", error)
      alert(error.message || window.t("errors.failed_to_delete"))
    }
  }

  openNewItemDialog(type, parent = "", template = null) {
    this.newItemType = type
    this.newItemParent = parent || this.newItemParent || ""
    this.newItemTemplate = template

    if (this.hasNewItemTitleTarget) {
      const titleKey = this.newItemDialogTitleKey(type, template)
      this.newItemTitleTarget.textContent = window.t(titleKey)
    }

    if (this.hasNewItemInputTarget) {
      this.newItemInputTarget.value = ""
      this.newItemInputTarget.placeholder = type === "folder"
        ? window.t("dialogs.new_item.folder_placeholder")
        : window.t("dialogs.new_item.note_placeholder")
    }

    if (this.hasNewItemDialogTarget) {
      this.newItemDialogTarget.showModal()
      this.newItemInputTarget?.focus()
    }
  }

  closeNewItemDialog() {
    if (this.hasNewItemDialogTarget) {
      this.newItemDialogTarget.close()
    }
    this.newItemType = null
    this.newItemParent = ""
    this.newItemTemplate = null
  }

  async submitNewItem() {
    if (!this.hasNewItemInputTarget) return

    const name = this.newItemInputTarget.value.trim()
    if (!name) return

    const type = this.newItemType
    const parent = this.newItemParent
    const template = this.newItemTemplate

    try {
      if (type === "folder") {
        await this.createFolder(name, parent)
      } else {
        await this.createNote(name, parent, template)
      }
      this.closeNewItemDialog()
    } catch (error) {
      console.error("Failed to create item:", error)
      alert(error.message || window.t("errors.failed_to_create"))
    }
  }

  async createNote(name, parent, template) {
    let response
    const expanded = this.expandedFolders

    if (template === "hugo") {
      // Hugo posts: server generates path and content
      const title = name.replace(/\.md$/, "")
      response = await post("/notes", {
        body: { template: "hugo", title, parent: parent || "", expanded },
        responseKind: "turbo-stream"
      })
    } else {
      // Regular notes use simple filename
      const fileName = name.endsWith(".md") ? name : `${name}.md`
      const path = parent ? `${parent}/${fileName}` : fileName
      const body = { content: "", expanded }

      if (template && template !== "empty") {
        body.template_path = template
      }

      response = await post(`/notes/${encodePath(path)}`, {
        body,
        responseKind: "turbo-stream"
      })
    }

    if (!response.ok) {
      const data = await response.json
      throw new Error(data.error || window.t("errors.failed_to_create"))
    }

    // Turbo Stream responses are auto-processed by request.js
    // For JSON fallback, extract the path
    const path = response.isTurboStream
      ? (response.headers.get("X-Created-Path") || this.inferCreatedPath(name, parent, template))
      : (await response.json).path
    this.dispatch("file-created", { detail: { path } })
  }

  // Infer the path for a created note when using turbo stream (no JSON body)
  inferCreatedPath(name, parent, template) {
    if (template === "hugo") {
      // The server marks the created file as selected in the turbo-stream response.
      // By the time post() resolves, Turbo has updated the DOM, so just query for it.
      const treeEl = document.getElementById("file-tree-content")
      const selected = treeEl?.querySelector('.tree-item.selected[data-type="file"]')
      if (selected?.dataset.path) return selected.dataset.path
      return name
    }
    const fileName = name.endsWith(".md") ? name : `${name}.md`
    return parent ? `${parent}/${fileName}` : fileName
  }

  async createFolder(name, parent) {
    const path = parent ? `${parent}/${name}` : name
    const expanded = this.expandedFolders

    const response = await post(`/folders/${encodePath(path)}?expanded=${encodeURIComponent(expanded)}`, {
      responseKind: "turbo-stream"
    })

    if (!response.ok) {
      const data = await response.json
      throw new Error(data.error || window.t("errors.failed_to_create"))
    }

    // Turbo Stream response auto-processed by request.js
    this.dispatch("folder-created", { detail: { path } })
  }

  // Rename
  renameItem() {
    this.hideContextMenu()
    if (!this.contextItem) return

    if (this.hasRenameInputTarget) {
      // Show just the name, not the full path
      const name = this.contextItem.path.split("/").pop()
      // Remove .md extension for display
      this.renameInputTarget.value = this.contextItem.type === "file"
        ? name.replace(/\.md$/, "")
        : name
    }

    if (this.hasRenameDialogTarget) {
      this.renameDialogTarget.showModal()
      this.renameInputTarget?.focus()
      this.renameInputTarget?.select()
    }
  }

  closeRenameDialog() {
    if (this.hasRenameDialogTarget) {
      this.renameDialogTarget.close()
    }
  }

  async submitRename() {
    if (!this.contextItem || !this.hasRenameInputTarget) return

    let newName = this.renameInputTarget.value.trim()
    if (!newName) return

    // Add .md extension for files if not present
    if (this.contextItem.type === "file" && !newName.endsWith(".md")) {
      newName = `${newName}.md`
    }

    // Build new path
    const pathParts = this.contextItem.path.split("/")
    pathParts[pathParts.length - 1] = newName
    const newPath = pathParts.join("/")

    // Don't rename if path is the same
    if (newPath === this.contextItem.path) {
      this.closeRenameDialog()
      return
    }

    try {
      const endpoint = this.contextItem.type === "file" ? "notes" : "folders"
      const expanded = this.expandedFolders
      const response = await post(`/${endpoint}/${encodePath(this.contextItem.path)}/rename`, {
        body: { new_path: newPath, expanded },
        responseKind: "turbo-stream"
      })

      if (!response.ok) {
        const data = await response.json
        throw new Error(data.error || window.t("errors.failed_to_rename"))
      }

      // Turbo Stream response auto-processed by request.js

      this.dispatch("file-renamed", {
        detail: {
          oldPath: this.contextItem.path,
          newPath: newPath,
          type: this.contextItem.type
        }
      })

      this.closeRenameDialog()
    } catch (error) {
      console.error("Failed to rename:", error)
      alert(error.message || window.t("errors.failed_to_rename"))
    }
  }

  // Delete
  async deleteItem() {
    this.hideContextMenu()
    if (!this.contextItem) return

    const itemName = this.displayNameForPath(
      this.contextItem.path,
      { stripMarkdown: this.contextItem.type === "file" }
    )
    const confirmKey = this.contextItem.type === "folder"
      ? "confirm.delete_folder"
      : "confirm.delete_note"

    if (!confirm(window.t(confirmKey, { name: itemName }))) {
      return
    }

    try {
      const endpoint = this.contextItem.type === "file" ? "notes" : "folders"
      const expanded = this.expandedFolders
      const response = await destroy(`/${endpoint}/${encodePath(this.contextItem.path)}?expanded=${encodeURIComponent(expanded)}`, {
        responseKind: "turbo-stream"
      })

      if (!response.ok) {
        const data = await response.json
        throw new Error(data.error || window.t("errors.failed_to_delete"))
      }

      // Turbo Stream response auto-processed by request.js

      this.dispatch("file-deleted", {
        detail: {
          path: this.contextItem.path,
          type: this.contextItem.type
        }
      })
    } catch (error) {
      console.error("Failed to delete:", error)
      alert(error.message || window.t("errors.failed_to_delete"))
    }
  }

  // Keyboard handlers
  onRenameKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.submitRename()
    } else if (event.key === "Escape") {
      this.closeRenameDialog()
    }
  }

  onNewItemKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.submitNewItem()
    } else if (event.key === "Escape") {
      this.closeNewItemDialog()
    }
  }

  onSaveTemplateKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.submitSaveTemplateFromNote()
    } else if (event.key === "Escape") {
      this.closeSaveTemplateDialog()
    }
  }

  newItemDialogTitleKey(type, template) {
    if (type === "folder") return "dialogs.new_item.new_folder"
    if (template && template !== "empty" && template !== "hugo") return "dialogs.new_item.new_note_from_template"
    return "dialogs.new_item.new_note"
  }

  templateDisplayName(template) {
    const builtIn = BUILT_IN_TEMPLATE_METADATA[template.path]
    if (builtIn) return window.t(builtIn.nameKey)

    return this.humanizeTemplateName(template.name)
  }

  templateDescription(template) {
    const builtIn = BUILT_IN_TEMPLATE_METADATA[template.path]
    if (builtIn) return window.t(builtIn.descriptionKey)

    return template.directory || template.path
  }

  defaultNoteNameForTemplate(template) {
    switch (template.path) {
      case "daily-note.md":
        return this.todayStamp()
      case "meeting-note.md":
        return `meeting-${this.todayStamp()}`
      case "article-draft.md":
        return "article-draft"
      case "journal-entry.md":
        return `journal-${this.todayStamp()}`
      case "changelog.md":
        return "changelog"
      default:
        return template.name
    }
  }

  todayStamp() {
    return new Date().toISOString().slice(0, 10)
  }

  humanizeTemplateName(name) {
    return name
      .replace(/[-_]+/g, " ")
      .replace(/(^|[\s])([\p{L}\p{N}])/gu, (match, prefix, char) => `${prefix}${char.toLocaleUpperCase()}`)
  }

  displayNameForTemplatePath(path) {
    return this.templateDisplayName({
      path,
      name: this.displayNameForPath(path, { stripMarkdown: true })
    })
  }

  displayNameForPath(path, { stripMarkdown = false } = {}) {
    const leaf = String(path || "").split("/").pop() || String(path || "")

    if (!stripMarkdown) return leaf

    return leaf.replace(/\.(md|markdown)$/i, "")
  }

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
  }

  showTemplateManagerNotice(message, tone = "success") {
    if (!this.hasTemplateManagerNoticeTarget || !message) return

    if (this.templateManagerNoticeTimeout) {
      clearTimeout(this.templateManagerNoticeTimeout)
      this.templateManagerNoticeTimeout = null
    }

    this.templateManagerNoticeTarget.textContent = message
    this.templateManagerNoticeTarget.dataset.tone = tone
    this.templateManagerNoticeTarget.style.color = tone === "error"
      ? "var(--theme-error)"
      : "var(--theme-success)"
    this.templateManagerNoticeTarget.classList.remove("hidden")

    this.templateManagerNoticeTimeout = setTimeout(() => {
      this.clearTemplateManagerNotice({ preserveText: false })
    }, 3500)
  }

  clearTemplateManagerNotice({ preserveText = true } = {}) {
    if (!this.hasTemplateManagerNoticeTarget) return

    if (this.templateManagerNoticeTimeout) {
      clearTimeout(this.templateManagerNoticeTimeout)
      this.templateManagerNoticeTimeout = null
    }

    this.templateManagerNoticeTarget.classList.add("hidden")
    this.templateManagerNoticeTarget.removeAttribute("data-tone")
    this.templateManagerNoticeTarget.style.removeProperty("color")

    if (!preserveText) {
      this.templateManagerNoticeTarget.textContent = ""
    }
  }

  setTemplateFormBusy(isBusy) {
    this.templatePathInputTarget?.toggleAttribute("disabled", isBusy)
    this.templateContentInputTarget?.toggleAttribute("disabled", isBusy)
    this.templateDeleteButtonTarget?.toggleAttribute("disabled", isBusy)
    this.templateSaveButtonTarget?.toggleAttribute("disabled", isBusy)
  }
}
