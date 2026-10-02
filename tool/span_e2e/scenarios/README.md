# Span report e2e scenarios

Run against `tool/mock_span_api` serving a `--dart-define=SPAN_SEMANTICS=true` web build:

```bash
MOCK_PASSWORD=<password from mock-users.json> node tool/span_e2e/run.mjs tool/span_e2e/scenarios/reports.json out/reports
MOCK_PASSWORD=... node tool/span_e2e/run.mjs tool/span_e2e/scenarios/templates.json out/templates
```

- `reports.json`: write a report with Span, progress page and row progress, open it, bold a word, swap,
  upload and undo photos, download Word and PDF, and check an older HTML report still opens the old way.
- `templates.json`: build a template from two example reports, progress, the template page, fields,
  instructions edit (saved), style guide, Download Word.

Uploads come from `scenarios/fixtures/` (not in git: two example `.docx` reports named
`Roof survey - Harbor Rd.docx` / `Roof survey - Kent St.docx` and a `new-site-photo.jpg`). The text the
report scenario taps (`BRONXDALE MASONRY CORP`) comes from the mock fixture's fill map; change it to a value
in your own fixture.
