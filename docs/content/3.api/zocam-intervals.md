---
title: "Zocam.Intervals"
description: "The linear kernel: sets of concrete intervals on one axis, with union, intersection, complement, and difference."
---

[AI SLOP]{.ai-slop} An AI agent wrote the docstrings; `mix docs` generated this page. [yuri4n](https://github.com/yuri4n), a senior engineer, gave the direction and did the review. The review is human, thus errors can stay.

[Source on GitHub ↗](https://github.com/yuri4n/zocam/blob/main/lib/zocam/intervals.ex#L16){.source-link}

The linear kernel: sets of concrete intervals on one axis, with
union, intersection, complement, and difference.

An interval is a plain map with four keys:

    %{from: a, until: b, left: :closed, right: :open}

     from                       until
      │<────────── span ──────────>│
      ●────────────────────────────○
      left: :closed                right: :open
      (a is inside)                (b is outside)

A `nil` endpoint means "unbounded on this side": `%{from: x,
until: nil, ...}` is the ray from `x` onward. A set of intervals
is the `%Zocam.Intervals{}` struct; `compress/1` keeps its list
sorted and free of overlaps, and the bare literal
`%Zocam.Intervals{}` is the empty set.

## One rule for shapes

An operation on sets answers with a set; a piece constructor
answers with a piece. `union/2`, `intersect/2`, `diff/2`,
`complement/1`, and `compress/1` accept a piece (a map or an
option list), a list of pieces, or the struct — and always answer
with the struct. `new!/1` builds one piece and answers with the
piece. `overlaps?/2` asks a question and answers with a boolean.

Endpoints are `Time` (a daily wall window) or `DateTime` (a
concrete window). The two kinds do not mix inside one interval.
Abstract calendar values ("a Saturday", "May") do not live here:
they belong to `Zocam.Point`, and `Zocam.Span.ground/3` turns
them into the concrete intervals of this module.

This module is the bottom layer of the library:

    Zocam.Point ──▶ Zocam.Span ──▶ Zocam.Intervals  (this module)

A grounded span lands here, so the kernel operations compose with
the calendar layers. Cut a busy morning out of a grounded
Wednesday (Jan 7 2026 is a Wednesday):

    iex> weds = Zocam.Span.of(Zocam.Point.weekday(:wednesday))
    iex> horizon = %{from: ~U[2026-01-05 00:00:00Z], until: ~U[2026-01-12 00:00:00Z], left: :closed, right: :open}
    iex> week = Zocam.Span.ground(weds, horizon, "Etc/UTC")
    iex> busy = [%{from: ~U[2026-01-07 00:00:00Z], until: ~U[2026-01-07 12:00:00Z], left: :closed, right: :open}]
    iex> Zocam.Intervals.diff(week, busy).intervals
    [%{from: ~U[2026-01-07 12:00:00Z], until: ~U[2026-01-08 00:00:00Z], left: :closed, right: :open}]

## Enumerate a set

A set is one value that holds pieces, so `Enum` walks it: the
struct implements `Enumerable` and yields its concrete
`interval/0` pieces, in normal-form order.

The common call — read one field off every piece:

    iex> free = Zocam.Intervals.diff(
    ...>   Zocam.Intervals.new!(from: ~T[08:00:00], until: ~T[18:00:00]),
    ...>   [%{from: ~T[09:00:00], until: ~T[10:00:00], left: :closed, right: :open}]
    ...> )
    iex> Enum.map(free, & &1.from)
    [~T[08:00:00], ~T[10:00:00]]

The pitfall: `Enum.member?/2` asks "is this value one of the
pieces in the list?" — it does NOT ask "is this instant covered by
the set?". An instant inside a piece is still not a piece:

    iex> jan7 = Zocam.Intervals.compress([
    ...>   [from: ~U[2026-01-07 00:00:00Z], until: ~U[2026-01-08 00:00:00Z]]
    ...> ])
    iex> Enum.member?(jan7, ~U[2026-01-07 12:00:00Z])
    false

To ask about coverage, keep the span and ask `Zocam.Span.member?/2`.

The edge: the empty set enumerates to nothing.

    iex> Enum.to_list(%Zocam.Intervals{})
    []

The integrated use — ground a span, then walk the result:

    iex> weds = Zocam.Span.of(Zocam.Point.weekday(:wednesday))
    iex> horizon = %{from: ~U[2026-01-05 00:00:00Z], until: ~U[2026-01-19 00:00:00Z], left: :closed, right: :open}
    iex> Zocam.Span.ground(weds, horizon, "Etc/UTC") |> Enum.map(& &1.from)
    [~U[2026-01-07 00:00:00Z], ~U[2026-01-14 00:00:00Z]]

## Types

### `at_least_one_valid`

```elixir
@type at_least_one_valid() :: valid_interval() | valid_intervals()
```

### `both`

```elixir
@type both() :: [
  from: timables(),
  until: timables(),
  left: closing(),
  right: closing()
]
```

### `closing`

```elixir
@type closing() :: :open | :closed
```

### `interval`

```elixir
@type interval() :: %{
  from: timables() | nil,
  until: timables() | nil,
  left: closing() | nil,
  right: closing() | nil
}
```

One concrete piece of the timeline: a plain map with exactly four
keys. It happens once — nothing repeats here. A `nil` endpoint
means "unbounded on this side" (a ray). The symbolic counterpart
that *does* repeat is `Zocam.Span.Arc`.

### `interval_opts`

```elixir
@type interval_opts() :: only_from() | only_until() | both()
```

### `only_from`

```elixir
@type only_from() :: [from: timables(), left: closing(), right: closing()]
```

### `only_until`

```elixir
@type only_until() :: [until: timables(), left: closing(), right: closing()]
```

### `t`

```elixir
@type t() :: %Zocam.Intervals{intervals: [interval()]}
```

A concrete *set* of pieces: the struct wraps one list of
`interval/0` maps, which `compress/1` keeps sorted and disjoint.
An empty list inside is the empty set, and so is the bare
literal `%Zocam.Intervals{}`. This is what `Zocam.Span.ground/3`
returns. The symbolic counterpart is `t:Zocam.Span.t/0`.

### `timables`

```elixir
@type timables() :: Time.t() | DateTime.t()
```

### `valid_interval`

```elixir
@type valid_interval() :: interval_opts() | interval()
```

### `valid_intervals`

```elixir
@type valid_intervals() :: [interval() | interval_opts()] | t()
```
## Functions

### `check_and_extract_as_list!`

```elixir
@spec check_and_extract_as_list!(at_least_one_valid()) :: [interval()]
```

Normalize one operand into a plain list of interval maps. This is
the funnel: every set operation pours its operands through it, so
each operation handles exactly ONE shape, and every bad shape is
stopped in exactly one place.

The funnel accepts exactly these shapes:

- `%Zocam.Intervals{}` — a set; its pieces come out as the list.
- One interval map with the four keys `:from`, `:until`, `:left`,
  and `:right` — what `new!/1` builds.
- One keyword list of interval options (`from:`, `until:`,
  `left:`, `right:`).
- A list — empty, or holding interval maps and option lists in
  any mix.

Every other shape raises an `ArgumentError` that names the
rejected shape and the accepted ones. A map with only some of the
four keys is such a shape: it looks like an interval and is not.
A map with the four keys and extra keys beside them is rejected
too, and so is an improper list (`[a | b]` where `b` is not a
list): each looks like an operand and is not exactly one.

    iex> Zocam.Intervals.check_and_extract_as_list!(from: ~T[09:00:00], until: ~T[17:00:00])
    [%{from: ~T[09:00:00], until: ~T[17:00:00], left: :closed, right: :open}]

    iex> Zocam.Intervals.check_and_extract_as_list!(%Zocam.Intervals{})
    []

### `check_closings!`

```elixir
@spec check_closings!(interval()) :: interval()
```

Check the two closings, per side: a bounded side (endpoint
present) must be `:open` or `:closed`; an unbounded side (endpoint
`nil`) has no boundary, so its closing must be `nil`. Returns the
interval unchanged; raises `ArgumentError` otherwise.

Why per side? A "dead" closing on an unbounded side describes a
boundary that does not exist, and a bogus atom (`left: :half`)
silently behaves as `:open` in every comparison. Both are
mistakes the caller wants to hear about at the door.

This check is shared: `Zocam.Span` runs the same rule on its
absolute intervals, so the two layers cannot drift apart.

    iex> Zocam.Intervals.check_closings!(%{from: ~T[09:00:00], until: nil, left: :closed, right: nil})
    %{from: ~T[09:00:00], until: nil, left: :closed, right: nil}

    iex> Zocam.Intervals.check_closings!(%{from: ~T[09:00:00], until: nil, left: :half, right: nil})
    ** (ArgumentError) left: must be :open or :closed on a bounded side, nil on an unbounded side, got :half

### `check_endpoints!`

```elixir
@spec check_endpoints!(interval()) :: interval()
```

Check that each non-nil endpoint is a value the kernel can
compare: a `Time` or a `DateTime`. Returns the interval unchanged;
raises `ArgumentError` naming the side and the value otherwise.

Why so strict? The kernel orders endpoints with `Time.compare/2`
and `DateTime.compare/2`. A weekday atom crashes the first
comparison. A `NaiveDateTime` or a `Date` is worse: it "works",
but equality falls back to structural `==`, which misses equal
instants written differently — and then a real hole between two
intervals is silently unioned away.

    iex> Zocam.Intervals.check_endpoints!(%{from: ~T[09:00:00], until: nil, left: :closed, right: nil})
    %{from: ~T[09:00:00], until: nil, left: :closed, right: nil}

    iex> Zocam.Intervals.check_endpoints!(%{from: :saturday, until: nil, left: :closed, right: nil})
    ** (ArgumentError) from: must be a Time, a DateTime, or nil, got :saturday. Calendar values (:saturday, :may) belong to Zocam.Point, and Zocam.Span.ground/3 turns them into kernel intervals. A NaiveDateTime or a Date is rejected too: without a timezone it names no instant the kernel can compare.

### `check_interval_opts!`

```elixir
@spec check_interval_opts!(interval_opts()) :: interval_opts()
```

Check one interval option list: a proper keyword list, with
`from`/`until`/`left`/`right` at most once each, and at least one
of `from`/`until` present. Returns the options unchanged; raises
`ArgumentError` otherwise.

    iex> Zocam.Intervals.check_interval_opts!(from: ~T[09:00:00], from: ~T[10:00:00])
    ** (ArgumentError) Invalid options: from, until, left and right cannot be specified more than once

The pitfall: a stray element between the pairs is not an option.
The check names it instead of failing deep inside `Keyword`:

    iex> Zocam.Intervals.check_interval_opts!([{:from, ~T[09:00:00]}, :oops])
    ** (ArgumentError) Invalid options: an interval option list holds {key, value} pairs only, and :oops is not one. Got: [{:from, ~T[09:00:00]}, :oops]

### `check_order!`

```elixir
@spec check_order!(interval()) :: interval()
```

Check that the interval runs forward: when both endpoints are
present, `from` must not be strictly after `until`. Returns the
interval unchanged; raises `ArgumentError` otherwise.

Why so strict? An inverted interval covers no instant, but the
ordering helpers read it as "before itself", and every law of the
algebra breaks from there. The kernel is linear: a window that
crosses midnight is not one backward interval, it is a *wrapping
arc* — that concept lives one layer up, in `Zocam.Span.arc!/1`.

    iex> Zocam.Intervals.check_order!(%{from: ~T[06:00:00], until: ~T[22:00:00], left: :closed, right: :open})
    %{from: ~T[06:00:00], until: ~T[22:00:00], left: :closed, right: :open}

    iex> Zocam.Intervals.check_order!(%{from: ~T[22:00:00], until: ~T[06:00:00], left: :closed, right: :open})
    ** (ArgumentError) from ~T[22:00:00] is after until ~T[06:00:00]: an interval runs forward. For a window that crosses midnight, such as 22:00..06:00, build a wrapping arc with Zocam.Span.arc!/1 instead.

### `complement`

```elixir
@spec complement(at_least_one_valid()) :: t()
```

Everything outside the operand, as a set. Each boundary closing
flips (see `opposite_closing/1`): the instants `[a, b]` covers are
exactly the instants `(-inf, a)` and `(b, +inf)` miss. One bounded
interval complements to two rays:

    iex> Zocam.Intervals.complement(
    ...>   %{from: ~T[09:00:00], until: ~T[17:00:00], left: :closed, right: :open}
    ...> ).intervals
    [
      %{from: nil, until: ~T[09:00:00], left: nil, right: :open},
      %{from: ~T[17:00:00], until: nil, left: :closed, right: nil}
    ]

The edge: the empty set complements to the whole timeline — one
interval, unbounded on both sides:

    iex> Zocam.Intervals.complement([])
    %Zocam.Intervals{intervals: [%{from: nil, until: nil, left: nil, right: nil}]}

### `completely_before?`

```elixir
@spec completely_before?(interval(), interval()) :: boolean()
```

Is `lhs` entirely before `rhs`, with no shared instant? Touching
endpoints count as "before" only when at least one side is `:open`
(the shared instant then belongs to at most one of them).

    iex> Zocam.Intervals.completely_before?(
    ...>   %{from: ~T[09:00:00], until: ~T[12:00:00], left: :closed, right: :open},
    ...>   %{from: ~T[12:00:00], until: ~T[17:00:00], left: :closed, right: :open}
    ...> )
    true

### `compress`

```elixir
@spec compress(at_least_one_valid()) :: t()
```

Bring one operand into its normal form: drop every piece that
covers no instant (`[t, t)`, `(t, t)`, `(t, t]` — only the
single-point `[t, t]` survives), fuse everything that overlaps or
touches, then sort by the left endpoint (`nil` first: an unbounded
left side starts before everything). Two operands with the same
content compress to the same struct, which makes normal forms
comparable with `==`.

The edge: a zero-width piece with an open side holds nothing, so
compressing it alone gives the empty set:

    iex> Zocam.Intervals.compress([
    ...>   %{from: ~T[12:00:00], until: ~T[12:00:00], left: :closed, right: :open}
    ...> ])
    %Zocam.Intervals{intervals: []}

    iex> Zocam.Intervals.compress([
    ...>   %{from: ~T[13:00:00], until: ~T[17:00:00], left: :closed, right: :open},
    ...>   %{from: ~T[09:00:00], until: ~T[11:00:00], left: :closed, right: :open},
    ...>   %{from: ~T[10:00:00], until: ~T[13:00:00], left: :closed, right: :open}
    ...> ])
    %Zocam.Intervals{intervals: [%{from: ~T[09:00:00], until: ~T[17:00:00], left: :closed, right: :open}]}

The edge: equality of instants follows the clock, not the struct.
A different written precision is still the same instant — and here
both sides are `:open` at 10:00, so the one-instant hole survives:

    iex> Zocam.Intervals.compress([
    ...>   %{from: ~T[09:00:00], until: ~T[10:00:00], left: :open, right: :open},
    ...>   %{from: ~T[10:00:00.000000], until: ~T[11:00:00], left: :open, right: :open}
    ...> ]).intervals
    [
      %{from: ~T[09:00:00], until: ~T[10:00:00], left: :open, right: :open},
      %{from: ~T[10:00:00.000000], until: ~T[11:00:00], left: :open, right: :open}
    ]

### `diff`

```elixir
@spec diff(at_least_one_valid(), at_least_one_valid()) :: t()
```

Set difference: the instants of `this` that are not in `other`,
as a set. Computed piece by piece as `this` intersected with the
complement of `other`, so the three operations stay consistent by
construction.

#### Examples

The common call: cut the busy slots out of a working day. The
subtrahends subtract one after the other from what remains:

    iex> day = Zocam.Intervals.new!(from: ~T[08:00:00], until: ~T[18:00:00])
    iex> busy = [
    ...>   %{from: ~T[09:00:00], until: ~T[10:00:00], left: :closed, right: :open},
    ...>   %{from: ~T[12:00:00], until: ~T[13:00:00], left: :closed, right: :open}
    ...> ]
    iex> Zocam.Intervals.diff(day, busy).intervals
    [
      %{from: ~T[08:00:00], until: ~T[09:00:00], left: :closed, right: :open},
      %{from: ~T[10:00:00], until: ~T[12:00:00], left: :closed, right: :open},
      %{from: ~T[13:00:00], until: ~T[18:00:00], left: :closed, right: :open}
    ]

Subtracting a middle slice cuts one interval into two pieces of
one set:

    iex> block = %{from: ~T[09:00:00], until: ~T[17:00:00], left: :closed, right: :open}
    iex> Zocam.Intervals.diff(block, %{from: ~T[12:00:00], until: ~T[13:00:00], left: :closed, right: :open}).intervals
    [
      %{from: ~T[09:00:00], until: ~T[12:00:00], left: :closed, right: :open},
      %{from: ~T[13:00:00], until: ~T[17:00:00], left: :closed, right: :open}
    ]

The edge: "nothing remains" is the empty set — the struct with no
pieces, never `nil`:

    iex> block = %{from: ~T[09:00:00], until: ~T[17:00:00], left: :closed, right: :open}
    iex> Zocam.Intervals.diff(block, block)
    %Zocam.Intervals{intervals: []}

### `intersect`

```elixir
@spec intersect(at_least_one_valid(), at_least_one_valid()) :: t()
```

The instants shared by both operands, as a set. The tighter bound
wins on each side, closing included: `[a, b]` meets `(a, c)` in
`(a, b]`:

    iex> Zocam.Intervals.intersect(
    ...>   %{from: ~T[09:00:00], until: ~T[12:00:00], left: :closed, right: :closed},
    ...>   %{from: ~T[09:00:00], until: ~T[17:00:00], left: :open, right: :open}
    ...> )
    %Zocam.Intervals{intervals: [%{from: ~T[09:00:00], until: ~T[12:00:00], left: :open, right: :closed}]}

The edge: two operands that share nothing meet in the empty set —
the struct with no pieces, never `nil`:

    iex> Zocam.Intervals.intersect(
    ...>   %{from: ~T[09:00:00], until: ~T[12:00:00], left: :closed, right: :open},
    ...>   %{from: ~T[14:00:00], until: ~T[15:00:00], left: :closed, right: :open}
    ...> )
    %Zocam.Intervals{intervals: []}

### `interval_from_opts`

```elixir
@spec interval_from_opts(interval_opts()) :: interval()
```

Build the interval map from an option list. A missing side stays
`nil` (unbounded). The default closings are `:closed` on the left
and `:open` on the right, the half-open convention that lets
adjacent intervals tile without overlap; an absent side gets `nil`.

    iex> Zocam.Intervals.interval_from_opts(from: ~T[09:00:00])
    %{from: ~T[09:00:00], until: nil, left: :closed, right: nil}

### `is_interval`

*macro*

### `new!`

```elixir
@spec new!(interval_opts()) :: interval()
```

Build ONE interval — a piece, not a set. This is the piece
constructor: an operation on sets answers with a set, and a piece
constructor answers with a piece (see "One rule for shapes" in the
moduledoc).

The common call, with the default closings (`:closed` left,
`:open` right):

    iex> Zocam.Intervals.new!(from: ~T[09:00:00], until: ~T[17:00:00])
    %{from: ~T[09:00:00], until: ~T[17:00:00], left: :closed, right: :open}

The edge: a missing side stays `nil` — the piece is a ray:

    iex> Zocam.Intervals.new!(from: ~T[09:00:00])
    %{from: ~T[09:00:00], until: nil, left: :closed, right: nil}

The pitfall: `new!/1` does not build a set. To turn pieces into a
set, pour them through a set operation, for example `compress/1`:

    iex> Zocam.Intervals.compress([
    ...>   Zocam.Intervals.new!(from: ~T[09:00:00], until: ~T[12:00:00]),
    ...>   Zocam.Intervals.new!(from: ~T[12:00:00], until: ~T[17:00:00])
    ...> ])
    %Zocam.Intervals{intervals: [%{from: ~T[09:00:00], until: ~T[17:00:00], left: :closed, right: :open}]}

Raises `ArgumentError` on an empty specification:

    iex> Zocam.Intervals.new!([])
    ** (ArgumentError) Invalid options: from or until must be specified

### `overlaps?`

```elixir
@spec overlaps?(at_least_one_valid(), at_least_one_valid()) :: boolean()
```

Do the two operands share at least one instant? Both operands may
be pieces or whole sets (any funnel shape); two sets overlap when
any pair of their members does. This is a question, so the answer
is a boolean, not a set.

The pitfall: touching is not overlapping. `[09:00, 12:00)` and
`[12:00, 17:00)` tile without a shared instant, because the right
side is `:open`. Close it and the instant 12:00 is shared:

    iex> Zocam.Intervals.overlaps?(
    ...>   %{from: ~T[09:00:00], until: ~T[12:00:00], left: :closed, right: :open},
    ...>   %{from: ~T[12:00:00], until: ~T[17:00:00], left: :closed, right: :open}
    ...> )
    false

    iex> Zocam.Intervals.overlaps?(
    ...>   %{from: ~T[09:00:00], until: ~T[12:00:00], left: :closed, right: :closed},
    ...>   %{from: ~T[12:00:00], until: ~T[17:00:00], left: :closed, right: :open}
    ...> )
    true

### `union`

```elixir
@spec union(at_least_one_valid(), at_least_one_valid()) :: t()
```

The union of the two operands, as one normal-form set (see
`compress/1`): overlapping and touching pieces fuse into one
spanning interval.

    iex> Zocam.Intervals.union(
    ...>   %{from: ~T[09:00:00], until: ~T[11:00:00], left: :closed, right: :open},
    ...>   %{from: ~T[10:00:00], until: ~T[13:00:00], left: :closed, right: :open}
    ...> )
    %Zocam.Intervals{intervals: [%{from: ~T[09:00:00], until: ~T[13:00:00], left: :closed, right: :open}]}

Touching pieces fuse too, because the shared instant is covered:

    iex> Zocam.Intervals.union(
    ...>   [%{from: ~T[09:00:00], until: ~T[12:00:00], left: :closed, right: :open}],
    ...>   %{from: ~T[12:00:00], until: ~T[17:00:00], left: :closed, right: :open}
    ...> )
    %Zocam.Intervals{intervals: [%{from: ~T[09:00:00], until: ~T[17:00:00], left: :closed, right: :open}]}

The edge: when both touching sides are `:open`, the shared instant
is in neither interval. A hole of one instant remains, so the two
do not fuse:

    iex> Zocam.Intervals.union(
    ...>   [%{from: ~T[09:00:00], until: ~T[12:00:00], left: :open, right: :open}],
    ...>   %{from: ~T[12:00:00], until: ~T[17:00:00], left: :open, right: :open}
    ...> ).intervals |> length()
    2

---

*Consult [api-reference.md](api-reference.md) for complete listing*
