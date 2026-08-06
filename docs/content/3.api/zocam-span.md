---
title: "Zocam.Span"
description: "Sets of instants built from calendar points: arcs, unions, intersections, complements, and ordinal selection."
---

[AI SLOP]{.ai-slop} An AI agent wrote the docstrings; `mix docs` generated this page. [yuri4n](https://github.com/yuri4n), a senior engineer, gave the direction and did the review. The review is human, thus errors can stay.

[Source on GitHub ↗](https://github.com/yuri4n/zocam/blob/main/lib/zocam/span.ex#L9){.source-link}

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

## Recipes

You want every second Friday, 09:00–12:00, as concrete UTC
intervals. Do these steps: name the day, set the rhythm, cut the
hours, intersect, and ground. (January 2026 has Fridays on the
2nd, 9th, 16th, 23rd, and 30th; the anchor Jan 2 keeps the 2nd,
the 16th, and the 30th.)

    iex> fridays =
    ...>   Zocam.Point.weekday(:friday)
    ...>   |> Zocam.Point.every(2, ~D[2026-01-02])
    ...>   |> Zocam.Span.of()
    iex> morning =
    ...>   Zocam.Span.arc!(
    ...>     from: Zocam.Point.time(~T[09:00:00]),
    ...>     until: Zocam.Point.time(~T[12:00:00])
    ...>   )
    iex> span = Zocam.Span.intersection([fridays, morning])
    iex> horizon = %{
    ...>   from: ~U[2026-01-01 00:00:00Z],
    ...>   until: ~U[2026-02-01 00:00:00Z],
    ...>   left: :closed,
    ...>   right: :open
    ...> }
    iex> Zocam.Span.ground(span, horizon, "Etc/UTC").intervals
    [
      %{from: ~U[2026-01-02 09:00:00Z], until: ~U[2026-01-02 12:00:00Z], left: :closed, right: :open},
      %{from: ~U[2026-01-16 09:00:00Z], until: ~U[2026-01-16 12:00:00Z], left: :closed, right: :open},
      %{from: ~U[2026-01-30 09:00:00Z], until: ~U[2026-01-30 12:00:00Z], left: :closed, right: :open}
    ]

You want the last working day of each month. Select it with
`nth/3`, then ask with `member?/2` — no horizon needed. April 2026
ends on Thursday the 30th; May 2026 ends on Sunday the 31st, so
its last working day is Friday the 29th:

    iex> weekdays =
    ...>   Zocam.Span.arc!(
    ...>     from: Zocam.Point.weekday(:monday),
    ...>     until: Zocam.Point.weekday(:friday)
    ...>   )
    iex> last_working_day = Zocam.Span.nth(-1, weekdays, per: :month)
    iex> Zocam.Span.member?(last_working_day, ~U[2026-04-30 12:00:00Z])
    true
    iex> Zocam.Span.member?(last_working_day, ~U[2026-05-29 12:00:00Z])
    true
    iex> Zocam.Span.member?(last_working_day, ~U[2026-05-31 12:00:00Z])
    false

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

### `horizon`

```elixir
@type horizon() :: %{
  from: DateTime.t(),
  until: DateTime.t(),
  left: Zocam.Intervals.closing(),
  right: Zocam.Intervals.closing()
}
```

A bounded evaluation window for `ground/3`: a kernel-shaped map
whose two endpoints are both present and both `DateTime`. Many
spans are infinite, so an unbounded ground cannot terminate — the
type has no `nil` sides. When there is no right bound, use
`stream/3` instead.

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

    iex> onward = Zocam.Span.absolute!(from: ~U[2026-05-23 00:00:00Z])
    iex> Zocam.Span.member?(onward, ~U[2026-08-01 12:00:00Z])
    true
    iex> Zocam.Span.member?(onward, ~U[2026-05-22 12:00:00Z])
    false

The pitfall: a wall value is not an instant, so a `Time` bound is
refused here — build a daily window with `arc!/1` instead:

    iex> Zocam.Span.absolute!(from: ~T[09:00:00])
    ** (ArgumentError) absolute!/1 from: must be a DateTime or nil, got ~T[09:00:00]. Wall values (Time, month atoms) belong to Point and arc!/1.

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

#### Examples

The common arc: a block of weekdays, "Friday through Monday".
Jan 10 2026 is a Saturday; Jan 7 is a Wednesday:

    iex> weekend = Zocam.Span.arc!(
    ...>   from: Zocam.Point.weekday(:friday),
    ...>   until: Zocam.Point.weekday(:monday)
    ...> )
    iex> Zocam.Span.member?(weekend, ~U[2026-01-10 12:00:00Z])
    true
    iex> Zocam.Span.member?(weekend, ~U[2026-01-07 12:00:00Z])
    false

A time window with a step: "every 15 minutes from 09:00 to 17:00":

    iex> every_15 = Zocam.Span.arc!(
    ...>   from: Zocam.Point.time(~T[09:00:00]),
    ...>   until: Zocam.Point.time(~T[17:00:00]),
    ...>   step: {15, :minute}
    ...> )
    iex> Zocam.Span.member?(every_15, ~U[2026-05-15 09:15:00Z])
    true
    iex> Zocam.Span.member?(every_15, ~U[2026-05-15 09:07:00Z])
    false

The edge: backward bounds wrap. "November through February" is one
continuous block across the year seam, so December is inside:

    iex> winter = Zocam.Span.arc!(
    ...>   from: Zocam.Point.month(:november),
    ...>   until: Zocam.Point.month(:february)
    ...> )
    iex> Zocam.Span.member?(winter, ~U[2026-12-15 12:00:00Z])
    true
    iex> Zocam.Span.member?(winter, ~U[2027-02-15 12:00:00Z])
    true
    iex> Zocam.Span.member?(winter, ~U[2026-06-15 12:00:00Z])
    false

The pitfall: `May..May` with an open side is the empty set, never
"everything except May". Wrap is decided at the chain level, before
closings expand, and a whole-unit `:open` excludes the whole unit:

    iex> Zocam.Span.arc!(
    ...>   from: Zocam.Point.month(:may),
    ...>   until: Zocam.Point.month(:may),
    ...>   left: :open,
    ...>   right: :open
    ...> )
    {:union, []}

On the `:absolute` scope there is no cycle to wrap in, so backward
bounds raise instead:

    iex> Zocam.Span.arc!(from: Zocam.Point.year(2027), until: Zocam.Point.year(2026))
    ** (ArgumentError) absolute bounds run backward: [year: 2027] is after [year: 2026]. The timeline has no cycle to wrap in; swap the bounds.

A bare integer step at `:time` grain is rejected — `Time` has no
unit cell, so the unit must be explicit:

    iex> Zocam.Span.arc!(
    ...>   from: Zocam.Point.time(~T[09:00:00]),
    ...>   until: Zocam.Point.time(~T[17:00:00]),
    ...>   step: 2
    ...> )
    ** (ArgumentError) a bare integer step counts grain units, and :time has no unit cell. Give the unit explicitly: {2, :minute}, {2, :hour}, ...

### `complement`

```elixir
@spec complement(t()) :: t()
```

Everything outside the given span.

    iex> not_may = Zocam.Span.complement(Zocam.Span.of(Zocam.Point.month(:may)))
    iex> Zocam.Span.member?(not_may, ~U[2026-05-15 12:00:00Z])
    false
    iex> Zocam.Span.member?(not_may, ~U[2026-06-15 12:00:00Z])
    true

A double complement collapses back to the original span:

    iex> may = Zocam.Span.of(Zocam.Point.month(:may))
    iex> Zocam.Span.complement(Zocam.Span.complement(may)) == may
    true

### `diff`

```elixir
@spec diff(t(), t()) :: t()
```

Set difference: `a` without `b`.

Defined as `intersection([a, complement(b)])`. One-versus-many and
many-versus-one are not special cases: "many" is already a union
value on either side. The linear kernel computes its own diff the
same way, so the two layers agree by construction.

Weekdays without Wednesdays — Jan 6 2026 is a Tuesday, Jan 7 a
Wednesday:

    iex> weekdays = Zocam.Span.arc!(
    ...>   from: Zocam.Point.weekday(:monday),
    ...>   until: Zocam.Point.weekday(:friday)
    ...> )
    iex> no_wednesdays = Zocam.Span.diff(weekdays, Zocam.Span.of(Zocam.Point.weekday(:wednesday)))
    iex> Zocam.Span.member?(no_wednesdays, ~U[2026-01-06 12:00:00Z])
    true
    iex> Zocam.Span.member?(no_wednesdays, ~U[2026-01-07 12:00:00Z])
    false

Subtracting nothing changes nothing — the empty span absorbs
instead of erasing:

    iex> may = Zocam.Span.of(Zocam.Point.month(:may))
    iex> Zocam.Span.diff(may, Zocam.Span.empty()) == may
    true

### `empty`

```elixir
@spec empty() :: t()
```

The empty set: a union of nothing.

    iex> Zocam.Span.empty()
    {:union, []}

### `empty?`

```elixir
@spec empty?(t(), horizon(), String.t()) :: boolean()
```

Does the span contain no instant inside the horizon?

February 2026 has four Wednesdays, so its "5th Wednesday" is empty
there — and not empty in April, which has five:

    iex> fifth_wed = Zocam.Span.of(Zocam.Point.day({:nth, 5, :wednesday}))
    iex> feb = %{from: ~U[2026-02-01 00:00:00Z], until: ~U[2026-03-01 00:00:00Z], left: :closed, right: :open}
    iex> Zocam.Span.empty?(fifth_wed, feb, "Etc/UTC")
    true
    iex> apr = %{from: ~U[2026-04-01 00:00:00Z], until: ~U[2026-05-01 00:00:00Z], left: :closed, right: :open}
    iex> Zocam.Span.empty?(fifth_wed, apr, "Etc/UTC")
    false

### `ground`

```elixir
@spec ground(t(), horizon(), String.t()) :: Zocam.Intervals.t()
```

Evaluate the span over a bounded horizon into the linear kernel.

Enumerates every scope instance that intersects the horizon,
grounds each fully (an instance may yield more than one kernel
interval on DST fall-back days), then clips to the horizon and
compresses. The horizon must be bounded on both sides: many spans
are infinite, so an unbounded ground cannot terminate — use
`stream/3` when there is no right bound.

#### Examples

The common call: one cyclic point, one bounded horizon, UTC.

    iex> may = Zocam.Span.of(Zocam.Point.month(:may))
    iex> horizon = %{
    ...>   from: ~U[2026-01-01 00:00:00Z],
    ...>   until: ~U[2027-01-01 00:00:00Z],
    ...>   left: :closed,
    ...>   right: :open
    ...> }
    iex> Zocam.Span.ground(may, horizon, "Etc/UTC").intervals
    [%{from: ~U[2026-05-01 00:00:00Z], until: ~U[2026-06-01 00:00:00Z], left: :closed, right: :open}]

The DST fold: on 2026-11-01, America/New_York sets its clocks
back, so the wall window 00:30..01:30 exists twice — once in EDT,
and partly again in EST. One instance grounds to *two* intervals:

    iex> night = Zocam.Span.arc!(
    ...>   from: Zocam.Point.time(~T[00:30:00]),
    ...>   until: Zocam.Point.time(~T[01:30:00])
    ...> )
    iex> fall_back = %{
    ...>   from: ~U[2026-11-01 00:00:00Z],
    ...>   until: ~U[2026-11-02 00:00:00Z],
    ...>   left: :closed,
    ...>   right: :open
    ...> }
    iex> Zocam.Span.ground(night, fall_back, "America/New_York").intervals
    [
      %{from: ~U[2026-11-01 04:30:00Z], until: ~U[2026-11-01 05:30:00Z], left: :closed, right: :open},
      %{from: ~U[2026-11-01 06:00:00Z], until: ~U[2026-11-01 06:30:00Z], left: :closed, right: :open}
    ]

The DST gap: on 2026-03-08 the wall time 02:30 never appears on a
New York clock, so that instance grounds to nothing:

    iex> spring = %{
    ...>   from: ~U[2026-03-08 00:00:00Z],
    ...>   until: ~U[2026-03-09 00:00:00Z],
    ...>   left: :closed,
    ...>   right: :open
    ...> }
    iex> Zocam.Span.ground(Zocam.Span.of(Zocam.Point.time(~T[02:30:00])), spring, "America/New_York").intervals
    []

### `intersection`

```elixir
@spec intersection([t()]) :: t()
```

The intersection of the given spans. `intersection([])` is
`universe/0`.

A cross-cycle intersection ("Wednesdays in May") has no finite
normal form before grounding, so the node holds it as data and the
two interpreters answer. May 6 2026 is a Wednesday; Apr 29 is a
Wednesday outside May:

    iex> weds_in_may = Zocam.Span.intersection([
    ...>   Zocam.Span.of(Zocam.Point.month(:may)),
    ...>   Zocam.Span.of(Zocam.Point.weekday(:wednesday))
    ...> ])
    iex> Zocam.Span.member?(weds_in_may, ~U[2026-05-06 12:00:00Z])
    true
    iex> Zocam.Span.member?(weds_in_may, ~U[2026-04-29 12:00:00Z])
    false

### `member?`

```elixir
@spec member?(t(), DateTime.t()) :: boolean()
```

Is the instant inside the set? Symbolic: no horizon, no
enumeration. Reads the wall clock of the given DateTime and applies
the same denotation as `ground/3`.

    iex> may = Zocam.Span.of(Zocam.Point.month(:may))
    iex> Zocam.Span.member?(may, ~U[2026-05-15 12:00:00Z])
    true

Clamping is part of the shared denotation, so the two interpreters
cannot disagree on it. February 2026 has 28 days; under the
default `:clamp` the 31st fires on Feb 28, and under `:skip` it
does not:

    iex> Zocam.Span.member?(Zocam.Span.of(Zocam.Point.day(31)), ~U[2026-02-28 12:00:00Z])
    true
    iex> literal_31st = Zocam.Point.new!(scope: :month, chain: [day: 31], overflow: :skip)
    iex> Zocam.Span.member?(Zocam.Span.of(literal_31st), ~U[2026-02-28 12:00:00Z])
    false

### `nth`

```elixir
@spec nth(n(), t(), [{:per, Zocam.Point.cycle()}]) :: t()
```

Ordinal selection: the `n`-th grain cell of `span` inside each
instance of the `per` cycle. Negative `n` counts from the end.

A missing ordinal skips the instance (no 5th Wednesday: nothing).
Grounding widens to whole `per` instances before counting, then
clips to the horizon, so a cut-off January never miscounts its
last Friday.

The inner span must be cyclic with day-sized grain cells: `nth`
counts days, and an `{:absolute, _}` node or a `:time`-grain leaf
has no day cells to count.

#### Examples

The last Friday of each month. January 2026 has Fridays on the
2nd, 9th, 16th, 23rd, and 30th:

    iex> last_friday = Zocam.Span.nth(-1, Zocam.Span.of(Zocam.Point.weekday(:friday)), per: :month)
    iex> Zocam.Span.member?(last_friday, ~U[2026-01-30 12:00:00Z])
    true
    iex> Zocam.Span.member?(last_friday, ~U[2026-01-23 12:00:00Z])
    false

The edge: a missing ordinal skips. February 2026 has four
Wednesdays, so its "5th Wednesday" names nothing — it does not
clamp onto the last one. April has five:

    iex> fifth_wed = Zocam.Span.nth(5, Zocam.Span.of(Zocam.Point.weekday(:wednesday)), per: :month)
    iex> Zocam.Span.member?(fifth_wed, ~U[2026-04-29 12:00:00Z])
    true
    iex> Zocam.Span.member?(fifth_wed, ~U[2026-02-25 12:00:00Z])
    false

The pitfall: "the first 09:00 of the month" reads well, but a
`:time`-grain span has no day cells to count. Select the day
first, then intersect with the time window:

    iex> Zocam.Span.nth(1, Zocam.Span.of(Zocam.Point.time(~T[09:00:00])), per: :month)
    ** (ArgumentError) nth/3 counts day cells; a :time-grain span has none. Select the day first, then intersect with the time window.

### `of`

```elixir
@spec of(Zocam.Point.t()) :: t()
```

Lift a point into the set algebra: the set of all instants the
point denotes (one grain-sized interval per scope instance).

The result is a one-arc node whose bounds are both the point's
chain, closed on both sides: "May" is the arc `May..May`.

    iex> may = Zocam.Span.of(Zocam.Point.month(:may))
    iex> match?({:arcs, :year, :month, [%Zocam.Span.Arc{}]}, may)
    true
    iex> Zocam.Span.member?(may, ~U[2026-05-15 12:00:00Z])
    true
    iex> Zocam.Span.member?(may, ~U[2026-06-01 00:00:00Z])
    false

### `stream`

```elixir
@spec stream(t(), DateTime.t(), String.t()) :: Enumerable.t()
```

Lazily enumerate the span's intervals from an instant forward, in
order. The stream grounds chunk by chunk (one year at a time, with
a one-year lookahead), so it works without a right bound; take
from it what you need.

The first two Wednesdays of 2026 fall on Jan 7 and Jan 14:

    iex> weds = Zocam.Span.of(Zocam.Point.weekday(:wednesday))
    iex> Zocam.Span.stream(weds, ~U[2026-01-01 00:00:00Z], "Etc/UTC") |> Enum.take(2)
    [
      %{from: ~U[2026-01-07 00:00:00Z], until: ~U[2026-01-08 00:00:00Z], left: :closed, right: :open},
      %{from: ~U[2026-01-14 00:00:00Z], until: ~U[2026-01-15 00:00:00Z], left: :closed, right: :open}
    ]

### `union`

```elixir
@spec union([t()]) :: t()
```

The union of the given spans. `union([])` is `empty/0`.

    iex> weekend = Zocam.Span.union([
    ...>   Zocam.Span.of(Zocam.Point.weekday(:saturday)),
    ...>   Zocam.Span.of(Zocam.Point.weekday(:sunday))
    ...> ])
    iex> Zocam.Span.member?(weekend, ~U[2026-01-10 12:00:00Z])
    true

The edge: same-cycle leaves merge eagerly. January and February
tile the year cycle side by side, so their union *is* the arc
`Jan..Feb` — one node, not two:

    iex> Zocam.Span.union([
    ...>   Zocam.Span.of(Zocam.Point.month(:january)),
    ...>   Zocam.Span.of(Zocam.Point.month(:february))
    ...> ]) == Zocam.Span.arc!(from: Zocam.Point.month(:january), until: Zocam.Point.month(:february))
    true

### `universe`

```elixir
@spec universe() :: t()
```

The whole timeline: an intersection of no constraints.

    iex> Zocam.Span.universe()
    {:intersection, []}

The two constants are dual under complement:

    iex> Zocam.Span.complement(Zocam.Span.empty()) == Zocam.Span.universe()
    true

---

*Consult [api-reference.md](api-reference.md) for complete listing*
