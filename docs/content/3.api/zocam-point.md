---
title: "Zocam.Point"
description: "A calendar point: a concrete or abstract \"thing about time\"."
---

[AI SLOP]{.ai-slop} An AI agent wrote the docstrings; `mix docs` generated this page. [yuri4n](https://github.com/yuri4n), a senior engineer, gave the direction and did the review. The review is human, thus errors can stay.

[Source on GitHub ↗](https://github.com/yuri4n/zocam/blob/main/lib/zocam/point.ex#L9){.source-link}

A calendar point: a concrete or abstract "thing about time".

A point is a pair of a **scope** and a **chain**:

- The scope is the cycle in which the point repeats. `"May"` repeats
  each year, so its scope is `:year`. `"May 2026"` does not repeat:
  its scope is `:absolute`.
- The chain is a list of valued segments. It starts directly under
  the scope and descends, one unit at a time, to a **grain** (the
  size of what the point names).

Concrete and abstract are not two types. They are one field: a point
is concrete exactly when its scope is `:absolute`.

## The unit graph

Chains must follow the edges of this graph. The week branch is a
sibling of the month branch: weeks do not nest in months or years.

    :absolute ── year ──┬── month ── day ────┬── time
                        │                    │
                        └── week(1..53) ── weekday
                                             │
    :week (cycle) ────────────── weekday ────┴── time

Examples:

    "May"                  %Point{scope: :year,     chain: [month: :may]}
    "May 2026"             %Point{scope: :absolute, chain: [year: 2026, month: :may]}
    "the 23rd"             %Point{scope: :month,    chain: [day: 23]}
    "15:00"                %Point{scope: :day,      chain: [time: ~T[15:00:00]]}
    "a Wednesday"          %Point{scope: :week,     chain: [weekday: :wednesday]}
    "first Wed of Jan"     %Point{scope: :year,     chain: [month: :january, day: {:nth, 1, :wednesday}]}

## Composition

`compose/2` concatenates two chains. It is defined exactly when the
inner point repeats once per unit of what the outer point names:
the inner scope must be a plain cycle of the outer grain class (an
`{:every, ...}` inner repeats less often, so it is out). This is
composition of arrows in a category: units are the objects, points
are the arrows, and two arrows compose only where they meet.

When the guard fails, the meaning is usually a *set*, not a point.
`compose(may, at_15_00)` fails because the day is free between month
and time; the error hint names the escape hatch:
`Zocam.Span.intersection/1` ("15:00 of every day of May").

## Denotation

A point denotes one grain-sized interval per instance of its scope
cycle. `Zocam.Span.of/1` lifts a point into the set algebra,
where intervals, steps, and the set operators live.

This module is pure: no timezone, no Timex. The calendar meets the
real timeline only in `Zocam.Span.ground/3`.

## One calendar

A point stores two standard-library values that carry a calendar:
the `%Time{}` of a `:time` segment, and the `%Date{}` anchor of an
`{:every, k, cycle, anchor}` scope. Both must be on `Calendar.ISO`,
because `month_number/1`, `weekday_number/1`, and the cell
arithmetic in `Zocam.Span` all read ISO numbers. A value on another
calendar is refused by `new!/1` with an error that names the
calendar. See `Zocam.ISO`.

## Types

### `chain`

```elixir
@type chain() :: [segment(), ...]
```

### `cycle`

```elixir
@type cycle() :: :year | :month | :week | :day
```

### `day_index`

```elixir
@type day_index() :: 1..31 | -31..-1
```

### `grain_class`

```elixir
@type grain_class() :: :year | :month | :week | :day | :time
```

### `month`

```elixir
@type month() ::
  :january
  | :february
  | :march
  | :april
  | :may
  | :june
  | :july
  | :august
  | :september
  | :october
  | :november
  | :december
```

### `nth_weekday`

```elixir
@type nth_weekday() :: {:nth, 1..5 | -1, weekday()}
```

### `overflow`

```elixir
@type overflow() :: :clamp | :skip
```

### `scope`

```elixir
@type scope() :: :absolute | cycle() | {:every, pos_integer(), cycle(), Date.t()}
```

### `segment`

```elixir
@type segment() ::
  {:year, integer()}
  | {:month, month()}
  | {:week, 1..53}
  | {:day, day_index() | nth_weekday()}
  | {:weekday, weekday()}
  | {:time, Time.t()}
```

### `t`

```elixir
@type t() :: %Zocam.Point{chain: chain(), overflow: overflow(), scope: scope()}
```

A calendar point: a scope and a contiguous chain.

### `unit`

```elixir
@type unit() :: :year | :month | :week | :day | :weekday | :time
```

### `weekday`

```elixir
@type weekday() ::
  :monday | :tuesday | :wednesday | :thursday | :friday | :saturday | :sunday
```
## Functions

### `compose`

```elixir
@spec compose(t(), t()) :: {:ok, t()} | {:error, Zocam.Point.ComposeError.t()}
```

Compose two points: `outer` refined by `inner`.

Defined exactly when the inner scope is a *plain* cycle whose class
equals `grain_class(outer)`. The result keeps the outer scope and
appends the inner chain. "2026" refined by "May" is "May 2026":

    iex> Zocam.Point.compose(Zocam.Point.year(2026), Zocam.Point.month(:may))
    {:ok, %Zocam.Point{scope: :absolute, chain: [year: 2026, month: :may], overflow: :clamp}}

Sibling units share a class, so "a Wednesday" takes a time of day
(`:weekday` and `:day` are different units of the same class):

    iex> {:ok, wed_15} =
    ...>   Zocam.Point.compose(Zocam.Point.weekday(:wednesday), Zocam.Point.time(~T[15:00:00]))
    iex> wed_15.chain
    [weekday: :wednesday, time: ~T[15:00:00]]

The pitfall: "May at 15:00" looks like a point, but the day is free
between month and time, so the meaning is a set. The error carries
the runnable repair:

    iex> {:error, error} =
    ...>   Zocam.Point.compose(Zocam.Point.month(:may), Zocam.Point.time(~T[15:00:00]))
    iex> error.reason
    :grain_gap
    iex> error.hint
    "Build the set with Zocam.Span.intersection([Span.of(outer), Span.of(inner)])."

The edge: weeks nest in no month and in no year, so "a Wednesday
of 2026" does not compose either. That meaning is also a set:

    iex> {:error, error} =
    ...>   Zocam.Point.compose(Zocam.Point.year(2026), Zocam.Point.weekday(:wednesday))
    iex> error.reason
    :cross_cycle

When the pair does not compose, the failure names why (see
`ComposeError`):

- `:grain_gap` — the inner nests inside the outer grain, but a unit
  level is free in the middle. The meaning is a set.
- `:cross_cycle` — neither class nests in the other (weeks straddle
  month and year edges). The meaning is a set here too.
- `:invalid` — the chain would run backward or repeat a unit.
- `:anchored` — the inner scope is `{:every, k, cycle, anchor}`. It
  repeats once per *k* cycles, not once per cycle, and a chain has
  no place for that phase. Compose the plain points first, then
  re-scope the result with `every/3`. An every-scoped *outer* is
  fine: compose keeps the outer scope, phase included.

The composed point keeps the overflow policy of the operand whose
chain holds the day segment: overflow only means something where a
day number sits, and a composed chain holds at most one day
segment. When neither operand has one, the policy is inert and the
outer's is kept.

The `{:ok, _} | {:error, _}` shape is deliberate: the type checker
presses call sites to handle the failure. Use `compose!/2` in
pipelines that must raise.

### `compose!`

```elixir
@spec compose!(t(), t()) :: t()
```

Like `compose/2` but raises the `ComposeError`. Use it in a
pipeline that must stop on a failed composition.

    iex> Zocam.Point.compose!(Zocam.Point.month(:january), Zocam.Point.day(23)).chain
    [month: :january, day: 23]

"May of June" repeats a unit, so it raises:

    iex> Zocam.Point.compose!(Zocam.Point.month(:may), Zocam.Point.month(:june))
    ** (Zocam.Point.ComposeError) cannot compose [month: :may] (grain :month) with [month: :june] (repeats per :year): the chain would run backward or repeat a unit. Swap the operands, or drop the repeated unit.

### `day`

```elixir
@spec day(day_index() | nth_weekday()) :: t()
```

A day of the month: scope `:month`, grain class `:day`.

Accepts a day number (`23`), a negative index from the month end
(`-1` is the last day), or an ordinal weekday selector
(`{:nth, 1, :wednesday}` is the first Wednesday).

    iex> Zocam.Point.day(23).chain
    [day: 23]

    iex> Zocam.Point.day(-1).chain
    [day: -1]

    iex> Zocam.Point.day({:nth, 1, :wednesday}).chain
    [day: {:nth, 1, :wednesday}]

A day number *measures* into the month, so it clamps where the
month is short (see `t:overflow/0`). February 2026 has 28 days,
and "the 31st" still fires there:

    iex> Zocam.Span.member?(Zocam.Span.of(Zocam.Point.day(31)), ~U[2026-02-28 12:00:00Z])
    true

An ordinal *selects*, so a missing ordinal names nothing instead
(see `Zocam.Span.nth/3` for the same rule at the set level).

### `every`

```elixir
@spec every(t(), pos_integer(), Date.t()) :: t()
```

Re-scope a cyclic point to every `k`-th instance of its cycle,
counted from the instance that contains `anchor`. This is how a
fortnight enters the library: "every other Wednesday" is a `:week`
point re-scoped with `k = 2`.

Jan 7, 14, and 21 of 2026 are consecutive Wednesdays; only every
second one is in the set, in phase with the anchor:

    iex> fortnightly = Zocam.Point.every(Zocam.Point.weekday(:wednesday), 2, ~D[2026-01-07])
    iex> fortnightly.scope
    {:every, 2, :week, ~D[2026-01-07]}
    iex> Zocam.Span.member?(Zocam.Span.of(fortnightly), ~U[2026-01-07 12:00:00Z])
    true
    iex> Zocam.Span.member?(Zocam.Span.of(fortnightly), ~U[2026-01-14 12:00:00Z])
    false

The point's scope must be a plain cycle. An `:absolute` point does
not repeat:

    iex> Zocam.Point.every(Zocam.Point.year(2026), 2, ~D[2026-01-07])
    ** (ArgumentError) an :absolute point happens once, so it cannot repeat every 2 cycles. Give a cyclic point such as Point.weekday(:wednesday).

And re-anchoring an `{:every, ...}` scope must restate the rhythm
from the base cycle:

    iex> fortnightly = Zocam.Point.every(Zocam.Point.weekday(:wednesday), 2, ~D[2026-01-07])
    iex> Zocam.Point.every(fortnightly, 3, ~D[2026-02-04])
    ** (ArgumentError) this point already repeats every 2 week(s) from ~D[2026-01-07]. Nested anchors would hide which phase wins: restate the rhythm from the base :week cycle.

### `grain_class`

```elixir
@spec grain_class(t()) :: grain_class()
```

The class of the point's finest segment (what the point names).
Together with `scope_class/1` it places a point on the two type
axes; `compose/2` reads both to decide where two points meet.

    iex> Zocam.Point.grain_class(Zocam.Point.month(:may))
    :month

    iex> wed_15 = Zocam.Point.compose!(Zocam.Point.weekday(:wednesday), Zocam.Point.time(~T[15:00:00]))
    iex> Zocam.Point.grain_class(wed_15)
    :time

### `month`

```elixir
@spec month(month()) :: t()
```

A month of the year: scope `:year`, grain class `:month`.

    iex> Zocam.Point.month(:may)
    %Zocam.Point{scope: :year, chain: [month: :may], overflow: :clamp}

### `month_atom`

```elixir
@spec month_atom(1..12) :: month()
```

The month atom of a calendar number: 1 is `:january`, 12 is `:december`.

    iex> Zocam.Point.month_atom(12)
    :december

A number outside 1..12 raises the taught error (the converters take
run-time values, so they keep a fallback clause):

    iex> Zocam.Point.month_atom(13)
    ** (ArgumentError) not a valid value for :month: 13. Give a full-name month atom such as :may.

### `month_number`

```elixir
@spec month_number(month()) :: 1..12
```

The calendar number of a month atom: `:january` is 1, `:december` is 12.

    iex> Zocam.Point.month_number(:may)
    5

### `new!`

```elixir
@spec new!(scope: scope(), chain: chain(), overflow: overflow()) :: t()
```

Build a point and validate every invariant the types cannot hold:
the chain is non-empty, starts directly under the scope, follows the
unit graph edges without gaps, and every value is in range.

This is the single validation walk. All other functions trust it,
so build points with `new!/1` or the per-unit constructors, never
with raw structs.

#### Examples

Build "May", the month that repeats each year (the constructor
`month/1` is a shorthand for exactly this call):

    iex> Zocam.Point.new!(scope: :year, chain: [month: :may])
    %Zocam.Point{scope: :year, chain: [month: :may], overflow: :clamp}

The pitfall: a chain that skips a level. "The 23rd of 2026" looks
like a point, but a month is free between year and day, so the
meaning is a set of days, not one point:

    iex> Zocam.Point.new!(scope: :year, chain: [day: 23])
    ** (ArgumentError) unit :day cannot sit directly under :year: a chain descends the unit graph one level at a time, so the next unit must be one of [:month, :week]

`overflow:` decides what a too-large day number means (see
`t:overflow/0`). The policy acts in `Zocam.Span`, where the point
is evaluated. February 2026 has 28 days, so under `:skip` its
"31st" names nothing:

    iex> the_31st = Zocam.Point.new!(scope: :month, chain: [day: 31], overflow: :skip)
    iex> Zocam.Span.member?(Zocam.Span.of(the_31st), ~U[2026-02-28 12:00:00Z])
    false

### `scope_class`

```elixir
@spec scope_class(t()) :: :absolute | grain_class()
```

The class of the point's scope unit (what the point repeats in).

    iex> Zocam.Point.scope_class(Zocam.Point.month(:may))
    :year

    iex> Zocam.Point.scope_class(Zocam.Point.year(2026))
    :absolute

### `time`

```elixir
@spec time(Time.t()) :: t()
```

A time of the day: scope `:day`, grain class `:time`.

    iex> Zocam.Point.time(~T[15:00:00])
    %Zocam.Point{scope: :day, chain: [time: ~T[15:00:00]], overflow: :clamp}

### `week`

```elixir
@spec week(1..53) :: t()
```

An ISO week of the year (1..53): scope `:year`, grain class `:week`.

    iex> Zocam.Point.week(33)
    %Zocam.Point{scope: :year, chain: [week: 33], overflow: :clamp}

### `weekday`

```elixir
@spec weekday(weekday()) :: t()
```

A day of the week: scope `:week`, grain class `:day`.

    iex> Zocam.Point.weekday(:wednesday)
    %Zocam.Point{scope: :week, chain: [weekday: :wednesday], overflow: :clamp}

### `weekday_atom`

```elixir
@spec weekday_atom(1..7) :: weekday()
```

The weekday atom of an ISO number: 1 is `:monday`, 7 is `:sunday`.

    iex> Zocam.Point.weekday_atom(1)
    :monday

### `weekday_number`

```elixir
@spec weekday_number(weekday()) :: 1..7
```

The ISO number of a weekday atom: `:monday` is 1, `:sunday` is 7.

    iex> Zocam.Point.weekday_number(:sunday)
    7

### `year`

```elixir
@spec year(integer()) :: t()
```

The year `n`: scope `:absolute`, grain class `:year`.

    iex> Zocam.Point.year(2026)
    %Zocam.Point{scope: :absolute, chain: [year: 2026], overflow: :clamp}

---

*Consult [api-reference.md](api-reference.md) for complete listing*
