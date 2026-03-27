/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
vi.mock("@rails/request.js", async () => await import("../mocks/requestjs.js"))

import { Application } from "@hotwired/stimulus"
import { setupJsdomGlobals } from "../helpers/jsdom_globals.js"
import ShareManagementController from "../../../app/javascript/controllers/share_management_controller.js"

describe("ShareManagementController", () => {
  let application
  let controller
  let element
  let appController

  beforeEach(async () => {
    setupJsdomGlobals()

    window.t = vi.fn((key) => {
      const translations = {
        "share_management.loading": "Loading Share API settings...",
        "share_management.ready": "Ready",
        "share_management.settings_saved": "Share API settings saved.",
        "share_management.recheck_complete": "Share API status refreshed.",
        "share_management.recheck_failed": "Couldn't refresh Share API status.",
        "share_management.delete_failed": "Couldn't delete the published remote shares.",
        "share_management.bulk_delete_success": "Deleted shared notes.",
        "share_management.secret_configured": "Configured",
        "share_management.secret_not_configured": "Not configured",
        "share_management.status.backend": "Backend",
        "share_management.status.public_base": "Public base",
        "share_management.status.reachable": "Reachable",
        "share_management.status.admin": "Admin features",
        "share_management.status.share_count": "Published shares",
        "share_management.status.storage_writable": "Storage writable",
        "share_management.status.capabilities": "Capabilities",
        "share_management.status.message": "Message",
        "share_management.yes": "Yes",
        "share_management.no": "No",
        "confirm.delete_all_shared_notes": "Delete all published remote shares?",
        "status.share_failed": "Share failed",
        "errors.failed_to_save": "Failed to save"
      }

      return translations[key] || key
    })

    document.body.innerHTML = `
      <div data-controller="app"></div>
      <div data-controller="share-management">
        <dialog data-share-management-target="dialog"></dialog>
        <form data-share-management-target="form">
          <select name="share_backend" data-action="change->share-management#onBackendChanged">
            <option value="local">local</option>
            <option value="remote">remote</option>
          </select>
          <select name="share_remote_api_scheme">
            <option value="https">https</option>
          </select>
          <input name="share_remote_api_host" type="text">
          <input name="share_remote_api_port" type="number">
          <input name="share_remote_public_base" type="url">
          <input name="share_remote_timeout_seconds" type="number">
          <input name="share_remote_expiration_days" type="number">
          <input name="share_remote_verify_tls" type="checkbox">
          <input name="share_remote_upload_assets" type="checkbox">
          <input name="share_remote_instance_name" type="text">
          <input name="share_remote_healthchecks_ping_url" type="url">
          <input name="share_remote_alert_webhook_url" type="url">
          <input name="share_remote_api_token" type="password" data-secret-setting="true">
          <input name="share_remote_signing_secret" type="password" data-secret-setting="true">
          <input name="share_remote_alert_webhook_secret" type="password" data-secret-setting="true">
        </form>
        <div data-share-management-target="statusPanel"></div>
        <p data-share-management-target="feedback"></p>
        <button data-share-management-target="saveButton"></button>
        <button data-share-management-target="recheckButton"></button>
        <button data-share-management-target="deleteButton"></button>
      </div>
    `

    HTMLDialogElement.prototype.showModal = vi.fn(function () {
      this.open = true
    })
    HTMLDialogElement.prototype.close = vi.fn(function () {
      this.open = false
    })

    appController = {
      showTemporaryMessage: vi.fn()
    }

    element = document.querySelector('[data-controller="share-management"]')
    application = Application.start()
    application.register("share-management", ShareManagementController)

    await new Promise((resolve) => setTimeout(resolve, 0))
    controller = application.getControllerForElementAndIdentifier(element, "share-management")
    controller.getAppController = vi.fn(() => appController)
    window.confirm = vi.fn(() => true)
  })

  afterEach(() => {
    application.stop()
    vi.restoreAllMocks()
  })

  function response(json, ok = true, status = 200) {
    return {
      ok,
      status,
      json: () => Promise.resolve(json)
    }
  }

  function payload(overrides = {}) {
    return {
      settings: {
        share_backend: "remote",
        share_remote_api_scheme: "https",
        share_remote_api_host: "shares.example.com",
        share_remote_api_port: 443,
        share_remote_public_base: "https://shares.example.com",
        share_remote_timeout_seconds: 10,
        share_remote_verify_tls: true,
        share_remote_upload_assets: true,
        share_remote_instance_name: "my-vps",
        share_remote_expiration_days: 30,
        share_remote_healthchecks_ping_url: "",
        share_remote_alert_webhook_url: "",
        share_remote_api_token_configured: true,
        share_remote_signing_secret_configured: true,
        share_remote_alert_webhook_secret_configured: false
      },
      status: {
        backend: "remote",
        public_base: "https://shares.example.com",
        reachable: true,
        admin_enabled: true,
        remote_share_count: 4,
        storage_writable: true,
        capabilities: {
          admin_status: true,
          admin_bulk_delete: true
        },
        message: "Remote share API is reachable."
      },
      ...overrides
    }
  }

  it("opens the modal and loads sanitized settings and status", async () => {
    global.fetch = vi.fn().mockResolvedValueOnce(response(payload()))

    await controller.open()

    expect(controller.dialogTarget.showModal).toHaveBeenCalled()
    expect(controller.formTarget.elements.share_backend.value).toBe("remote")
    expect(controller.formTarget.elements.share_remote_api_host.value).toBe("shares.example.com")
    expect(controller.formTarget.elements.share_remote_api_token.placeholder).toBe("Configured")
    expect(controller.statusPanelTarget.textContent).toContain("Published shares")
    expect(controller.statusPanelTarget.textContent).toContain("4")
  })

  it("saves updated settings through the local admin proxy", async () => {
    global.fetch = vi.fn()
      .mockResolvedValueOnce(response(payload()))
      .mockResolvedValueOnce(response(payload({
        settings: {
          ...payload().settings,
          share_remote_api_host: "relay.example.com"
        },
        message: "Share API settings saved."
      })))

    await controller.open()
    controller.formTarget.elements.share_remote_api_host.value = "relay.example.com"

    await controller.save()

    expect(global.fetch).toHaveBeenCalledWith("/shares/admin", expect.objectContaining({
      method: "PATCH"
    }))
    const requestBody = JSON.parse(global.fetch.mock.calls[1][1].body)
    expect(requestBody.share_remote_api_host).toBe("relay.example.com")
    expect(appController.showTemporaryMessage).toHaveBeenCalledWith("Share API settings saved.", 3500, false)
  })

  it("rechecks remote status through the local admin proxy", async () => {
    global.fetch = vi.fn()
      .mockResolvedValueOnce(response(payload()))
      .mockResolvedValueOnce(response(payload({
        status: {
          ...payload().status,
          remote_share_count: 2
        },
        message: "Share API status refreshed."
      })))

    await controller.open()
    await controller.recheck()

    expect(global.fetch).toHaveBeenCalledWith("/shares/admin/recheck", expect.objectContaining({
      method: "POST"
    }))
    expect(controller.statusPanelTarget.textContent).toContain("2")
  })

  it("confirms before deleting all shared notes and dispatches the cleared event", async () => {
    const clearedSpy = vi.fn()
    element.addEventListener("share-management:shares-cleared", clearedSpy)
    global.fetch = vi.fn()
      .mockResolvedValueOnce(response(payload()))
      .mockResolvedValueOnce(response(payload({
        status: {
          ...payload().status,
          remote_share_count: 0
        },
        deleted: true,
        deleted_count: 4,
        message: "Deleted shared notes."
      })))

    await controller.open()
    await controller.deleteAllShares()

    expect(window.confirm).toHaveBeenCalled()
    expect(global.fetch).toHaveBeenCalledWith("/shares/admin", expect.objectContaining({
      method: "DELETE"
    }))
    expect(clearedSpy).toHaveBeenCalledTimes(1)
    expect(clearedSpy.mock.calls[0][0].detail).toEqual({ deleted: true, deletedCount: 4 })
    expect(controller.statusPanelTarget.textContent).toContain("0")
  })

  it("disables remote-only actions when local sharing is selected", async () => {
    global.fetch = vi.fn().mockResolvedValueOnce(response(payload({
      settings: {
        ...payload().settings,
        share_backend: "local"
      },
      status: {
        backend: "local",
        public_base: "",
        reachable: null,
        admin_enabled: false,
        remote_share_count: null,
        storage_writable: null,
        capabilities: {},
        message: "Local sharing stores snapshots on this machine."
      }
    })))

    await controller.open()

    expect(controller.recheckButtonTarget.disabled).toBe(true)
    expect(controller.deleteButtonTarget.disabled).toBe(true)
  })
})
