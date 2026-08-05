---
title: "Zocam.Span"
description: "Sets of instants built from calendar points: arcs, unions, intersections, complements, and ordinal selection."
---

[AI SLOP]{.ai-slop} An AI agent wrote the docstrings; `mix docs` generated this page. [yuri4n](https://github.com/yuri4n), a senior engineer, gave the direction and did the review. The review is human, thus errors can stay.

[Source on GitHub ↗](https://github.com/yuri4n/zocam/blob/main/lib/zocam/span.ex#L5){.source-link}

Sets of instants built from calendar points: arcs, unions,
intersections, complements, and ordinal selection.

This module is the set layer over `Zocam.Point`. The layers:

    Point ──▶ Arc ──▶ Span ──▶ ground/3 ──▶ Zocam.Intervals
    (thing)   (from..until    (recursive     (linear kernel,
               + closings      set: the       already tested)
               + step)         algebra)

A span is one recursive type. The *set* is primary and a single
interval is only a one-arc set. The reason is closure: the
complement of one arc is already two pieces, and a diff can cut one
interval into two. A standalone interval type cannot be closed
under its own operators.

Keep the names apart: `Zocam.Span.Arc` is *one symbolic piece*
and `t:t/0` is the *symbolic set* built over such pieces, while
`t:Zocam.Intervals.interval/0` is *one concrete piece* and
`t:Zocam.Intervals.t/0` is the *concrete set*. "The four names" in
the `Zocam` moduledoc shows the full two-by-two map.

## Two evaluation regimes

- **Within one cycle** the algebra is eager where it can be: when
  same-scope arc nodes merge in a union, the plain arcs (one
  segment, both sides closed, no step, no wrap) compact to sorted,
  disjoint integer cell ranges (january=1..december=12,
  monday=1..sunday=7), so `Jan..Jan` plus `Feb..Feb` IS `Jan..Feb`.
  All other arcs (wraps, steps, ordinals, open sides) ride along
  unchanged: the form is quasi-canonical, not minimal. A step
  samples cells forward from the `from` bound after the `until`
  bound has been resolved across the wrap seam, so the sampling
  phase runs through the seam.
- **Across cycles** the tree stays symbolic and lazy: "Wednesdays
  in May" has no finite normal form before grounding, so the
  intersection node holds it as data. This is the interpreter
  pattern: constructors build a free algebra, and `member?/2` and
  `ground/3` are its two interpreters.

Both interpreters share ONE denotation function: clamping, ordinal
skipping, and closings behave identically in `member?/2` and
`ground/3`. Keeping them equal is the keystone property test:
`member?(span, t) == member of t in ground(span, horizon, tz)`.

## How an arc becomes kernel intervals

The shared denotation core works in *wall time* and meets the real
timeline only at the very end:

    arc                     one per scope instance
     │ chain_window/3        (year 2026, week of Jan 5, ...)
     ▼
    wall windows            [~N[2026-11-01 00:00:00],
     │ preimage/3            ~N[2027-02-01 00:00:00])
     ▼
    UTC intervals           the tzdata period table maps each wall
     │ clip + compress       window to 0, 1, or 2 UTC pieces
     ▼
    Zocam.Intervals

`member?/2` stops at the second stage: it reads the wall clock of
the given `DateTime` and checks the wall windows directly. That is
why the two interpreters cannot disagree: they run the same code up
to the point where a timezone exists.

## Wrap-around

`Fri..Mon`, `Nov..Feb`, and `22:00..06:00` are legal arcs. A wrap
is decided at the chain level, before closings expand: `May..May`
is the single-unit case, never a wrap. A wrapping arc materializes
*forward*: the until bound resolves in the next cycle instance, so
`Nov..Feb` becomes one continuous block `[Nov 1, Feb 1)` of the
following year and nothing needs to re-fuse at the seam.
`member?/2` therefore checks the instance of the probed instant
*and its predecessor*: a block that started last instance can
still cover the probe.

## Timezone

Only `ground/3` and `member?/2` on real `DateTime`s meet the
timeline. `member?/2` reads the wall clock of the given DateTime.
`ground/3` resolves wall times in the given timezone: an instance
can ground to *two* kernel intervals on a fall-back day (the wall
window exists twice), and a wall time inside a spring-forward gap
grounds to nothing.

## One calendar

Every `DateTime` this module takes must be on `Calendar.ISO`:
`absolute!/1`, the `ground/3` horizon, `member?/2`, and `stream/3`
all check it and refuse anything else. The wall dates that come out
of those instants are read as ISO dates — `instance_index/2` reads
`date.year` and `date.month` as Gregorian numbers — so the check is
what makes the reading true. See `Zocam.ISO`.

## Types

### `n`

```elixir
@type n() :: pos_integer() | neg_integer()
```

### `step`

```elixir
@type step() :: {pos_integer(), Zocam.Point.unit() | time_unit()}
```

### `t`

```elixir
@type t() ::
  {:arcs, Zocam.Point.scope(), Zocam.Point.grain_class(),
   [Zocam.Span.Arc.t(), ...]}
  | {:absolute, Zocam.Intervals.interval()}
  | {:union, [t()]}
  | {:intersection, [t()]}
  | {:complement, t()}
  | {:nth, n(), t(), Zocam.Point.cycle()}
```

### `time_unit`

```elixir
@type time_unit() :: :hour | :minute | :second
```
## Functions

### `absolute!`

```elixir
@spec absolute!(Zocam.Intervals.valid_interval()) :: t()
```

Wrap an already-linear interval (`Zocam.Intervals` spec) as a
span, e.g. "from 2026-05-23 onward". This is where unbounded sides
live: cyclic arcs always have both bounds, absolute ones may not.
Bounds must be `DateTime` (or `nil` for a ray): a span meets the
timeline as instants, never as bare wall values.

### `arc!`

```elixir
@spec arc!(
  from: Zocam.Point.t(),
  until: Zocam.Point.t(),
  left: Zocam.Intervals.closing(),
  right: Zocam.Intervals.closing(),
  step: pos_integer() | step()
) :: t()
```

Build a one-arc span between two points of the same form.

Options: `from:`, `until:` (both `Point.t()`, required, same scope
and grain class), `left:`, `right:` (closings; defaults: `:closed`
on both sides for bare-unit grains, `:closed`/`:open` when the
grain is `:time`), `step:` (default: no sampling). A bare integer
step means `{n, grain}` and is legal only at discrete grains; at
`:time` grain the unit is mandatory (`{15, :minute}`).

`from == until` names the single unit (`:open` on any side excludes
it entirely, so the result is `empty/0`). A bound order that runs
backward in cycle order wraps: `november..february`,
`friday..monday`. On the `:absolute` scope there is no cycle to
wrap in, so backward bounds raise.

### `complement`

```elixir
@spec complement(t()) :: t()
```

Everything outside the given span.

### `diff`

```elixir
@spec diff(t(), t()) :: t()
```

Set difference: `a` without `b`.

Defined as `intersection([a, complement(b)])`. One-versus-many and
many-versus-one are not special cases: "many" is already a union
value on either side. The linear kernel computes its own diff the
same way, so the two layers agree by construction.

### `empty`

```elixir
@spec empty() :: t()
```

The empty set: a union of nothing.

### `empty?`

```elixir
@spec empty?(t(), Zocam.Intervals.interval(), Timex.Types.valid_timezone()) ::
  boolean()
```

Does the span contain no instant inside the horizon?

### `ground`

```elixir
@spec ground(t(), Zocam.Intervals.interval(), Timex.Types.valid_timezone()) ::
  Zocam.Intervals.t()
```

Evaluate the span over a bounded horizon into the linear kernel.

Enumerates every scope instance that intersects the horizon,
grounds each fully (an instance may yield more than one kernel
interval on DST fall-back days), then clips to the horizon and
compresses. The horizon must be bounded on both sides: many spans
are infinite, so an unbounded ground cannot terminate.

### `intersection`

```elixir
@spec intersection([t()]) :: t()
```

The intersection of the given spans. `intersection([])` is `universe/0`.

### `member?`

```elixir
@spec member?(t(), DateTime.t()) :: boolean()
```

Is the instant inside the set? Symbolic: no horizon, no
enumeration. Reads the wall clock of the given DateTime and applies
the same denotation as `ground/3` (clamping included: the 31st is
a member on Feb 28 under `:clamp`).

### `nth`

```elixir
@spec nth(n(), t(), [{:per, Zocam.Point.cycle()}]) :: t()
```

Ordinal selection: the `n`-th grain cell of `span` inside each
instance of the `per` cycle. Negative `n` counts from the end.

    nth(-1, weekdays, per: :month)  # last working day of the month

A missing ordinal skips the instance (no 5th Wednesday: nothing).
Grounding widens to whole `per` instances before counting, then
clips to the horizon, so a cut-off January never miscounts its
last Friday.

The inner span must be cyclic with day-sized grain cells: `nth`
counts days, and an `{:absolute, _}` node or a `:time`-grain leaf
has no day cells to count.

### `of`

```elixir
@spec of(Zocam.Point.t()) :: t()
```

Lift a point into the set algebra: the set of all instants the
point denotes (one grain-sized interval per scope instance).

The result is a one-arc node whose bounds are both the point's
chain, closed on both sides: "May" is the arc `May..May`.

### `stream`

```elixir
@spec stream(t(), DateTime.t(), Timex.Types.valid_timezone()) :: Enumerable.t()
```

Lazily enumerate the span's intervals from an instant forward, in
order. The stream grounds chunk by chunk (one year at a time, with
a one-year lookahead), so it works without a right bound; take
from it what you need.

### `union`

```elixir
@spec union([t()]) :: t()
```

The union of the given spans. `union([])` is `empty/0`.

### `universe`

```elixir
@spec universe() :: t()
```

The whole timeline: an intersection of no constraints.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
