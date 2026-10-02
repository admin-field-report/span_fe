# Span report editor and report templates (feature/span-report-editor)

What this branch does, how to run it, and how to check it before production.
Design: Figma file `WmfEdnU0dkU4H3rFTUeYpa`, page "Report Generation" (frames R1–R7, TP1–TP6).

## What changed for users

**Writing a report (Project > Reports)**
- Create Report > Write with Span > "Write report with Span" opens a progress page with four plain steps
  (Reading the inspection, Writing the report, Placing photos, Final check). No agent log, no time left.
  The user can leave: the report's row in the Reports tab shows "Span is writing" with a progress bar and
  turns into a normal row when Span finishes.
- Span reports (report_format `docx`) always open in the Span report screen. They never open in the old
  HTML editor or PDF preview, which can't read Word reports. Download on their row saves the current Word file.
- The report screen shows the report as Word pages drawn by the app (letterhead, tables, text boxes,
  photos, headers and footers) on web, iPad and Android:
  - Tap any value on the page to edit it in place. The toolbar does bold, italic, underline, strike,
    clear formatting, bulleted and numbered lists, undo and redo (Ctrl+Z / Ctrl+Y too).
  - The right sidebar lists the inspection's photos ("In report" marks the ones used). Selecting a photo on
    the page shows its caption (editable), Move left / Move right, Remove, and the album: clicking a photo
    swaps it into that spot (the caption stays). Upload adds a new photo.
  - Changes save on their own ("Saving…" / "Saved"). The server rebuilds the Word file (and its PDF) from
    the edited fill map; Download waits for that, so a download always includes the latest edits.
  - Download > Word (.docx) or PDF (.pdf). "Rewrite with Span" starts a new report from the inspection.
- Older (HTML/PDF) reports are unchanged.

**Report templates (Templates > Report Templates)**
- The list shows "Made from" (example reports · Span, or PDF / skill examples) and a progress bar on
  templates Span is building.
- New template: name + 2–5 example reports (Word or PDF, drag and drop or browse) > "Build template with
  Span" > the same kind of progress page. Span no longer stops to ask questions.
- A built template shows its Word pages with every field as a blue chip and repeating blocks outlined.
  Sidebar tabs: Fields (each field and where its value comes from; selecting one highlights it on the page),
  Instructions and Style guide (editable, saved automatically). Download Word, Upload edited Word file,
  Rebuild with Span.

## Code map

| Path | What |
|---|---|
| `lib/span_doc/docx_model.dart` | Reads a .docx (styles, numbering, tables, text boxes, floating shapes, pictures with cropping, headers/footers, page setup). Placeholders become `DocxSlot`s. |
| `lib/span_doc/fill_binding.dart` | Lays a fill map over a template the way the agent's `fill_template.py` fills Word: repeating blocks, list rows, photo blocks (`photo_slots.py` rules), image frames. Every value knows its fill-map path. |
| `lib/span_doc/fill_values.dart` | Fill-map get/set and value shapes, including formatted text `{"runs": [...]}`. |
| `lib/span_doc/report_page_view.dart` | Draws the pages. Report mode: tappable values, selectable photos. Template mode: field chips, outlined blocks. |
| `lib/span_doc/rich_field_controller.dart`, `editor_toolbar.dart` | In-place rich text editing and the toolbar. |
| `lib/screens/projects/reports/generation/report_run_screen.dart` | The report screen (progress, editor, autosave, downloads). |
| `lib/screens/projects/reports/generation/widgets/` | `span_progress_card.dart` (progress page + row bar), `report_photo_sidebar.dart`. |
| `lib/screens/projects/reports/project_reports.dart` | Reports tab: routing for Span reports, row progress, Word download. |
| `lib/screens/reports/span_template_screen.dart`, `reports_screen.dart` | Template setup / progress / page + sidebar, and the templates list. |
| `lib/utils/save_report_file.dart` | Saves Word/PDF on web (download) and on iPad/Android (Documents/Span Inspect, then opens it). |
| `tool/mock_span_api/` | Local stand-in for the Span backend (no login to dev needed). |
| `tool/span_e2e/run.mjs` | Headless end-to-end runner (Edge/Chrome) that clicks through the app by text. |

Removed: the old fill-map field editor (`report_document_editor.dart`), the agent-log progress panel,
`span_reports_list.dart`, and the old profiler screen with its questions step and web-only docx preview.

## Depends on (merge these first)

1. **be_rest_api** `feature/span-report-editor`: `GET /span-report/runs/:jobId/fill-map` adds `album`
   (every inspection photo as a fill-map path + caption); `GET /span-report/runs/:jobId` adds `pdf`.
   Without it the album only shows photos already in the report and PDF download says "not ready".
2. **span-eve-agent** `feature/span-report-editor`: `fill_template.py` understands formatted text
   (`{"runs": [...]}`), the rebuild renders `filled.edited.pdf`, generate jobs upload `filled.pdf`, and
   template jobs never pause for questions. **Must be deployed to Vercel before this app ships**: without
   it, bold/italic/underline edits come out of the Word rebuild as plain text and edited reports have no PDF.

The app branch is based on `feature/eve-report-agent` (PR #6), so merging it includes that PR.

## How to run and check it locally (no dev login)

```bash
# 1. Mock backend + the web build, with real fixtures from a profiled template and one generated report
#    (fixture folder layout is in tool/mock_span_api/server.mjs; keep client data out of git)
MOCK_PYTHON=<python with python-docx> MOCK_FILL_SCRIPT=<span-eve-agent>/agent/skills/report-generate-from-profile/scripts/fill_template.py \
  node tool/mock_span_api/server.mjs --fixtures <fixtures dir> --port 8787 --static build/web --static-port 5180
flutter build web --release --dart-define=SPAN_API_BASE_URL=http://localhost:8787 --dart-define=SPAN_SEMANTICS=true
# 2. Sign in at http://localhost:5180/login?beta=true with an account from <fixtures>/mock-users.json
# 3. Automated end-to-end runs (scenario JSON format is documented at the top of run.mjs)
MOCK_PASSWORD=... node tool/span_e2e/run.mjs <scenario.json> <out dir>
# 4. Unit tests
flutter test test/span_doc/span_doc_test.dart
```

## Test before production (on dev, with the real backend and agent)

Run on web **and** an iPad (and an Android tablet if you have one).

1. Project > Reports > Create Report > Write with Span > Write report with Span: progress page shows the
   four steps; Back to Reports shows the row with "Span is writing" and a bar; the row updates by itself.
2. Open the finished report: the pages look like the template's examples (logo, header/footer, tables,
   photos and captions). Compare with Download > Word: same content, same order.
3. Tap a sentence, select a word, Bold: "Saving…" then "Saved" within about a minute. Download Word and
   open it in Word: the word is bold. Repeat with italic, underline, a bulleted list.
4. Select a photo: caption edit, Move left/right, Remove, swap from the album, Upload. Each saves; the
   downloaded Word file has the change.
5. Download > PDF after an edit: the PDF includes the edit.
6. Undo / Redo restore earlier text and photos (and save).
7. Old HTML reports: view, edit, download still work exactly as before.
8. On iPad / Android: the report is visible (no "web only" message), Download saves to Documents/Span
   Inspect and opens the file.
9. Templates > Report Templates > Create Report Template > Build from example reports: add 2+ examples,
   Build; progress page, then the row's progress bar; when ready the page shows blue field chips and
   outlined blocks; Fields highlight on the page; edit Instructions and Style guide (Saved), reload and see
   the edit kept; Download Word; Upload edited Word file; Rebuild with Span.
10. A template build never shows a questions step and never stalls waiting for answers.

## Known limits (not blockers)

- Pages split at section and page breaks only; a long section is one tall sheet. The downloaded Word file
  paginates exactly.
- Fonts are drawn with metric-compatible open fonts (Carlito for Calibri, Arimo for Arial, etc.).
- Callout leader arrows (red lines from caption boxes to photos) are not drawn on screen; they are in the Word file.
- Paragraph style, text color, highlight, alignment, indent, links and tables are not in the toolbar: the
  Word rebuild only carries text and bold/italic/underline/strike, and layout comes from the template.
- Each save starts a short agent rebuild session (seconds). Saves are batched (2.5 s after the last change)
  and queued while a rebuild runs.
