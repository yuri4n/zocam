---
title: "Zocam"
description: "A three-layer library for time: calendar things, sets of them, and concrete intervals."
---

[AI SLOP]{.ai-slop} An AI agent wrote the docstrings; `mix docs` generated this page. [yuri4n](https://github.com/yuri4n), a senior engineer, gave the direction and did the review. The review is human, thus errors can stay.

[Source on GitHub ↗](https://github.com/yuri4n/zocam/blob/main/lib/zocam.ex#L13){.source-link}

A three-layer library for time: calendar things, sets of them, and
concrete intervals.

## The layers

    Zocam.Point ──▶ Zocam.Span ──▶ Zocam.Intervals
    (calendar        (sets: arcs,     (linear kernel:
     things:          unions,          concrete interval
     "May",           steps,           sets on the real
     "the 23rd",      nth, ...)        timeline)
     "15:00")

- `Zocam.Point` models one "thing about time": concrete
  (`"May 2026"`) or abstract (`"May"`). Points compose:
  `"Jan"` + `"the 23rd"` = `"Jan 23, yearly"`.
- `Zocam.Span` models *sets* of instants built from points: arcs
  with closings and steps (`"Fri..Mon"`, `"every 15 minutes"`),
  unions, intersections, complements, and ordinal selection
  (`"last working day of the month"`). Its two interpreters are
  `Zocam.Span.member?/2` and `Zocam.Span.ground/3`.
- `Zocam.Intervals` is the linear kernel: concrete interval sets
  with union, intersection, complement, and difference. Everything
  a span grounds to lands here.

The calendar meets the real timeline in exactly one place:
`Zocam.Span.ground/3` resolves wall times in a timezone, which is
where DST folds (a wall hour that exists twice) and gaps (a wall
hour that never exists) are handled.

## One calendar

zocam reads and writes `Calendar.ISO` numbers only: `:january` is
month 1, `:monday` is weekday 1, and a year is a Gregorian year. A
`%Date{}`, `%Time{}`, `%NaiveDateTime{}`, or `%DateTime{}` on any
other calendar is refused at the function that takes it, with an
error that names the calendar and the repair. `Zocam.ISO` holds that
rule and lists every place it is applied.

## The four names

Four types carry all data in this library. Two questions place
each one. Question one: does the value hold *one piece* of time,
or a *set* of pieces? Question two: is the value *symbolic* (a
calendar shape that repeats, with no timezone), or *concrete* (a
window on the real timeline, timezone already resolved)?

|                          | one piece                  | a set of pieces      |
| ------------------------ | -------------------------- | -------------------- |
| **symbolic** (repeats)   | `Zocam.Span.Arc`           | `t:Zocam.Span.t/0`     |
| **concrete** (happens)   | `t:Zocam.Intervals.interval/0` | `t:Zocam.Intervals.t/0` |

### `Zocam.Span.Arc` — one symbolic piece

An arc is a struct: two bounds (`Zocam.Point` chains), one closing
per side, an optional step, and an overflow policy. It *repeats*:
"Fri..Mon" happens once in every week. An arc never travels alone —
it always sits inside an `{:arcs, scope, grain, arcs}` node of a
span, and the node owns the scope:

    iex> {:arcs, :week, :day, [arc]} =
    ...>   Zocam.Span.arc!(
    ...>     from: Zocam.Point.weekday(:friday),
    ...>     until: Zocam.Point.weekday(:monday)
    ...>   )
    iex> {arc.from, arc.until}
    {[weekday: :friday], [weekday: :monday]}

### `t:Zocam.Span.t/0` — a symbolic set

A span is not a struct. It is a recursive tagged tuple — the
expression tree of a set algebra: `{:arcs, ...}` leaves combined
with `{:union, ...}`, `{:intersection, ...}`, `{:complement, ...}`,
and `{:nth, ...}`. Even one point lifts to a one-arc *set*:

    iex> may = Zocam.Span.of(Zocam.Point.month(:may))
    iex> match?({:arcs, :year, :month, [%Zocam.Span.Arc{}]}, may)
    true

Why is the set primary, in both layers? Closure. The complement of
one arc is already two pieces, and a difference can cut one piece
into two. A lone piece cannot be closed under its own operators, so
every operator answers with a set.

### `t:Zocam.Intervals.interval/0` — one concrete piece

A plain map with exactly four keys: `%{from, until, left, right}`.
The endpoints are `Time` or `DateTime` values (or `nil` for an
unbounded ray). Nothing repeats here: this window happens once.
The `horizon` argument of `Zocam.Span.ground/3` is exactly one
such interval.

### `t:Zocam.Intervals.t/0` — a concrete set

The `%Zocam.Intervals{}` struct: a list of intervals, kept sorted
and disjoint by `Zocam.Intervals.compress/1`. An empty list inside
is the empty set. `Zocam.Span.ground/3` is the bridge from the
symbolic column to the concrete column — each arc instance lands as
0, 1, or 2 concrete pieces (a DST gap, a normal day, a DST fold):

    iex> weds = Zocam.Span.of(Zocam.Point.weekday(:wednesday))
    iex> may = Zocam.Span.of(Zocam.Point.month(:may))
    iex> span = Zocam.Span.intersection([weds, may])
    iex> horizon = %{
    ...>   from: ~U[2026-05-01 00:00:00Z],
    ...>   until: ~U[2026-06-01 00:00:00Z],
    ...>   left: :closed,
    ...>   right: :open
    ...> }
    iex> %Zocam.Intervals{intervals: intervals} =
    ...>   Zocam.Span.ground(span, horizon, "Etc/UTC")
    iex> length(intervals)
    4
    iex> hd(intervals).from
    ~U[2026-05-06 00:00:00Z]

### One rule for shapes: operations answer with the set

`Zocam.Intervals` accepts all three spellings of "some intervals" —
one bare map, a plain list, or the struct — and an operation on
sets always answers with the set struct, whatever shape the
operands came in. A piece constructor answers with a piece:
`Zocam.Intervals.new!/1` builds one interval map. So "nothing
remains" is always the empty set, never `nil`:

    iex> block = Zocam.Intervals.new!(from: ~T[09:00:00], until: ~T[17:00:00])
    iex> block
    %{from: ~T[09:00:00], until: ~T[17:00:00], left: :closed, right: :open}
    iex> Zocam.Intervals.diff(block, block)
    %Zocam.Intervals{intervals: []}
    iex> Zocam.Intervals.diff([block], [block])
    %Zocam.Intervals{intervals: []}

The design records (the ADR series) are not part of this API
reference. They live on the documentation site, at
[zocam.dev/design](https://zocam.dev/design), because each record is a
website page with its own diagrams. This reference documents the code;
the site documents the decisions behind it.

---

*Consult [api-reference.md](api-reference.md) for complete listing*

