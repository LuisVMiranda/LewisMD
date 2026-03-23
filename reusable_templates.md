# Reusable Templates Implementation Plan

## Goal
Expand note creation beyond `Empty` and `Hugo` by adding a small built-in set of markdown templates that generate useful starter content while keeping the filesystem-first model intact.

## Why This Is The Right Next Phase
- It improves the core note-taking workflow directly.
- It avoids heavy features like databases, custom template engines, or plugin systems.
- It fits the existing creation flow and current server-side note creation patterns.
- It is low-risk compared with larger UI/state features because it mainly affects creation-time logic.

## Scope

### Include
- a built-in template picker flow
- server-side generation of starter markdown content
- support for creating template-based notes in root or inside folders
- small UI additions to the existing note-creation dialogs
- tests and documentation

### Exclude
- user-editable custom templates
- marketplace or remote templates
- template variables editor
- template inheritance
- database-backed metadata

## Recommended Built-In Templates
1. Daily Note
2. Meeting Note
3. Article Draft
4. Journal Entry
5. Changelog

## Architecture

### Backend
Add a new service:
- `app/services/note_template_service.rb`

Responsibilities:
- expose available built-in template ids and labels
- generate markdown scaffold for a given template
- keep content generation deterministic and testable
- avoid any filesystem write logic inside the service itself if current controller/service patterns already own file creation

Suggested API:
- `NoteTemplateService.options`
- `NoteTemplateService.generate(template_id, title:, parent:)`

Output:
- normalized filename suggestion if needed
- markdown body content

### Controller Changes
Update note creation handling in:
- `app/controllers/notes_controller.rb`

Desired behavior:
- if `template` is absent: existing empty-note behavior
- if `template == "hugo"`: keep current Hugo behavior unchanged
- if `template` matches one of the built-ins: generate template content and create a standard markdown note
- if template id is invalid: reject cleanly

Important rule:
- built-in templates should create normal notes, not special note types

## UI Flow

### Proposed Flow
1. User clicks `New note`
2. First dialog shows three choices:
   - Empty document
   - Template
   - Hugo post
3. If user picks `Template`, open a second compact dialog:
   - title: `Choose template`
   - list of 5 built-in templates
4. After choosing one, open the existing naming dialog:
   - prefill filename based on template
   - preserve parent folder context if the user created it from a folder
5. Submit as normal with `template` id included

### Why This Flow Is Best
- it avoids cramming 7 options into the first modal
- it preserves the app’s already lightweight creation rhythm
- it avoids visual pollution in the sidebar or header

## UI Placement
Modify the existing dialog partial in:
- `app/views/notes/dialogs/_file_operations.html.erb`

Do not add:
- new sidebar buttons
- new persistent toolbar buttons
- always-visible template panels

## Frontend Controller Work
Update:
- `app/javascript/controllers/file_operations_controller.js`

Add responsibilities:
- open/close the template picker step
- remember the chosen template id
- prefill filenames intelligently
- pass template id during submit

Suggested defaults:
- Daily Note: `YYYY-MM-DD`
- Meeting Note: `meeting-YYYY-MM-DD`
- Article Draft: `article-draft`
- Journal Entry: `journal-YYYY-MM-DD`
- Changelog: `changelog`

## Template Content Design

### Daily Note
- Date
- Top Priorities
- Notes
- Wins
- Tomorrow

### Meeting Note
- Date
- Attendees
- Agenda
- Notes
- Decisions
- Action Items

### Article Draft
- Title
- Summary
- Outline
- Draft
- References

### Journal Entry
- Date
- Mood
- What Happened
- Reflections
- Gratitude

### Changelog
- Unreleased
- Added
- Changed
- Fixed

Important content rules:
- plain markdown only
- no special frontmatter unless there is a very strong reason
- keep scaffolds concise, not bloated

## Testing Plan

### Ruby Tests
- service tests for `NoteTemplateService`
- controller tests for template-based note creation
- invalid-template rejection tests
- preservation of existing Hugo behavior

### JavaScript Tests
- file operations controller tests for template picker flow
- selected template propagation
- filename prefill behavior

### System Tests
- create each built-in template from root
- create at least one template from folder context menu
- verify created note content scaffold
- verify Empty and Hugo flows still work

## Edge Cases To Cover
- invalid template id
- creating template note inside nested folder
- filename conflicts using current note creation behavior
- switching back from Template to Empty/Hugo during dialog flow
- locale-safe UI labels
- note names with spaces or punctuation under current normalization rules

## Documentation Work
Update:
- `README.md`
- `antigravity.md`

## Implementation Feedback Before Coding
This phase is a strong fit for the project because it gives users more structure at note creation time without changing how notes are stored, edited, or rendered. The main thing to avoid is overdesign: built-in templates should stay opinionated and simple, and the picker should remain a short branch off the current new-note flow rather than becoming its own subsystem.
