# frozen_string_literal: true

class SharesController < ApplicationController
  layout "share", only: [ :show ]

  def lookup
    note = find_existing_markdown_note(params[:path])
    share = share_service.active_share_for(
      note.path,
      note_identifier: note_share_identity_service.identity_for(note)
    )
    return render json: { error: I18n.t("errors.share_not_found", default: "Share not found") }, status: :not_found unless share

    render json: share_response(share)
  rescue NotesService::NotFoundError
    render json: { error: I18n.t("errors.share_not_found", default: "Share not found") }, status: :not_found
  rescue ShareService::InvalidShareError => e
    render_invalid_share_error(e)
  end

  def create
    note = find_existing_markdown_note(params[:path])
    identity_result = note_share_identity_service.ensure_identity!(note)
    share_payload = share_payload_builder.build(
      path: note.path,
      title: share_title(params[:title], note.path),
      document_html: params[:html],
      note_identifier: identity_result[:note_identifier]
    )
    share = share_service.create_or_find(
      path: note.path,
      title: share_payload[:title],
      snapshot_html: params[:html],
      share_payload: share_payload
    )

    render json: share_response(share, identity_result), status: share[:created] ? :created : :ok
  rescue NotesService::NotFoundError
    render json: { error: I18n.t("errors.note_not_found") }, status: :not_found
  rescue ShareService::InvalidShareError => e
    render_invalid_share_error(e)
  end

  def update
    note = find_existing_markdown_note(params[:path])
    identity_result = note_share_identity_service.ensure_identity!(note)
    share_payload = share_payload_builder.build(
      path: note.path,
      title: share_title(params[:title], note.path),
      document_html: params[:html],
      note_identifier: identity_result[:note_identifier]
    )
    share = share_service.refresh(
      path: note.path,
      title: share_payload[:title],
      snapshot_html: params[:html],
      share_payload: share_payload
    )

    render json: share_response(share, identity_result)
  rescue NotesService::NotFoundError
    render json: { error: I18n.t("errors.note_not_found") }, status: :not_found
  rescue ShareService::NotFoundError
    render json: { error: I18n.t("errors.share_not_found", default: "Share not found") }, status: :not_found
  rescue ShareService::InvalidShareError => e
    render_invalid_share_error(e)
  end

  def destroy
    note = find_existing_markdown_note(params[:path])
    note_identifier = note_share_identity_service.identity_for(note)
    share = share_service.revoke(path: note.path, note_identifier: note_identifier)

    render json: {
      path: share[:path],
      revoked: true
    }
  rescue NotesService::NotFoundError
    render json: { error: I18n.t("errors.share_not_found", default: "Share not found") }, status: :not_found
  rescue ShareService::NotFoundError
    render json: { error: I18n.t("errors.share_not_found", default: "Share not found") }, status: :not_found
  rescue ShareService::InvalidShareError => e
    render_invalid_share_error(e)
  end

  def show
    share = share_service.find_by_token(params[:token])
    return head :not_found unless share

    @share = share
    @initial_theme = params[:theme].presence || extract_snapshot_theme(share[:snapshot_file]) || "light"
    @snapshot_url = share_snapshot_content_url(token: share[:token])
  end

  def content
    share = share_service.find_by_token(params[:token])
    return head :not_found unless share

    send_file share[:snapshot_file].to_s, type: "text/html", disposition: "inline"
  end

  private

  def share_service
    @share_service ||= ShareProviderSelector.new.provider
  end

  def normalize_share_path(path)
    Note.normalize_path(path).tap do |normalized_path|
      raise ShareService::InvalidShareError unless normalized_path.end_with?(".md")
    end
  end

  def share_payload_builder
    @share_payload_builder ||= SharePayloadBuilder.new
  end

  def note_share_identity_service
    @note_share_identity_service ||= NoteShareIdentityService.new
  end

  def find_existing_markdown_note(path)
    normalized_path = normalize_share_path(path)
    note = Note.new(path: normalized_path)
    raise NotesService::NotFoundError unless note.exists?

    note
  end

  def share_title(raw_title, path)
    raw_title.to_s.strip.presence || File.basename(path, ".md")
  end

  def share_response(share, identity_result = nil)
    response = {
      token: share[:token],
      path: share[:path],
      title: share[:title],
      url: share[:url].presence || share_snapshot_url(token: share[:token]),
      updated_at: share[:updated_at]
    }

    response[:note_identifier] = identity_result[:note_identifier] if identity_result&.dig(:note_identifier).present?
    response[:note_content] = identity_result[:content] if identity_result&.dig(:updated) && identity_result[:content].present?
    response[:created] = share[:created] if share.key?(:created)
    response[:stale] = share[:stale] if share.key?(:stale)
    response[:last_error] = share[:last_error] if share.key?(:last_error) && share[:last_error].present?
    response[:expires_at] = share[:expires_at] if share.key?(:expires_at) && share[:expires_at].present?
    response
  end

  def extract_snapshot_theme(snapshot_file)
    snapshot_file.read[/<html[^>]*data-theme="([^"]+)"/i, 1]
  rescue StandardError
    nil
  end

  def render_invalid_share_error(error)
    message = error.message.to_s.strip
    message = I18n.t("errors.invalid_share_request", default: "Invalid share request") if message.blank?

    render json: { error: message }, status: :unprocessable_entity
  end
end
