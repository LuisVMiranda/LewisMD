/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import FileOperationsController from "../../../app/javascript/controllers/file_operations_controller.js"

describe("FileOperationsController", () => {
  let application, controller, element

  beforeEach(() => {
    // Mock window.t for translations
    window.t = vi.fn((key, params) => {
      if (params) return `${key} ${JSON.stringify(params)}`
      return key
    })

    // Add CSRF token
    document.head.innerHTML = '<meta name="csrf-token" content="test-token">'

    document.body.innerHTML = `
      <div data-controller="file-operations">
        <div data-file-operations-target="contextMenu" class="hidden">
          <button data-action="click->file-operations#renameItem">Rename</button>
          <button data-action="click->file-operations#deleteItem">Delete</button>
          <button data-action="click->file-operations#newNoteInFolder">New Note</button>
          <button data-action="click->file-operations#newFolderInFolder">New Folder</button>
          <button data-file-operations-target="templateNoteMenuItem" class="hidden">
            <span data-file-operations-target="templateNoteMenuLabel"></span>
          </button>
        </div>
        <dialog data-file-operations-target="renameDialog">
          <input data-file-operations-target="renameInput" type="text" />
        </dialog>
        <dialog data-file-operations-target="saveTemplateDialog">
          <h3 data-file-operations-target="saveTemplateTitle"></h3>
          <p data-file-operations-target="saveTemplateNotePath"></p>
          <input data-file-operations-target="saveTemplateInput" type="text" />
        </dialog>
        <dialog data-file-operations-target="noteTypeDialog"></dialog>
        <dialog data-file-operations-target="templateDialog">
          <div data-file-operations-target="templateLoading" class="hidden"></div>
          <div data-file-operations-target="templateEmpty" class="hidden"></div>
          <div data-file-operations-target="templateList"></div>
        </dialog>
        <dialog data-file-operations-target="templateManagerDialog">
          <div data-file-operations-target="templateManagerList"></div>
          <p data-file-operations-target="templateManagerNotice" class="hidden"></p>
          <h4 data-file-operations-target="templateFormTitle"></h4>
          <input data-file-operations-target="templatePathInput" type="text" />
          <textarea data-file-operations-target="templateContentInput"></textarea>
          <button data-file-operations-target="templateDeleteButton" class="hidden">Delete</button>
        </dialog>
        <dialog data-file-operations-target="newItemDialog">
          <h3 data-file-operations-target="newItemTitle"></h3>
          <input data-file-operations-target="newItemInput" type="text" />
        </dialog>
      </div>
    `

    // Mock showModal and close for dialog
    HTMLDialogElement.prototype.showModal = vi.fn(function () {
      this.open = true
    })
    HTMLDialogElement.prototype.close = vi.fn(function () {
      this.open = false
    })

    // Mock fetch
    global.fetch = vi.fn((url, options = {}) => {
      if (url === "/templates/status/test.md") {
        return Promise.resolve({
          ok: true,
          headers: { get: () => "application/json" },
          json: () => Promise.resolve({
            note_path: "test.md",
            linked: false,
            template_path: null
          }),
          text: () => Promise.resolve("{}")
        })
      }

      if (url === "/templates/status/linked.md") {
        return Promise.resolve({
          ok: true,
          headers: { get: () => "application/json" },
          json: () => Promise.resolve({
            note_path: "linked.md",
            linked: true,
            template_path: "templates/linked.md"
          }),
          text: () => Promise.resolve("{}")
        })
      }

      if (url === "/templates") {
        return Promise.resolve({
          ok: true,
          headers: { get: () => "application/json" },
          json: () => Promise.resolve([
            { path: "article-draft.md", name: "article-draft", directory: "" },
            { path: "team/retro.md", name: "retro", directory: "team" }
          ]),
          text: () => Promise.resolve("[]")
        })
      }

      if (url === "/templates/article-draft.md" || url === "/templates/team/retro.md") {
        const path = url.replace("/templates/", "")
        return Promise.resolve({
          ok: true,
          headers: { get: () => "application/json" },
          json: () => Promise.resolve({
            path,
            content: path === "article-draft.md" ? "# Article Draft" : "# Retro\n\n## Wins"
          }),
          text: () => Promise.resolve("{}")
        })
      }

      if (url === "/templates/save_from_note" && options.method === "POST") {
        return Promise.resolve({
          ok: true,
          headers: { get: () => "application/json" },
          json: () => Promise.resolve({
            note_path: "test.md",
            path: "saved-template.md",
            linked: true
          }),
          text: () => Promise.resolve("{}")
        })
      }

      if (url === "/templates/save_from_note" && options.method === "DELETE") {
        return Promise.resolve({
          ok: true,
          headers: { get: () => "application/json" },
          json: () => Promise.resolve({
            note_path: "linked.md",
            path: "templates/linked.md",
            linked: false
          }),
          text: () => Promise.resolve("{}")
        })
      }

      return Promise.resolve({
        ok: true,
        headers: { get: () => "application/json" },
        json: () => Promise.resolve({ path: "test.md" }),
        text: () => Promise.resolve('{"path": "test.md"}')
      })
    })

    // Mock confirm
    global.confirm = vi.fn().mockReturnValue(true)
    global.alert = vi.fn()

    element = document.querySelector('[data-controller="file-operations"]')
    application = Application.start()
    application.register("file-operations", FileOperationsController)

    return new Promise((resolve) => {
      setTimeout(() => {
        controller = application.getControllerForElementAndIdentifier(element, "file-operations")
        resolve()
      }, 0)
    })
  })

  afterEach(() => {
    application.stop()
    vi.restoreAllMocks()
  })

  describe("connect()", () => {
    it("initializes context item to null", () => {
      expect(controller.contextItem).toBeNull()
    })

    it("initializes new item type to null", () => {
      expect(controller.newItemType).toBeNull()
    })

    it("initializes new item parent to empty string", () => {
      expect(controller.newItemParent).toBe("")
    })
  })

  describe("showContextMenu()", () => {
    it("shows context menu at click position", () => {
      const event = {
        preventDefault: vi.fn(),
        stopPropagation: vi.fn(),
        clientX: 100,
        clientY: 200,
        currentTarget: {
          dataset: { path: "test.md", type: "file" }
        }
      }

      controller.showContextMenu(event)

      expect(controller.contextMenuTarget.classList.contains("hidden")).toBe(false)
      expect(controller.contextMenuTarget.style.left).toBe("100px")
      expect(controller.contextMenuTarget.style.top).toBe("200px")
    })

    it("stores context item", () => {
      const event = {
        preventDefault: vi.fn(),
        stopPropagation: vi.fn(),
        clientX: 100,
        clientY: 200,
        currentTarget: {
          dataset: { path: "folder/test.md", type: "file" }
        }
      }

      controller.showContextMenu(event)

      expect(controller.contextItem).toEqual({
        path: "folder/test.md",
        type: "file",
        fileType: undefined
      })
    })

    it("does not show for config files", () => {
      const event = {
        preventDefault: vi.fn(),
        stopPropagation: vi.fn(),
        clientX: 100,
        clientY: 200,
        currentTarget: {
          dataset: { path: "config.yml", type: "file", fileType: "config" }
        }
      }

      controller.showContextMenu(event)

      expect(controller.contextMenuTarget.classList.contains("hidden")).toBe(true)
    })

    it("shows save-as-template for markdown notes without a linked template", async () => {
      const event = {
        preventDefault: vi.fn(),
        stopPropagation: vi.fn(),
        clientX: 100,
        clientY: 200,
        currentTarget: {
          dataset: { path: "test.md", type: "file", fileType: "markdown" }
        }
      }

      controller.showContextMenu(event)
      await new Promise((resolve) => setTimeout(resolve, 0))

      expect(global.fetch).toHaveBeenCalledWith("/templates/status/test.md", expect.any(Object))
      expect(controller.templateNoteMenuItemTarget.classList.contains("hidden")).toBe(false)
      expect(controller.templateNoteMenuLabelTarget.textContent).toBe("context_menu.save_as_template")
    })
  })

  describe("hideContextMenu()", () => {
    it("hides the context menu", () => {
      controller.contextMenuTarget.classList.remove("hidden")

      controller.hideContextMenu()

      expect(controller.contextMenuTarget.classList.contains("hidden")).toBe(true)
    })
  })

  describe("newNote()", () => {
    it("shows note type dialog", () => {
      controller.newNote()

      expect(controller.noteTypeDialogTarget.showModal).toHaveBeenCalled()
    })
  })

  describe("closeNoteTypeDialog()", () => {
    it("closes the note type dialog", () => {
      controller.newNote()
      controller.closeNoteTypeDialog()

      expect(controller.noteTypeDialogTarget.close).toHaveBeenCalled()
    })
  })

  describe("selectNoteTypeEmpty()", () => {
    it("closes note type dialog and opens new item dialog", () => {
      const openSpy = vi.spyOn(controller, "openNewItemDialog")

      controller.selectNoteTypeEmpty()

      expect(controller.noteTypeDialogTarget.close).toHaveBeenCalled()
      expect(openSpy).toHaveBeenCalledWith("note", "", "empty")
    })
  })

  describe("selectNoteTypeHugo()", () => {
    it("closes note type dialog and opens new item dialog with hugo template", () => {
      const openSpy = vi.spyOn(controller, "openNewItemDialog")

      controller.selectNoteTypeHugo()

      expect(controller.noteTypeDialogTarget.close).toHaveBeenCalled()
      expect(openSpy).toHaveBeenCalledWith("note", "", "hugo")
    })
  })

  describe("selectNoteTypeTemplate()", () => {
    it("closes note type dialog and loads the template picker", async () => {
      const openSpy = vi.spyOn(controller, "openTemplateDialog")

      await controller.selectNoteTypeTemplate()

      expect(controller.noteTypeDialogTarget.close).toHaveBeenCalled()
      expect(openSpy).toHaveBeenCalled()
    })
  })

  describe("newFolder()", () => {
    it("opens new item dialog for folder", () => {
      const openSpy = vi.spyOn(controller, "openNewItemDialog")

      controller.newFolder()

      expect(openSpy).toHaveBeenCalledWith("folder", "")
    })
  })

  describe("newFolderInFolder()", () => {
    it("hides context menu and opens new item dialog for folder", () => {
      controller.contextItem = { path: "parent/myfolder", type: "folder" }
      controller.contextMenuTarget.classList.remove("hidden")
      const openSpy = vi.spyOn(controller, "openNewItemDialog")

      controller.newFolderInFolder()

      expect(controller.contextMenuTarget.classList.contains("hidden")).toBe(true)
      expect(openSpy).toHaveBeenCalledWith("folder", "parent/myfolder")
    })

    it("does nothing if context item is not a folder", () => {
      controller.contextItem = { path: "test.md", type: "file" }
      const openSpy = vi.spyOn(controller, "openNewItemDialog")

      controller.newFolderInFolder()

      expect(openSpy).not.toHaveBeenCalled()
    })

    it("does nothing if no context item", () => {
      controller.contextItem = null
      const openSpy = vi.spyOn(controller, "openNewItemDialog")

      controller.newFolderInFolder()

      expect(openSpy).not.toHaveBeenCalled()
    })
  })

  describe("openNewItemDialog()", () => {
    it("shows the new item dialog", () => {
      controller.openNewItemDialog("note", "")

      expect(controller.newItemDialogTarget.showModal).toHaveBeenCalled()
    })

    it("sets new item type", () => {
      controller.openNewItemDialog("folder", "parent")

      expect(controller.newItemType).toBe("folder")
      expect(controller.newItemParent).toBe("parent")
    })

    it("sets appropriate title for notes", () => {
      controller.openNewItemDialog("note", "")

      expect(controller.newItemTitleTarget.textContent).toBe("dialogs.new_item.new_note")
    })

    it("sets appropriate title for folders", () => {
      controller.openNewItemDialog("folder", "")

      expect(controller.newItemTitleTarget.textContent).toBe("dialogs.new_item.new_folder")
    })

    it("sets template title for notes created from templates", () => {
      controller.openNewItemDialog("note", "", "article-draft.md")

      expect(controller.newItemTitleTarget.textContent).toBe("dialogs.new_item.new_note_from_template")
    })
  })

  describe("openTemplateDialog()", () => {
    it("shows the template dialog", async () => {
      await controller.openTemplateDialog()

      expect(controller.templateDialogTarget.showModal).toHaveBeenCalled()
    })

    it("loads templates from the server", async () => {
      await controller.openTemplateDialog()

      expect(global.fetch).toHaveBeenCalledWith("/templates", expect.any(Object))
      expect(controller.templateListTarget.innerHTML).toContain("dialogs.templates.built_ins.article_draft.name")
      expect(controller.templateListTarget.innerHTML).toContain("Retro")
    })
  })

  describe("selectTemplate()", () => {
    it("opens the new note dialog with a suggested filename", () => {
      controller.templates = [
        { path: "article-draft.md", name: "article-draft", directory: "" }
      ]

      controller.selectTemplate({
        currentTarget: {
          dataset: { templatePath: "article-draft.md" }
        }
      })

      expect(controller.templateDialogTarget.close).toHaveBeenCalled()
      expect(controller.newItemDialogTarget.showModal).toHaveBeenCalled()
      expect(controller.newItemInputTarget.value).toBe("article-draft")
    })
  })

  describe("template manager", () => {
    it("opens the template manager dialog and loads templates", async () => {
      controller.templateDialogTarget.open = true

      await controller.openTemplateManager()

      expect(controller.templateManagerDialogTarget.showModal).toHaveBeenCalled()
      expect(controller.templateManagerListTarget.innerHTML).toContain("dialogs.templates.built_ins.article_draft.name")
    })

    it("keeps the new-template form when an earlier refresh resolves late", async () => {
      let resolveTemplates
      global.fetch = vi.fn(() => new Promise((resolve) => {
        resolveTemplates = resolve
      }))

      const openPromise = controller.openTemplateManager()
      controller.newTemplate()

      resolveTemplates({
        ok: true,
        headers: { get: () => "application/json" },
        json: () => Promise.resolve([
          { path: "article-draft.md", name: "article-draft", directory: "" }
        ]),
        text: () => Promise.resolve("[]")
      })

      await openPromise

      expect(controller.currentTemplatePath).toBeNull()
      expect(controller.templateFormTitleTarget.textContent).toBe("dialogs.templates.new_title")
      expect(controller.templatePathInputTarget.readOnly).toBe(false)
    })

    it("prepares a blank form for a new template", () => {
      controller.newTemplate()

      expect(controller.currentTemplatePath).toBeNull()
      expect(controller.templatePathInputTarget.readOnly).toBe(false)
      expect(controller.templateDeleteButtonTarget.classList.contains("hidden")).toBe(true)
    })

    it("loads a template for editing", async () => {
      await controller.loadTemplateForEditing("team/retro.md")

      expect(controller.currentTemplatePath).toBe("team/retro.md")
      expect(controller.templatePathInputTarget.value).toBe("team/retro.md")
      expect(controller.templatePathInputTarget.readOnly).toBe(true)
      expect(controller.templateContentInputTarget.value).toContain("## Wins")
      expect(controller.templateDeleteButtonTarget.classList.contains("hidden")).toBe(false)
    })

    it("saves a new template via the templates API", async () => {
      controller.newTemplate()
      controller.templatePathInputTarget.value = "team/retro"
      controller.templateContentInputTarget.value = "# Retro"

      await controller.submitTemplateSave()

      expect(global.fetch).toHaveBeenCalledWith("/templates", expect.objectContaining({
        method: "POST",
        body: expect.stringContaining('"path":"team/retro"')
      }))
    })

    it("shows success feedback after saving a template", async () => {
      controller.newTemplate()
      controller.templatePathInputTarget.value = "team/retro"
      controller.templateContentInputTarget.value = "# Retro"

      await controller.submitTemplateSave()

      expect(controller.templateManagerNoticeTarget.textContent).toBe("success.template_saved")
      expect(controller.templateManagerNoticeTarget.classList.contains("hidden")).toBe(false)
    })

    it("updates an existing template via the templates API", async () => {
      controller.currentTemplatePath = "team/retro.md"
      controller.templatePathInputTarget.value = "team/retro.md"
      controller.templateContentInputTarget.value = "# Updated"

      await controller.submitTemplateSave()

      expect(global.fetch).toHaveBeenCalledWith("/templates/team/retro.md", expect.objectContaining({
        method: "PATCH",
        body: expect.stringContaining('"content":"# Updated"')
      }))
    })

    it("deletes an existing template", async () => {
      controller.currentTemplatePath = "team/retro.md"

      await controller.deleteTemplate()

      expect(global.fetch).toHaveBeenCalledWith("/templates/team/retro.md", expect.objectContaining({
        method: "DELETE"
      }))
    })

    it("shows success feedback after deleting a template", async () => {
      controller.currentTemplatePath = "team/retro.md"

      await controller.deleteTemplate()

      expect(controller.templateManagerNoticeTarget.textContent).toBe("success.template_deleted")
      expect(controller.templateManagerNoticeTarget.classList.contains("hidden")).toBe(false)
    })
  })

  describe("save current note as template", () => {
    it("opens the save dialog with the default template path for an unlinked note", async () => {
      await controller.openSaveTemplateFromNoteDialog("test.md")

      expect(global.fetch).toHaveBeenCalledWith("/templates/status/test.md", expect.any(Object))
      expect(controller.saveTemplateDialogTarget.showModal).toHaveBeenCalled()
      expect(controller.saveTemplateTitleTarget.textContent).toBe("dialogs.templates.save_from_note_title")
      expect(controller.saveTemplateNotePathTarget.textContent).toBe("test.md")
      expect(controller.saveTemplateInputTarget.value).toBe("test")
    })

    it("uses the linked template path when the note already has one", async () => {
      await controller.openSaveTemplateFromNoteDialog("linked.md")

      expect(controller.saveTemplateTitleTarget.textContent).toBe("dialogs.templates.save_from_note_update_title")
      expect(controller.saveTemplateInputTarget.value).toBe("templates/linked")
    })

    it("submits the note save request and closes the dialog", async () => {
      controller.currentTemplateSourceNotePath = "test.md"
      controller.saveTemplateInputTarget.value = "saved-template"

      await controller.submitSaveTemplateFromNote()

      expect(global.fetch).toHaveBeenCalledWith("/templates/save_from_note", expect.objectContaining({
        method: "POST",
        body: expect.stringContaining('"note_path":"test.md"')
      }))
      expect(global.fetch).toHaveBeenCalledWith("/templates/save_from_note", expect.objectContaining({
        method: "POST",
        body: expect.stringContaining('"template_path":"saved-template"')
      }))
      expect(controller.saveTemplateDialogTarget.close).toHaveBeenCalled()
      expect(controller.currentTemplateSourceNotePath).toBeNull()
      expect(controller.currentTemplateLinkedPath).toBeNull()
    })

    it("deletes a linked template from the note context action", async () => {
      await controller.deleteTemplateForNote("linked.md")

      expect(global.fetch).toHaveBeenCalledWith("/templates/save_from_note", expect.objectContaining({
        method: "DELETE",
        body: expect.stringContaining('"note_path":"linked.md"')
      }))
      expect(controller.contextItemTemplateLinked).toBe(false)
      expect(controller.contextItemTemplatePath).toBeNull()
    })
  })

  describe("closeNewItemDialog()", () => {
    it("closes the new item dialog", () => {
      controller.openNewItemDialog("note", "")
      controller.closeNewItemDialog()

      expect(controller.newItemDialogTarget.close).toHaveBeenCalled()
    })

    it("resets state", () => {
      controller.newItemType = "note"
      controller.newItemParent = "parent"

      controller.closeNewItemDialog()

      expect(controller.newItemType).toBeNull()
      expect(controller.newItemParent).toBe("")
    })
  })

  describe("submitNewItem()", () => {
    it("does nothing with empty input", async () => {
      controller.openNewItemDialog("note", "")
      controller.newItemInputTarget.value = ""

      await controller.submitNewItem()

      expect(global.fetch).not.toHaveBeenCalled()
    })

    it("creates note via API", async () => {
      controller.openNewItemDialog("note", "", "empty")
      controller.newItemInputTarget.value = "test"

      await controller.submitNewItem()

      expect(global.fetch).toHaveBeenCalledWith("/notes/test.md", expect.objectContaining({
        method: "POST"
      }))
    })

    it("creates template-based note via API", async () => {
      controller.openNewItemDialog("note", "", "team/retro.md")
      controller.newItemInputTarget.value = "retro"

      await controller.submitNewItem()

      expect(global.fetch).toHaveBeenCalledWith("/notes/retro.md", expect.objectContaining({
        method: "POST",
        body: expect.stringContaining('"template_path":"team/retro.md"')
      }))
    })

    it("creates folder via API", async () => {
      controller.openNewItemDialog("folder", "")
      controller.newItemInputTarget.value = "newfolder"

      await controller.submitNewItem()

      expect(global.fetch).toHaveBeenCalledWith(
        expect.stringContaining("/folders/newfolder"),
        expect.objectContaining({ method: "POST" })
      )
    })

    it("dispatches file-created event", async () => {
      const handler = vi.fn()
      element.addEventListener("file-operations:file-created", handler)

      controller.openNewItemDialog("note", "", "empty")
      controller.newItemInputTarget.value = "test"

      await controller.submitNewItem()

      expect(handler).toHaveBeenCalled()
    })

    it("dispatches folder-created event", async () => {
      const handler = vi.fn()
      element.addEventListener("file-operations:folder-created", handler)

      controller.openNewItemDialog("folder", "")
      controller.newItemInputTarget.value = "newfolder"

      await controller.submitNewItem()

      expect(handler).toHaveBeenCalled()
    })
  })

  describe("humanizeTemplateName()", () => {
    it("preserves accented words without uppercasing trailing letters", () => {
      expect(controller.humanizeTemplateName("reunião wise up")).toBe("Reunião Wise Up")
    })
  })

  describe("renameItem()", () => {
    it("hides context menu", () => {
      controller.contextItem = { path: "test.md", type: "file" }
      controller.renameItem()

      expect(controller.contextMenuTarget.classList.contains("hidden")).toBe(true)
    })

    it("shows rename dialog", () => {
      controller.contextItem = { path: "test.md", type: "file" }
      controller.renameItem()

      expect(controller.renameDialogTarget.showModal).toHaveBeenCalled()
    })

    it("populates input with file name without extension", () => {
      controller.contextItem = { path: "folder/myfile.md", type: "file" }
      controller.renameItem()

      expect(controller.renameInputTarget.value).toBe("myfile")
    })

    it("populates input with folder name", () => {
      controller.contextItem = { path: "parent/myfolder", type: "folder" }
      controller.renameItem()

      expect(controller.renameInputTarget.value).toBe("myfolder")
    })
  })

  describe("closeRenameDialog()", () => {
    it("closes the rename dialog", () => {
      controller.contextItem = { path: "test.md", type: "file" }
      controller.renameItem()
      controller.closeRenameDialog()

      expect(controller.renameDialogTarget.close).toHaveBeenCalled()
    })
  })

  describe("submitRename()", () => {
    it("does nothing with empty input", async () => {
      controller.contextItem = { path: "test.md", type: "file" }
      controller.renameInputTarget.value = ""

      await controller.submitRename()

      expect(global.fetch).not.toHaveBeenCalled()
    })

    it("adds .md extension for files", async () => {
      controller.contextItem = { path: "test.md", type: "file" }
      controller.renameInputTarget.value = "newname"

      await controller.submitRename()

      expect(global.fetch).toHaveBeenCalledWith(
        expect.stringContaining("/notes/"),
        expect.objectContaining({
          body: expect.stringContaining("newname.md")
        })
      )
    })

    it("dispatches file-renamed event", async () => {
      const handler = vi.fn()
      element.addEventListener("file-operations:file-renamed", handler)

      controller.contextItem = { path: "old.md", type: "file" }
      controller.renameInputTarget.value = "new"

      await controller.submitRename()

      expect(handler).toHaveBeenCalled()
      const detail = handler.mock.calls[0][0].detail
      expect(detail.oldPath).toBe("old.md")
      expect(detail.newPath).toBe("new.md")
    })

    it("closes dialog after successful rename", async () => {
      controller.contextItem = { path: "test.md", type: "file" }
      controller.renameInputTarget.value = "newname"

      await controller.submitRename()

      expect(controller.renameDialogTarget.close).toHaveBeenCalled()
    })
  })

  describe("deleteItem()", () => {
    it("hides context menu", async () => {
      controller.contextItem = { path: "test.md", type: "file" }
      await controller.deleteItem()

      expect(controller.contextMenuTarget.classList.contains("hidden")).toBe(true)
    })

    it("shows confirmation dialog", async () => {
      controller.contextItem = { path: "test.md", type: "file" }
      await controller.deleteItem()

      expect(global.confirm).toHaveBeenCalled()
    })

    it("does not delete if confirmation cancelled", async () => {
      global.confirm = vi.fn().mockReturnValue(false)
      controller.contextItem = { path: "test.md", type: "file" }

      await controller.deleteItem()

      expect(global.fetch).not.toHaveBeenCalled()
    })

    it("calls delete API", async () => {
      controller.contextItem = { path: "test.md", type: "file" }

      await controller.deleteItem()

      expect(global.fetch).toHaveBeenCalledWith(
        expect.stringContaining("/notes/"),
        expect.objectContaining({ method: "DELETE" })
      )
    })

    it("dispatches file-deleted event", async () => {
      const handler = vi.fn()
      element.addEventListener("file-operations:file-deleted", handler)

      controller.contextItem = { path: "test.md", type: "file" }

      await controller.deleteItem()

      expect(handler).toHaveBeenCalled()
      expect(handler.mock.calls[0][0].detail.path).toBe("test.md")
    })
  })

  describe("onRenameKeydown()", () => {
    it("submits on Enter", () => {
      const submitSpy = vi.spyOn(controller, "submitRename")
      const event = { key: "Enter", preventDefault: vi.fn() }

      controller.onRenameKeydown(event)

      expect(event.preventDefault).toHaveBeenCalled()
      expect(submitSpy).toHaveBeenCalled()
    })

    it("closes on Escape", () => {
      const closeSpy = vi.spyOn(controller, "closeRenameDialog")
      const event = { key: "Escape", preventDefault: vi.fn() }

      controller.onRenameKeydown(event)

      expect(closeSpy).toHaveBeenCalled()
    })
  })

  describe("onNewItemKeydown()", () => {
    it("submits on Enter", () => {
      const submitSpy = vi.spyOn(controller, "submitNewItem")
      const event = { key: "Enter", preventDefault: vi.fn() }

      controller.onNewItemKeydown(event)

      expect(event.preventDefault).toHaveBeenCalled()
      expect(submitSpy).toHaveBeenCalled()
    })

    it("closes on Escape", () => {
      const closeSpy = vi.spyOn(controller, "closeNewItemDialog")
      const event = { key: "Escape", preventDefault: vi.fn() }

      controller.onNewItemKeydown(event)

      expect(closeSpy).toHaveBeenCalled()
    })
  })
})
