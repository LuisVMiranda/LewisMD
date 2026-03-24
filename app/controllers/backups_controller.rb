# frozen_string_literal: true

class BackupsController < ApplicationController
  def note
    stream_archive(backup_service.backup_note(params[:path]))
  rescue BackupService::NotFoundError
    render json: { error: t("errors.note_not_found") }, status: :not_found
  rescue BackupService::InvalidPathError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Errno::EACCES, Errno::EPERM
    render json: { error: t("errors.permission_denied") }, status: :forbidden
  end

  def folder
    stream_archive(backup_service.backup_folder(params[:path]))
  rescue BackupService::NotFoundError
    render json: { error: t("errors.folder_not_found") }, status: :not_found
  rescue BackupService::InvalidPathError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Errno::EACCES, Errno::EPERM
    render json: { error: t("errors.permission_denied") }, status: :forbidden
  end

  private

  def backup_service
    @backup_service ||= BackupService.new
  end

  def stream_archive(archive)
    send_data archive.path.binread,
      type: "application/zip",
      filename: archive.filename,
      disposition: "attachment"
  ensure
    if archive
      archive.cleanup!
    end
  end
end
