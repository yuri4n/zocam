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
| [ADR-001](/design/adrs/001-refinement-chain) | A calendar point is a scope plus a refinement chain |
| [ADR-002](/design/adrs/002-set-primary-spans) | Sets are primary; Span is a recursive set algebra over points and arcs |
| [ADR-003](/design/adrs/003-overflow-policy) | Overflow clamps by default; `:skip` is an explicit override |
| [ADR-004](/design/adrs/004-fortnight-scopes) | Fortnights are `{:every, k, cycle, anchor}` scopes with subsequence semantics |
| [ADR-005](/design/adrs/005-shared-denotation) | `member?` and `ground` share one denotation function; DST rules pinned |
| [ADR-006](/design/adrs/006-standalone-library) | Zocam is a standalone repository that releases to Hex |
| [ADR-007](/design/adrs/007-one-value-sets) | Set operations answer with the `%Intervals{}` struct; sets and arcs enumerate |

*Figure 1 — The ADR timetable: one row per record, with the decision in one line. AI generated, human reviewed.*

::note
These records are hand-written pages. They live in the zocam repository at `docs/content/2.design/adrs/`, and nothing generates them. To change an ADR, edit the page itself. They are not ExDoc extras: hexdocs carries the API reference only.
::

::note
This series records zocam's side of each decision. When a decision also binds the s7r application, s7r keeps its own record, numbered from 001 in its own repository. ADR-006 is such a case: its consumer half is s7r ADR-001.
::
