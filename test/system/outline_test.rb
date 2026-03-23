# frozen_string_literal: true

require "application_system_test_case"

class OutlineTest < ApplicationSystemTestCase
  test "outline is populated immediately after loading and refreshing a markdown note" do
    create_test_note("outline_refresh_ready.md", <<~MD)
      # Alpha

      Intro

      ## Beta

      More text
    MD

    visit "/notes/outline_refresh_ready.md"

    assert_selector ".outline-panel:not(.hidden)", wait: 2
    assert_selector "[data-line='1']", text: "Alpha", wait: 2
    assert_selector "[data-line='5']", text: "Beta", wait: 2

    page.refresh

    assert_selector ".outline-panel:not(.hidden)", wait: 2
    assert_selector "[data-line='1']", text: "Alpha", wait: 2
    assert_selector "[data-line='5']", text: "Beta", wait: 2
  end

  test "outline is markdown-only and clicking a heading jumps to that line" do
    create_test_note("outline_navigation.md", <<~MD)
      # Intro

      Body

      ## Section

      More body

      ### Deep Dive

      Closing text
    MD

    visit root_url
    find("[data-path='outline_navigation.md']").click

    assert_selector ".outline-panel:not(.hidden)", wait: 2
    assert_selector "[data-line='1']", text: "Intro"
    assert_selector "[data-line='5']", text: "Section"
    assert_selector "[data-line='9']", text: "Deep Dive"

    find("[data-line='9']").click

    assert_equal 9, editor_cursor_line
    assert_selector "[data-line='9'][data-active='true']", wait: 2
  end

  test "outline updates for unsaved heading changes and hides for config files" do
    create_test_note("outline_live.md", "# First Heading\n\nBody")

    visit root_url
    find("[data-path='outline_live.md']").click

    assert_selector "[data-line='1']", text: "First Heading"
    assert_no_selector "[data-line='5']", text: "Second Heading"

    page.execute_script(<<~JS)
      (function() {
        var el = document.querySelector('[data-controller~="codemirror"]');
        var ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'codemirror');
        ctrl.insertAt(ctrl.getValue().length, "\\n\\n## Second Heading");
      })()
    JS

    assert_selector "[data-line='5']", text: "Second Heading", wait: 2

    find("[data-path='.fed']").click

    assert_selector ".outline-panel.hidden", visible: :all
  end

  test "preview source lines update the active outline heading" do
    create_test_note("outline_preview_scroll.md", <<~MD)
      # Intro

      Alpha
      Beta

      ## Section A

      Gamma
      Delta

      ## Section B

      Epsilon
      Zeta
    MD

    visit root_url
    find("[data-path='outline_preview_scroll.md']").click
    sleep 0.3

    click_app_target("previewToggle")
    assert_no_selector "[data-app-target='previewPanel'].hidden", visible: :all, wait: 2

    page.execute_script(<<~JS)
      (function() {
        var appElement = document.querySelector('[data-controller~="app"]');
        var app = window.Stimulus.getControllerForElementAndIdentifier(appElement, 'app');
        app.onPreviewScrolled({ detail: { sourceLine: 11 } });
      })()
    JS

    assert_selector "[data-line='11'][data-active='true']", wait: 2
  end

  test "dense sidebar keeps the file tree usable on short viewports" do
    18.times do |index|
      create_test_note("outline_density/audit-note-#{format('%02d', index + 1)}.md", "# Audit\n\nBody")
    end

    6.times do |folder_index|
      folder_name = "outline_density/folder-#{format('%02d', folder_index + 1)}"
      create_test_folder(folder_name)

      3.times do |note_index|
        create_test_note("#{folder_name}/nested-note-#{format('%02d', note_index + 1)}.md", "# Nested\n\nContent")
      end
    end

    create_test_note("outline_density/zzz-outline-density.md", dense_outline_content)

    visit root_url
    page.current_window.resize_to(1280, 650)

    find("[data-path='outline_density'][data-type='folder']").click
    6.times do |folder_index|
      find("[data-path='outline_density/folder-#{format('%02d', folder_index + 1)}'][data-type='folder']").click
    end
    find("[data-path='outline_density/zzz-outline-density.md'][data-type='file']").click

    assert_selector ".outline-panel:not(.hidden)", wait: 2
    assert_selector "[data-path='outline_density/zzz-outline-density.md'].selected", wait: 2

    metrics = sidebar_density_metrics

    assert metrics["fileTreeOverflowing"], metrics.inspect
    refute metrics["fileTreeOverlapsOutline"]
    assert_operator metrics["outlineScrollHeight"], :<, 224, metrics.inspect

    sleep 0.3
  end

  private

  def dense_outline_content
    lines = [ "# Outline Density Audit", "", "Intro paragraph" ]

    14.times do |index|
      lines << ""
      lines << "## Section #{format('%02d', index + 1)}"
      lines << ""
      lines << "Body for section #{format('%02d', index + 1)}"
    end

    lines.join("\n")
  end

  def editor_cursor_line
    page.evaluate_script(<<~JS)
      (function() {
        var el = document.querySelector('[data-controller~="codemirror"]');
        var ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'codemirror');
        return ctrl ? ctrl.getCursorInfo().currentLine : null;
      })()
    JS
  end

  def sidebar_density_metrics
    page.evaluate_script(<<~JS)
      (function() {
        var fileTree = document.querySelector('#file-tree-content');
        var outlineList = document.querySelector('[data-outline-target="list"]');
        var outlineScroll = outlineList ? outlineList.parentElement : null;
        var outlinePanel = document.querySelector('.outline-panel');
        var fileTreeRect = fileTree.getBoundingClientRect();
        var outlineRect = outlinePanel.getBoundingClientRect();

        return {
          fileTreeHeight: fileTree.clientHeight,
          outlineScrollHeight: outlineScroll ? outlineScroll.clientHeight : 0,
          fileTreeOverflowing: fileTree.scrollHeight > fileTree.clientHeight + 1,
          fileTreeOverlapsOutline: fileTreeRect.bottom > outlineRect.top + 1
        };
      })()
    JS
  end
end
