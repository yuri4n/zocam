---
title: "Zocam.Span.Arc"
description: "A directed span between two bounds of the same form, with per-side closings, a step, and an overflow policy."
---

[AI SLOP]{.ai-slop} An AI agent wrote the docstrings; `mix docs` generated this page. [yuri4n](https://github.com/yuri4n), a senior engineer, gave the direction and did the review. The review is human, thus errors can stay.

[Source on GitHub ↗](https://github.com/yuri4n/zocam/blob/main/lib/zocam/span.ex#L118){.source-link}

A directed span between two bounds of the same form, with
per-side closings, a step, and an overflow policy.

An arc always lives inside an `{:arcs, scope, grain, arcs}` node.
The node owns the scope and the grain — the arc holds only the
bounds, so the two can never disagree. The smart constructors
guarantee that every arc's chains match its node.

On a bare coarse unit the closing covers the whole unit:
`until: february, right: :open` excludes all of February;
`right: :closed` includes all of it.

`step: nil` means "no sampling": the arc covers the whole block
between its bounds. A `{1, grain}` step is the same set, so the
constructors normalize it to `nil` — one canonical spelling for
one meaning. The overflow policy comes from the bound points and
acts where a day number lands in a short month.

An arc is not a `t:Zocam.Intervals.interval/0`. The arc is
symbolic and *repeats* — "Fri..Mon" happens once in every week.
The interval is concrete and happens *once*. `Zocam.Span.ground/3`
turns each instance of an arc into 0, 1, or 2 concrete intervals
(a DST gap, a normal day, a DST fold). See "The four names" in
the `Zocam` moduledoc for the full map.

## Types

### `t`

```elixir
@type t() :: %Zocam.Span.Arc{
  from: Zocam.Point.chain(),
  left: Zocam.Intervals.closing(),
  overflow: Zocam.Point.overflow(),
  right: Zocam.Intervals.closing(),
  step: Zocam.Span.step() | nil,
  until: Zocam.Point.chain()
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
