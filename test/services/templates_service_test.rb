# frozen_string_literal: true

require "test_helper"

class TemplatesServiceTest < ActiveSupport::TestCase
  def setup
    setup_test_notes_dir
    @service = TemplatesService.new(base_path: @test_notes_dir)
    create_test_note("drafts/weekly.md", "# Weekly\n\nSummary")
  end

  def teardown
    teardown_test_notes_dir
  end

  test "uses hidden templates directory inside notes path by default" do
    assert_equal @test_notes_dir.join(".frankmd/templates"), @service.base_path
    assert @service.base_path.directory?
  end

  test "seeds built-in templates on first initialization" do
    templates = @service.list

    assert_includes templates.map { |template| template[:path] }, "daily-note.md"
    assert_includes templates.map { |template| template[:path] }, "meeting-note.md"
    assert_includes templates.map { |template| template[:path] }, "article-draft.md"
    assert_includes templates.map { |template| template[:path] }, "journal-entry.md"
    assert_includes templates.map { |template| template[:path] }, "changelog.md"
  end

  test "does not overwrite existing seeded templates" do
    custom_content = "# Daily Note\n\nCustomized"
    @service.write("daily-note.md", custom_content)

    seeded_again = TemplatesService.new(base_path: @test_notes_dir)

    assert_equal custom_content, seeded_again.read("daily-note.md")
  end

  test "lists user-added markdown templates recursively" do
    @service.write("team/retro.md", "# Retro")

    template = @service.list.find { |entry| entry[:path] == "team/retro.md" }

    assert_not_nil template
    assert_equal "retro", template[:name]
    assert_equal "team", template[:directory]
  end

  test "ignores hidden and non-markdown files in list" do
    FileUtils.mkdir_p(@service.base_path.join(".hidden"))
    File.write(@service.base_path.join(".hidden/secret.md"), "# Hidden")
    File.write(@service.base_path.join("notes.txt"), "Not markdown")

    paths = @service.list.map { |entry| entry[:path] }

    refute_includes paths, ".hidden/secret.md"
    refute_includes paths, "notes.txt"
  end

  test "list skips templates that disappear during refresh" do
    missing_path = @service.base_path.join("missing.md")
    @service.stubs(:template_files).returns([ missing_path ])

    assert_equal [], @service.list
  end

  test "write creates markdown file when extension is omitted" do
    @service.write("scratch/template", "# Scratch")

    assert @service.exists?("scratch/template.md")
    assert_equal "# Scratch", @service.read("scratch/template")
  end

  test "delete removes template file" do
    @service.write("obsolete.md", "# Old")

    @service.delete("obsolete")

    refute @service.exists?("obsolete.md")
  end

  test "read raises not found when a template disappears during access" do
    path = @service.base_path.join("vanishing.md")
    path.stubs(:file?).returns(true)
    path.stubs(:read).raises(Errno::ENOENT)
    @service.stubs(:safe_path).returns(path)

    assert_raises(TemplatesService::NotFoundError) do
      @service.read("vanishing.md")
    end
  end

  test "prevents path traversal" do
    assert_raises(TemplatesService::InvalidPathError) do
      @service.read("../outside.md")
    end
  end

  test "respects configured templates path override" do
    custom_templates_path = @test_notes_dir.join("shared-templates")
    config = Config.new(base_path: @test_notes_dir)
    config.set(:templates_path, custom_templates_path.to_s)

    service = TemplatesService.new(base_path: @test_notes_dir)

    assert_equal custom_templates_path, service.base_path
    assert service.base_path.directory?
    assert_includes service.list.map { |template| template[:path] }, "daily-note.md"
  end

  test "save_from_note writes template content and links the note" do
    saved_path = @service.save_from_note(note_path: "drafts/weekly.md", template_path: "saved/weekly-template")

    assert_equal "saved/weekly-template.md", saved_path
    assert_equal "# Weekly\n\nSummary", @service.read("saved/weekly-template.md")
    assert_equal "saved/weekly-template.md", @service.linked_template_path_for("drafts/weekly.md")
  end

  test "delete_for_note removes linked template and clears the note link" do
    @service.save_from_note(note_path: "drafts/weekly.md", template_path: "saved/weekly-template")

    deleted_path = @service.delete_for_note("drafts/weekly.md")

    assert_equal "saved/weekly-template.md", deleted_path
    refute @service.exists?("saved/weekly-template.md")
    refute @service.template_linked?("drafts/weekly.md")
  end

  test "move_note_link preserves linked template when a note is renamed" do
    @service.save_from_note(note_path: "drafts/weekly.md", template_path: "saved/weekly-template")

    @service.move_note_link("drafts/weekly.md", "drafts/archive.md")

    refute @service.template_linked?("drafts/weekly.md")
    assert_equal "saved/weekly-template.md", @service.linked_template_path_for("drafts/archive.md")
  end
end
