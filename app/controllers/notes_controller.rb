# frozen_string_literal: true

class NotesController < ApplicationController
  before_action :set_note, only: [ :update, :destroy, :rename ]

  def index
    @tree = Note.all
    @initial_path = params[:file]
    @initial_note = load_initial_note if @initial_path.present?
    @config_obj = Config.new
    @config = load_config
    @expanded_folders = Set.new
    @selected_file = @initial_path || ""
  end

  def tree
    @tree = Note.all
    @expanded_folders = params[:expanded].to_s.split(",").to_set
    @selected_file = params[:selected].to_s
    render partial: "notes/file_tree", layout: false
  end

  def show
    path = Note.normalize_path(params[:path])

    # JSON API request - check Accept header since .md extension confuses format detection
    if json_request?
      begin
        note = Note.find(path)
        render json: { path: note.path, content: note.content }
      rescue NotesService::NotFoundError
        render json: { error: t("errors.note_not_found") }, status: :not_found
      end
      return
    end

    # HTML request - render SPA with file loaded
    @tree = Note.all
    @initial_path = path
    @initial_note = load_initial_note
    @config_obj = Config.new
    @config = load_config
    @expanded_folders = Set.new
    @selected_file = path
    render :index, formats: [ :html ]
  end

  def create
    # Hugo blog post template - server generates path and content
    if params[:template] == "hugo"
      title = params[:title].to_s
      parent = params[:parent].presence

      if title.blank?
        render json: { error: t("errors.title_required") }, status: :unprocessable_entity
        return
      end

      hugo_post = HugoService.generate_blog_post(title, parent: parent)
      @note = Note.new(path: hugo_post[:path], content: hugo_post[:content])
    else
      path = Note.normalize_path(params[:path])
      content = note_content_for_create
      return if performed?

      @note = Note.new(path: path, content: content)
    end

    if @note.exists?
      render json: { error: t("errors.note_already_exists") }, status: :unprocessable_entity
      return
    end

    if @note.save
      respond_to do |format|
        format.turbo_stream {
          load_tree_for_turbo_stream(selected: @note.path)
          response.headers["X-Created-Path"] = @note.path
          render status: :created
        }
        format.any { render json: { path: @note.path, message: t("success.note_created") }, status: :created }
      end
    else
      render json: { error: @note.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def update
    @note.content = params[:content] || ""

    if @note.save
      render json: { path: @note.path, message: t("success.note_saved") }
    else
      render json: { error: @note.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def destroy
    if @note.destroy
      TemplatesService.new.unlink_note(@note.path)
      respond_to do |format|
        format.turbo_stream { load_tree_for_turbo_stream }
        format.any { render json: { message: t("success.note_deleted") } }
      end
    else
      render json: { error: @note.errors.full_messages.join(", ") }, status: :not_found
    end
  end

  def rename
    unless @note.exists?
      render json: { error: t("errors.note_not_found") }, status: :not_found
      return
    end

    new_path = Note.normalize_path(params[:new_path])
    old_path = @note.path

    if @note.rename(new_path)
      TemplatesService.new.move_note_link(old_path, @note.path)
      respond_to do |format|
        format.turbo_stream { load_tree_for_turbo_stream(selected: @note.path) }
        format.any { render json: { old_path: old_path, new_path: @note.path, message: t("success.note_renamed") } }
      end
    else
      render json: { error: @note.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def search
    query = params[:q].to_s
    results = Note.search(query, context_lines: 3, max_results: 20)

    respond_to do |format|
      format.html { render partial: "notes/search_results", locals: { results: results }, layout: false }
      format.json { render json: results }
    end
  end

  private

  def json_request?
    # Check Accept header since .md extension in URL confuses Rails format detection
    request.headers["Accept"]&.include?("application/json") ||
      request.xhr? ||
      request.format.json?
  end

  def set_note
    path = Note.normalize_path(params[:path])
    @note = Note.new(path: path)
  end

  def load_tree_for_turbo_stream(selected: nil)
    @tree = Note.all
    @expanded_folders = params[:expanded].to_s.split(",").to_set
    @selected_file = selected || params[:selected].to_s
  end

  def load_initial_note
    return nil unless @initial_path.present?

    path = Note.normalize_path(@initial_path)
    note = Note.new(path: path)

    if note.exists?
      {
        path: note.path,
        content: note.read,
        exists: true
      }
    else
      {
        path: path,
        content: nil,
        exists: false,
        error: t("errors.file_not_found")
      }
    end
  rescue NotesService::NotFoundError
    {
      path: path,
      content: nil,
      exists: false,
      error: t("errors.file_not_found")
    }
  end

  def load_config
    config = Config.new
    {
      settings: config.ui_settings,
      features: {
        s3_upload: config.feature_available?(:s3_upload),
        youtube_search: config.feature_available?(:youtube_search),
        google_search: config.feature_available?(:google_search),
        local_images: config.feature_available?(:local_images)
      }
    }
  rescue => e
    Rails.logger.error("Failed to load config: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    { settings: {}, features: {} }
  end

  def note_content_for_create
    return params[:content] || "" if params[:template_path].blank?

    TemplatesService.new.read(params[:template_path])
  rescue TemplatesService::NotFoundError
    render json: { error: t("errors.file_not_found") }, status: :not_found
    nil
  rescue TemplatesService::InvalidPathError => e
    render json: { error: e.message }, status: :unprocessable_entity
    nil
  end
end
