---
title: "Zocam.ISO"
description: "One calendar, checked at the door: Calendar.ISO."
---

[AI SLOP]{.ai-slop} An AI agent wrote the docstrings; `mix docs` generated this page. [yuri4n](https://github.com/yuri4n), a senior engineer, gave the direction and did the review. The review is human, thus errors can stay.

[Source on GitHub ↗](https://github.com/yuri4n/zocam/blob/main/lib/zocam/iso.ex#L3){.source-link}

One calendar, checked at the door: `Calendar.ISO`.

Every number in this library is an ISO number. `Zocam.Point` maps
`:january` to 1 and `:monday` to 1. `Zocam.Span` then does cell
arithmetic on those numbers. A `%Date{}` or a `%Time{}` on a
different calendar has the same *shape*, thus it matches a `%Date{}`
pattern, but its numbers mean something else. Before this module
existed, such a value was accepted and the library gave a wrong
answer with no crash and no warning.

This module holds the assumption in one place. Each function that
takes a calendar value from the caller calls `check!/2` before any
number is read.

## Why identity, and not compatibility

The standard library has a weaker test,
`Calendar.compatible_calendars?/2`: two calendars are compatible when
they agree on the structure of a day and of a time. That is not
sufficient here, because compatible calendars can still *number*
differently. The Holocene calendar in Elixir's own test suite is
compatible with ISO and writes the year 2026 as 12026. zocam reads
the number, thus only `Calendar.ISO` itself is safe.

The price is that a calendar which agrees with ISO in every number is
refused too. Nothing in this tree builds one, so the price is zero.

## Where the doors are

    Zocam.Point.time/1,  Point.new!/1  ── the :time segment
    Zocam.Point.every/3, Point.new!/1  ── the {:every, ...} anchor
    Zocam.Span.absolute!/1             ── both bounds
    Zocam.Span.ground/3, empty?/3      ── both horizon bounds
    Zocam.Span.member?/2               ── the instant
    Zocam.Span.stream/3                ── the start instant

An arc bound is a `Zocam.Point`, thus the two Point doors already
cover it. `Zocam.Intervals` is the linear kernel: it compares
instants and never reads a calendar number, so it needs no door.

## Types

### `calendared`

```elixir
@type calendared() :: Date.t() | Time.t() | NaiveDateTime.t() | DateTime.t()
```

A standard-library value that carries a `:calendar` field. These four
are the only values that can enter zocam with a calendar attached.
## Functions

### `check!`

```elixir
@spec check!(calendared(), String.t()) :: :ok
```

Answer `:ok` when the value is on `Calendar.ISO`, or raise an
`ArgumentError` that names the place, the calendar, and the repair.

`where` is a short phrase that names the place in the caller's own
words, such as `"the every/3 anchor"`. It opens the message, so write
it as the subject of a sentence.

    iex> Zocam.ISO.check!(~T[09:00:00], "the :time segment")
    :ok

    iex> Zocam.ISO.check!(~U[2026-05-15 09:00:00Z], "the horizon")
    :ok

A value on any other calendar raises. The repair names the converter
of the value's own type:

    iex> Zocam.ISO.check!(%Date{calendar: Holocene, year: 12026, month: 5, day: 15}, "the anchor")
    ** (ArgumentError) the anchor is on Holocene, but zocam reads every calendar number as ISO. Convert it first: Date.convert!(value, Calendar.ISO).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
