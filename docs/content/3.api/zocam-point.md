---
title: "Zocam.Point"
description: "A calendar point: a concrete or abstract \"thing about time\"."
---

[AI SLOP]{.ai-slop} An AI agent wrote the docstrings; `mix docs` generated this page. [yuri4n](https://github.com/yuri4n), a senior engineer, gave the direction and did the review. The review is human, thus errors can stay.

[Source on GitHub ↗](https://github.com/yuri4n/zocam/blob/main/lib/zocam/point.ex#L7){.source-link}

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
appends the inner chain:

    compose(year(2026), month(:may))
    #=> {:ok, %Point{scope: :absolute, chain: [year: 2026, month: :may]}}

    compose(month(:may), time(~T[15:00:00]))
    #=> {:error, %ComposeError{reason: :grain_gap, hint: "... Span.intersection ..."}}

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

Like `compose/2` but raises the `ComposeError`.

### `day`

```elixir
@spec day(day_index() | nth_weekday()) :: t()
```

A day of the month: scope `:month`, grain class `:day`.

Accepts a day number (`23`), a negative index from the month end
(`-1` is the last day), or an ordinal weekday selector
(`{:nth, 1, :wednesday}` is the first Wednesday).

### `every`

```elixir
@spec every(t(), pos_integer(), Date.t()) :: t()
```

Re-scope a cyclic point to every `k`-th instance of its cycle,
counted from the instance that contains `anchor`.

    weekday(:wednesday) |> every(2, ~D[2026-01-07])
    #=> "every other Wednesday", in phase with Jan 7 2026

The point's scope must be a plain cycle: an `:absolute` point does
not repeat, and re-anchoring an `{:every, ...}` scope must restate
it from the base cycle.

### `grain_class`

```elixir
@spec grain_class(t()) :: grain_class()
```

The class of the point's finest segment (what the point names).

### `month`

```elixir
@spec month(month()) :: t()
```

A month of the year: scope `:year`, grain class `:month`.

### `month_atom`

```elixir
@spec month_atom(1..12) :: month()
```

The month atom of a calendar number: 1 is `:january`, 12 is `:december`.

### `month_number`

```elixir
@spec month_number(month()) :: 1..12
```

The calendar number of a month atom: `:january` is 1, `:december` is 12.

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

### `scope_class`

```elixir
@spec scope_class(t()) :: :absolute | grain_class()
```

The class of the point's scope unit (what the point repeats in).

### `time`

```elixir
@spec time(Time.t()) :: t()
```

A time of the day: scope `:day`, grain class `:time`.

### `week`

```elixir
@spec week(1..53) :: t()
```

An ISO week of the year (1..53): scope `:year`, grain class `:week`.

### `weekday`

```elixir
@spec weekday(weekday()) :: t()
```

A day of the week: scope `:week`, grain class `:day`.

### `weekday_atom`

```elixir
@spec weekday_atom(1..7) :: weekday()
```

The weekday atom of an ISO number: 1 is `:monday`, 7 is `:sunday`.

### `weekday_number`

```elixir
@spec weekday_number(weekday()) :: 1..7
```

The ISO number of a weekday atom: `:monday` is 1, `:sunday` is 7.

### `year`

```elixir
@spec year(integer()) :: t()
```

The year `n`: scope `:absolute`, grain class `:year`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
