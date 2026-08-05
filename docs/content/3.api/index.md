---
title: "API Reference"
description: "All public modules of zocam, generated from the Elixir docstrings by mix docs."
---

[AI SLOP]{.ai-slop} An AI agent wrote the docstrings; `mix docs` generated this page. [yuri4n](https://github.com/yuri4n), a senior engineer, gave the direction and did the review. The review is human, thus errors can stay.

To change this reference, edit the `@doc` and `@moduledoc` attributes
in `lib/`, run `mix docs` in the repository root, and rebuild.

| Module | Summary |
| --- | --- |
| [Zocam](/api/zocam) | A three-layer library for time: calendar things, sets of them, and concrete intervals. |
| [Zocam.Intervals](/api/zocam-intervals) | The linear kernel: sets of concrete intervals on one axis, with union, intersection, complement, and difference. |
| [Zocam.ISO](/api/zocam-iso) | One calendar, checked at the door: Calendar.ISO. |
| [Zocam.Point](/api/zocam-point) | A calendar point: a concrete or abstract "thing about time". |
| [Zocam.Point.ComposeError](/api/zocam-point-composeerror) | Raised (or returned) when two points do not compose. |
| [Zocam.Span](/api/zocam-span) | Sets of instants built from calendar points: arcs, unions, intersections, complements, and ordinal selection. |
| [Zocam.Span.Arc](/api/zocam-span-arc) | A directed span between two bounds of the same form, with per-side closings, a step, and an overflow policy. |
