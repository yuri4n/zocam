---
title: "Zocam.Intervals"
description: "The linear kernel: sets of concrete intervals on one axis, with union, intersection, complement, and difference."
---

[AI SLOP]{.ai-slop} An AI agent wrote the docstrings; `mix docs` generated this page. [yuri4n](https://github.com/yuri4n), a senior engineer, gave the direction and did the review. The review is human, thus errors can stay.

[Source on GitHub ↗](https://github.com/yuri4n/zocam/blob/main/lib/zocam/intervals.ex#L7){.source-link}

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
until: nil, ...}` is the ray from `x` onward. A set of intervals is
the `%Zocam.Intervals{}` struct; `compress/1` keeps its list
sorted and free of overlaps, and the set operations both produce
and accept the empty list (the empty set).

Endpoints are `Time` (a daily wall window) or `DateTime` (a
concrete window). The two kinds do not mix inside one interval.
Abstract calendar values ("a Saturday", "May") do not live here:
they belong to `Zocam.Point`, and `Zocam.Span.ground/3` turns
them into the concrete intervals of this module.

This module is the bottom layer of the library:

    Zocam.Point ──▶ Zocam.Span ──▶ Zocam.Intervals  (this module)

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

### `interval_opt`

```elixir
@type interval_opt() :: {:interval, interval_opts()}
```

### `interval_opts`

```elixir
@type interval_opts() :: only_from() | only_until() | both()
```

### `new_opts`

```elixir
@type new_opts() :: interval_opt()
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
An empty list inside is the empty set. This is what
`Zocam.Span.ground/3` returns. The symbolic counterpart is
`t:Zocam.Span.t/0`.

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
@type valid_intervals() :: [interval_opt() | interval()] | t()
```
## Functions

### `check_and_extract_as_list!`

```elixir
@spec check_and_extract_as_list!(valid_interval() | valid_intervals()) :: [interval()]
```

Normalize any accepted shape (a struct, an interval map, option
lists, a mixed list, `{left, right}` pairs, `nil`, `[]`) into a
plain list of interval maps. This is the funnel every set operation
pours its input through, so each operation handles ONE shape.

### `check_interval_opts!`

```elixir
@spec check_interval_opts!(interval_opts()) :: interval_opts()
```

Check one interval option list: `from`/`until`/`left`/`right` at
most once each, and at least one of `from`/`until` present. Returns
the options unchanged; raises `ArgumentError` otherwise.

### `check_new_opts!`

```elixir
@spec check_new_opts!([new_opts()] | interval_opts()) ::
  [new_opts()] | interval_opts()
```

Check the options for `new!/1`. Two forms are legal: a root-level
interval (`from:`/`until:` directly in the list) or one or more
`interval:` entries. Mixing the two forms raises, and every
`interval:` entry is checked with `check_interval_opts!/1`.

### `complement`

```elixir
@spec complement(interval()) :: interval() | {interval(), interval()} | nil
@spec complement(t()) :: t()
@spec complement(at_least_one_valid()) :: [interval()]
```

Everything outside the operand. One bounded interval complements
to two rays (a `{left_ray, right_ray}` pair); a half-unbounded one
to a single ray; the whole timeline to `nil`; the empty set to the
whole timeline. Each boundary closing flips (see
`opposite_closing/1`): the instants `[a, b]` covers are exactly
the instants `(-inf, a)` and `(b, +inf)` miss.

### `completely_before?`

```elixir
@spec completely_before?(interval(), interval()) :: boolean()
```

Is `lhs` entirely before `rhs`, with no shared instant? Touching
endpoints count as "before" only when at least one side is `:open`
(the shared instant then belongs to at most one of them).

### `compress`

```elixir
@spec compress(t()) :: t()
@spec compress([interval()]) :: [interval()]
```

Bring a set into its normal form: fuse everything that overlaps or
touches, then sort by the left endpoint (`nil` first: an unbounded
left side starts before everything). Two sets with the same
content compress to the same list, which makes normal forms
comparable with `==`.

### `diff`

```elixir
@spec diff(interval(), interval()) :: interval() | {interval(), interval()} | nil
@spec diff(t(), at_least_one_valid()) :: t()
@spec diff(at_least_one_valid(), at_least_one_valid()) :: [interval()]
```

Set difference: the instants of `this` that are not in `other`.
Computed as `this` intersected with the complement of `other`, so
the three operations stay consistent by construction. Subtracting
a middle slice cuts one interval into two; on sets the subtrahends
subtract one after the other from what remains.

### `intersect`

```elixir
@spec intersect(interval(), interval()) :: interval() | nil
@spec intersect(t(), at_least_one_valid()) :: t()
@spec intersect(at_least_one_valid(), at_least_one_valid()) :: [interval()]
```

The instants shared by both operands. On two single intervals the
result is one interval or `nil`; on sets it is the compressed set
of all pairwise intersections. The tighter bound wins on each
side, closing included: `[a, b]` meets `(a, c)` in `(a, b]`.

### `interval_from_opts`

```elixir
@spec interval_from_opts(interval_opts()) :: interval()
```

Build the interval map from an option list. A missing side stays
`nil` (unbounded). The default closings are `:closed` on the left
and `:open` on the right, the half-open convention that lets
adjacent intervals tile without overlap; an absent side gets `nil`.

### `is_interval`

*macro*

### `new!`

```elixir
@spec new!([new_opts()] | interval_opts()) :: t()
```

Build a compressed interval set from options:

    new!(from: ~T[09:00:00], until: ~T[17:00:00])
    new!(interval: [from: a, until: b], interval: [from: c, until: d])

Raises `ArgumentError` on an empty or mixed specification. The
result is already in normal form (see `compress/1`).

### `overlaps?`

```elixir
@spec overlaps?(interval(), interval()) :: boolean()
@spec overlaps?(valid_interval(), valid_interval() | valid_intervals()) :: boolean()
```

Do the two operands share at least one instant? Both operands may
be single intervals or whole sets; two sets overlap when any pair
of their members does.

### `union`

```elixir
@spec union([interval()]) :: [interval()]
```

Union a list of intervals into a minimal list: overlapping and
touching members fuse into one spanning interval. The result is
not sorted; `compress/1` also sorts.

This is a fold of `union/2` over the list.

### `union`

```elixir
@spec union([interval()], interval()) :: [interval()]
```

Add one interval to a list that is already minimal, and keep it
minimal: every member that overlaps or touches `new_ival` fuses
with it into one spanning interval.

This is the fold step of `union/1`. Use it directly when the
intervals arrive one by one. The result is not sorted.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
