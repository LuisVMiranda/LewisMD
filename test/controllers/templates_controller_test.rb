# frozen_string_literal: true

require "test_helper"

class TemplatesControllerTest < ActionDispatch::IntegrationTest
  def setup
    setup_test_notes_dir
    @service = TemplatesService.new(base_path: @test_notes_dir)
    create_test_note("notes/weekly.md", "# Weekly")
  end

  def teardown
    teardown_test_notes_dir
  end

  test "index returns seeded templates" do
    get "/templates", as: :json
    assert_response :success

    templates = JSON.parse(response.body)
    paths = templates.map { |template| template["path"] }

    assert_includes paths, "daily-note.md"
    assert_includes paths, "meeting-note.md"
    assert_includes paths, "article-draft.md"
  end

  test "show returns template content" do
    @service.write("team/retro", "# Retro")

    get template_file_url(path: "team/retro.md"), as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "team/retro.md", data["path"]
    assert_equal "# Retro", data["content"]
  end

  test "show returns not found for missing template" do
    get template_file_url(path: "missing.md"), as: :json
    assert_response :not_found
  end

  test "create writes template and returns normalized path" do
    post "/templates", params: { path: "team/retro", content: "# Retro" }, as: :json
    assert_response :created

    data = JSON.parse(response.body)
    assert_equal "team/retro.md", data["path"]
    assert_equal "# Retro", @service.read("team/retro.md")
  end

  test "create rejects blank path" do
    post "/templates", params: { path: "", content: "# Blank" }, as: :json
    assert_response :unprocessable_entity
  end

  test "update overwrites template content" do
    @service.write("drafts/article", "# Old")

    patch update_template_file_url(path: "drafts/article.md"), params: { content: "# New" }, as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "drafts/article.md", data["path"]
    assert_equal "# New", @service.read("drafts/article.md")
  end

  test "update renames a template when new_path is provided" do
    @service.write("drafts/article", "# Old")

    patch update_template_file_url(path: "drafts/article.md"),
      params: { content: "# New", new_path: "drafts/article-renamed" },
      as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "drafts/article-renamed.md", data["path"]
    refute @service.exists?("drafts/article.md")
    assert_equal "# New", @service.read("drafts/article-renamed.md")
  end

  test "update returns validation error when target path already exists" do
    @service.write("drafts/article", "# Old")
    @service.write("drafts/existing", "# Existing")

    patch update_template_file_url(path: "drafts/article.md"),
      params: { content: "# New", new_path: "drafts/existing" },
      as: :json
    assert_response :unprocessable_entity

    data = JSON.parse(response.body)
    assert_equal I18n.t("errors.template_already_exists"), data["error"]
  end

  test "destroy removes template file" do
    @service.write("obsolete", "# Old")

    delete destroy_template_file_url(path: "obsolete.md"), as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "obsolete.md", data["path"]
    refute @service.exists?("obsolete.md")
  end

  test "status returns whether a note is linked to a template" do
    @service.save_from_note(note_path: "notes/weekly.md", template_path: "team/weekly-template")

    get template_status_url(path: "notes/weekly.md"), as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal true, data["linked"]
    assert_equal "team/weekly-template.md", data["template_path"]
  end

  test "save_from_note stores a linked template for a note" do
    post "/templates/save_from_note", params: { note_path: "notes/weekly.md", template_path: "team/weekly-template" }, as: :json
    assert_response :created

    data = JSON.parse(response.body)
    assert_equal "notes/weekly.md", data["note_path"]
    assert_equal "team/weekly-template.md", data["path"]
    assert_equal true, data["linked"]
    assert_equal "# Weekly", @service.read("team/weekly-template.md")
  end

  test "destroy_saved_note_template deletes a note-linked template" do
    @service.save_from_note(note_path: "notes/weekly.md", template_path: "team/weekly-template")

    delete "/templates/save_from_note", params: { note_path: "notes/weekly.md" }, as: :json
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal false, data["linked"]
    refute @service.exists?("team/weekly-template.md")
    refute @service.template_linked?("notes/weekly.md")
  end
end
