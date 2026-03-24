# frozen_string_literal: true

class TemplatesController < ApplicationController
  before_action :set_service

  def index
    render json: @service.list
  end

  def status
    note_path = params[:note_path].presence || params[:path].to_s
    template_path = @service.linked_template_path_for(note_path)

    render json: {
      note_path: Note.normalize_path(note_path),
      linked: template_path.present?,
      template_path: template_path
    }
  rescue TemplatesService::InvalidNoteError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def show
    render json: {
      path: template_path,
      content: @service.read(template_path)
    }
  rescue TemplatesService::NotFoundError
    render json: { error: t("errors.file_not_found") }, status: :not_found
  rescue TemplatesService::InvalidPathError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def create
    path = params[:path].to_s

    if path.blank?
      return render json: { error: t("errors.no_file_provided") }, status: :unprocessable_entity
    end

    created_path = @service.write(path, params[:content] || "")

    render json: { path: created_path }, status: :created
  rescue TemplatesService::InvalidPathError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    render json: {
      path: @service.update(
        path: template_path,
        content: params[:content] || "",
        new_path: params[:new_path]
      )
    }
  rescue TemplatesService::NotFoundError
    render json: { error: t("errors.file_not_found") }, status: :not_found
  rescue TemplatesService::ConflictError
    render json: { error: t("errors.template_already_exists") }, status: :unprocessable_entity
  rescue TemplatesService::InvalidPathError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    render json: { path: @service.delete(template_path) }
  rescue TemplatesService::NotFoundError
    render json: { error: t("errors.file_not_found") }, status: :not_found
  rescue TemplatesService::InvalidPathError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def save_from_note
    note_path = params[:note_path].to_s
    saved_path = @service.save_from_note(
      note_path: note_path,
      template_path: params[:template_path]
    )

    render json: {
      note_path: Note.normalize_path(note_path),
      path: saved_path,
      linked: true,
      message: t("success.template_saved")
    }, status: :created
  rescue TemplatesService::InvalidNoteError, TemplatesService::InvalidPathError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue TemplatesService::NotFoundError
    render json: { error: t("errors.file_not_found") }, status: :not_found
  end

  def destroy_saved_note_template
    note_path = params[:note_path].to_s
    deleted_path = @service.delete_for_note(note_path)

    render json: {
      note_path: Note.normalize_path(note_path),
      path: deleted_path,
      linked: false,
      message: t("success.template_deleted")
    }
  rescue TemplatesService::InvalidNoteError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue TemplatesService::NotFoundError
    render json: { error: t("errors.file_not_found") }, status: :not_found
  end

  private

  def set_service
    @service = TemplatesService.new
  end

  def template_path
    params[:path].to_s
  end
end
