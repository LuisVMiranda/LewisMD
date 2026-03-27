# frozen_string_literal: true

require "test_helper"

class NoteShareIdentityServiceTest < ActiveSupport::TestCase
  def setup
    setup_test_notes_dir
    @service = NoteShareIdentityService.new(base_path: @test_notes_dir)
  end

  def teardown
    teardown_test_notes_dir
  end

  test "ensure_identity adds yaml frontmatter to notes without frontmatter" do
    create_test_note("plain.md", "# Plain Note\n\nBody")

    result = @service.ensure_identity!("plain.md")
    content = File.read(@test_notes_dir.join("plain.md"))

    assert_equal true, result[:updated]
    assert_match(/\A---\nlewismd_note_id: [0-9a-f\-]{36}\n---\n# Plain Note/m, content)
    assert_equal result[:note_identifier], @service.identity_for("plain.md")
  end

  test "ensure_identity appends the identifier to existing yaml frontmatter" do
    create_test_note("yaml.md", <<~MARKDOWN)
      ---
      title: "Example"
      tags:
        - test
      ---
      # Heading
    MARKDOWN

    result = @service.ensure_identity!("yaml.md")
    content = File.read(@test_notes_dir.join("yaml.md"))

    assert_equal true, result[:updated]
    assert_includes content, "title: \"Example\""
    assert_includes content, "lewismd_note_id: #{result[:note_identifier]}"
    assert_match(/\A---\n.*\n---\n# Heading/m, content)
  end

  test "ensure_identity appends the identifier to existing toml frontmatter" do
    create_test_note("toml.md", <<~MARKDOWN)
      +++
      title = "Example"
      draft = true
      +++
      # Heading
    MARKDOWN

    result = @service.ensure_identity!("toml.md")
    content = File.read(@test_notes_dir.join("toml.md"))

    assert_equal true, result[:updated]
    assert_includes content, %(title = "Example")
    assert_includes content, %(lewismd_note_id = "#{result[:note_identifier]}")
    assert_match(/\A\+\+\+\n.*\n\+\+\+\n# Heading/m, content)
  end

  test "ensure_identity reuses an existing unique identifier without rewriting the note" do
    existing_identifier = SecureRandom.uuid
    create_test_note("existing.md", <<~MARKDOWN)
      ---
      lewismd_note_id: #{existing_identifier}
      ---
      # Heading
    MARKDOWN

    original_content = File.read(@test_notes_dir.join("existing.md"))
    result = @service.ensure_identity!("existing.md")

    assert_equal false, result[:updated]
    assert_equal existing_identifier, result[:note_identifier]
    assert_nil result[:content]
    assert_equal original_content, File.read(@test_notes_dir.join("existing.md"))
  end

  test "ensure_identity regenerates duplicated identifiers for copied notes" do
    source = create_test_note("source.md", "# Source")
    original = @service.ensure_identity!("source.md")
    create_test_note("copy.md", File.read(source))

    duplicate = @service.ensure_identity!("copy.md")

    refute_equal original[:note_identifier], duplicate[:note_identifier]
    assert_equal original[:note_identifier], @service.identity_for("source.md")
    assert_equal duplicate[:note_identifier], @service.identity_for("copy.md")
  end

  test "ensure_identity raises a share error when yaml frontmatter is malformed" do
    create_test_note("broken.md", <<~MARKDOWN)
      ---
      title: "Broken"
      # Heading
    MARKDOWN

    error = assert_raises(ShareService::InvalidShareError) do
      @service.ensure_identity!("broken.md")
    end

    assert_includes error.message, I18n.t("errors.share_identity_frontmatter_invalid")
  end
end
