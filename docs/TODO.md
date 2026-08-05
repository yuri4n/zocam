<!-- agent: claude — whole file. Requested by the reviewer on 2026-08-04.
     Rewritten 2026-08-05: the two former entries were promoted to Linear
     (see "What left this file"), per the rule in AGENTS.md. -->

# Docs site — local notes

Small items that belong to **one file**. The person who opens that file is
the person who does them. Keep this list short; delete an entry when it
ships or when it dies.

Anything that needs an ADR, or that touches several files, goes to Linear
instead (see "Where work is tracked" in `AGENTS.md`).

## Caption the generated API index table

`docs/content/2.design/index.md` gives its ADR table a caption. The
generated `docs/content/3.api/index.md` module table has none.

The fix belongs in the generator, not in the page: `renderIndex()` in
`docs/scripts/ingest-exdoc.mjs` writes that table. Emit a caption below
it with the three parts the "Figures" rule asks for — the figure name,
one line on what it shows, and the note that AI made it. Then update the
`renderIndex` unit tests to assert it.

s7r has the same gap in its own copy of the script.

## Give the ADR folder a sidebar entry

`docs/content/2.design/adrs/` has no `.navigation.yml`, so the folder
shows a raw title in the sidebar. `1.guide` and `2.design` both have one.
Add a title and an icon.

The dead `/design/adr-*` links left by the same unfinished move are a
larger item and live in Linear as YUR-69.

## What left this file

Both former entries grew past a single file and are now Linear issues:

- **Hover popups on code references** → YUR-125. It became cross-repo:
  `app/utils/api-links.ts` is byte-identical in both repositories
  (16072 bytes each), so the work is to make it a shared package, not to
  copy it a third time.
- **Runnable code blocks** → YUR-128 (and YUR-127 on the s7r side). The
  entry said itself that it must not start without an ADR, which makes it
  a decision, not a local note.
