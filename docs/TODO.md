<!-- agent: claude — whole file. Requested by the reviewer on 2026-08-04.
     Rewritten 2026-08-05: the two former entries were promoted to Linear
     (see "What left this file"), per the rule in AGENTS.md. -->

# Docs site — local notes

Small items that belong to **one file**. The person who opens that file is
the person who does them. Keep this list short; delete an entry when it
ships or when it dies.

Anything that needs an ADR, or that touches several files, goes to Linear
instead (see "Where work is tracked" in `AGENTS.md`).

<!-- agent: claude — added 2026-08-05, found while the doctests were
     written (Linear YUR-130). -->

## Span.ground/3: the unbounded-horizon error cannot be a doctest

`check_horizon!/1` in `lib/zocam/span.ex` writes `inspect(horizon)`
into its error message. The key order of a map in `inspect` is not
stable across Erlang VMs, thus a doctest cannot pin that message; the
`ground/3` examples stop before it. If the message must become
testable, name the missing side ("until is nil") instead of the whole
map.

## What left this file

Both former entries grew past a single file and are now Linear issues:

- **Hover popups on code references** → YUR-125. It became cross-repo:
  `app/utils/api-links.ts` is byte-identical in both repositories
  (16072 bytes each), so the work is to make it a shared package, not to
  copy it a third time.
- **Runnable code blocks** → YUR-128 (and YUR-127 on the s7r side). The
  entry said itself that it must not start without an ADR, which makes it
  a decision, not a local note.
