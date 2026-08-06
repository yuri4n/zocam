---
title: "Zocam.Span.Arc"
description: "A directed span between two bounds of the same form, with per-side closings, a step, and an overflow policy."
---

[AI SLOP]{.ai-slop} An AI agent wrote the docstrings; `mix docs` generated this page. [yuri4n](https://github.com/yuri4n), a senior engineer, gave the direction and did the review. The review is human, thus errors can stay.

[Source on GitHub ↗](https://github.com/yuri4n/zocam/blob/main/lib/zocam/span.ex#L171){.source-link}

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

## Enumerate an arc

One instance of an arc is a row of grain cells, and `Enum` walks
that row: the struct implements `Enumerable` and yields the
symbolic cells of ONE instance, in walking order. Each cell comes
out as the simplest honest value — the bare cell value when the
bounds are single-segment chains (`:friday`, `:november`, `15`,
`~T[09:15:00]`), and a chain in which only the grain cell varies
when the bounds carry a prefix (`[month: :may, day: 11]`). The
walk reuses `Zocam.Span.ground/3`'s reading of "cell": the same
wrap rule, the same whole-unit closings, the same step sampling.

The common call — the four weekday cells of "Friday through
Monday" (the smart constructors hand the arc back inside an
`{:arcs, ...}` node, so match it out first):

    iex> {:arcs, _, _, [weekend]} =
    ...>   Zocam.Span.arc!(
    ...>     from: Zocam.Point.weekday(:friday),
    ...>     until: Zocam.Point.weekday(:monday)
    ...>   )
    iex> Enum.to_list(weekend)
    [:friday, :saturday, :sunday, :monday]

Closings are honored: an `:open` side drops that bound's whole
cell, exactly as it does under grounding:

    iex> {:arcs, _, _, [stay]} =
    ...>   Zocam.Span.arc!(
    ...>     from: Zocam.Point.weekday(:friday),
    ...>     until: Zocam.Point.weekday(:monday),
    ...>     right: :open
    ...>   )
    iex> Enum.to_list(stay)
    [:friday, :saturday, :sunday]

The edge: a wrapping arc walks through the cycle seam, inside
one instance — November through February is four month cells:

    iex> {:arcs, _, _, [winter]} =
    ...>   Zocam.Span.arc!(
    ...>     from: Zocam.Point.month(:november),
    ...>     until: Zocam.Point.month(:february)
    ...>   )
    iex> Enum.to_list(winter)
    [:november, :december, :january, :february]

The integrated use: a step whose unit is the grain samples every
n-th cell, so a stepped `:time` arc yields its sampled `Time`
values:

    iex> {:arcs, _, _, [morning]} =
    ...>   Zocam.Span.arc!(
    ...>     from: Zocam.Point.time(~T[09:00:00]),
    ...>     until: Zocam.Point.time(~T[12:00:00]),
    ...>     step: {15, :minute}
    ...>   )
    iex> Enum.count(morning)
    12
    iex> Enum.take(morning, 3)
    [~T[09:00:00], ~T[09:15:00], ~T[09:30:00]]

The pitfall: an UNstepped `:time` arc is continuous — between
any two instants sit infinitely many more — so it has no cells
to walk, and `Enum` on it raises with the two ways out:

    iex> {:arcs, _, _, [window]} =
    ...>   Zocam.Span.arc!(
    ...>     from: Zocam.Point.time(~T[09:00:00]),
    ...>     until: Zocam.Point.time(~T[12:00:00])
    ...>   )
    iex> Enum.to_list(window)
    ** (ArgumentError) a :time-grain arc without a step is continuous, so it has no cells to enumerate. Two ways out: give the arc a step (for example step: {15, :minute}), or ground the span with Zocam.Span.ground/3 and walk the concrete intervals.

The same honesty applies to every arc whose one-instance cell
row is not fixed: a step whose unit is not the grain ("the 31st,
monthly" samples across real months), an ordinal or negative
bound (each month elects its own "last Saturday"), bounds that
differ above the grain cell, and a wrap in a cycle without a
fixed length (a month has 28 to 31 days). Each raises an
`ArgumentError` that points to `Zocam.Span.ground/3` — the
interpreter that walks the real calendar.

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
