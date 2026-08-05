---
title: "Design decisions (ADRs)"
description: "One record for each irreversible design choice in the zocam time library, with the reasoning behind it."
---

[AI SLOP]{.ai-slop} An AI agent wrote this page. [yuri4n](https://github.com/yuri4n), a senior engineer, gave the direction and did the review. The review is human, thus errors can stay.

An ADR is an architecture decision record: a short page that captures one decision, with its context, its options, and its consequences. This project writes one ADR for each choice that is hard to reverse. The records serve two goals. They teach: you can read *why* the design is what it is, not only what it is. And they give traceability: when a later change pushes against an old decision, the ADR shows what that change must respect or revise.

Read the records in order. Each one builds on the ones before it: ADR-001 fixes the shape of a point, ADR-002 builds spans on top of points, and ADR-005 ties both to one shared meaning function.

## Timetable

| ADR | Decision in one line |
| --- | --- |
| [ADR-001](/design/adr-001-refinement-chain) | A calendar point is a scope plus a refinement chain |
| [ADR-002](/design/adr-002-set-primary-spans) | Sets are primary; Span is a recursive set algebra over points and arcs |
| [ADR-003](/design/adr-003-overflow-policy) | Overflow clamps by default; `:skip` is an explicit override |
| [ADR-004](/design/adr-004-fortnight-scopes) | Fortnights are `{:every, k, cycle, anchor}` scopes with subsequence semantics |
| [ADR-005](/design/adr-005-shared-denotation) | `member?` and `ground` share one denotation function; DST rules pinned |
| [ADR-006](/design/adr-006-library-extraction) | The time layer is its own library, extracted from the s7r app |

*Figure 1 — The ADR timetable: one row per record, with the decision in one line. AI generated, human reviewed.*

::note
The ADR sources live as plain markdown in `docs/adr-*.md` in the repository — they are also the ExDoc extras on hexdocs. The documentation pipeline generates these pages from those files. To change an ADR, edit it there, not here.
::
