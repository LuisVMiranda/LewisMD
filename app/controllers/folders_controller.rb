# frozen_string_literal: true

class FoldersController < ApplicationController
  include ExpandedFoldersParam

  before_action :set_folder, only: [ :destroy, :rename ]

  def create
    @folder = Folder.new(path: params[:path].to_s)

    if @folder.exists?
      render json: { error: t("errors.folder_already_exists") }, status: :unprocessable_entity
      return
    end

    if @folder.create
      respond_to do |format|
        format.turbo_stream {
          load_tree_for_turbo_stream
          render status: :created
        }
        format.any { render json: { path: @folder.path, message: t("success.folder_created") }, status: :created }
      end
    else
      render json: { error: @folder.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def destroy
    if @folder.destroy
      respond_to do |format|
        format.turbo_stream { load_tree_for_turbo_stream }
        format.any { render json: { message: t("success.folder_deleted") } }
      end
    else
      error_message = @folder.errors.full_messages.join(", ")
      status = error_message.include?("not found") ? :not_found : :unprocessable_entity
      render json: { error: error_message }, status: status
    end
  end

  def rename
    old_path = @folder.path
    new_path = params[:new_path].to_s

    if @folder.rename(new_path)
      respond_to do |format|
        format.turbo_stream { load_tree_for_turbo_stream(selected: @folder.path, remap_from: old_path, remap_to: @folder.path) }
        format.any { render json: { old_path: old_path, new_path: @folder.path, message: t("success.folder_renamed") } }
      end
    else
      error_message = @folder.errors.full_messages.join(", ")
      status = error_message.include?("not found") ? :not_found : :unprocessable_entity
      render json: { error: error_message }, status: status
    end
  end

  private

  def set_folder
    @folder = Folder.new(path: params[:path].to_s)
  end

  def load_tree_for_turbo_stream(selected: nil, remap_from: nil, remap_to: nil)
    @tree = Note.all
    @expanded_folders = parse_expanded_folders_param(params[:expanded])
    if remap_from && remap_to
      @expanded_folders = @expanded_folders.map { |path|
        if path == remap_from || path.start_with?("#{remap_from}/")
          "#{remap_to}#{path.delete_prefix(remap_from)}"
        else
          path
        end
      }.to_set
    end
    @selected_file = selected || params[:selected].to_s
  end
end
