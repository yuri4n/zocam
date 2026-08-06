# [cursor-agent] Added 2026-08-06 (Linear YUR-83). The property test
# for the library's keystone law (ADR-005, "shared denotation"): for
# every span and every instant inside a bounded horizon, the symbolic
# interpreter member?/2 and the concrete interpreter ground/3 give
# one answer. YUR-78 was a counterexample at a spring-forward seam
# that the hand-written fixtures missed; this generator searches that
# space on every run. Per AGENTS.md, a property test checks an
# invariant with many generated inputs - the recipe rule does not
# apply here.
defmodule Zocam.SpanDenotationPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Zocam.Point
  alias Zocam.Span

  @weekdays [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]

  @months [
    :january,
    :february,
    :march,
    :april,
    :may,
    :june,
    :july,
    :august,
    :september,
    :october,
    :november,
    :december
  ]

  # Zones with different seam dates; UTC has no seams at all.
  @timezones ["Etc/UTC", "America/New_York", "Europe/Berlin"]

  # Days the horizon generator aims at: the 2026 DST seams of the two
  # zones above (spring forward and fall back), plus two plain days
  # far from any seam.
  @anchor_days [
    ~D[2026-03-08],
    ~D[2026-11-01],
    ~D[2026-03-29],
    ~D[2026-10-25],
    ~D[2026-01-15],
    ~D[2026-07-04]
  ]

  # ── Generators ─────────────────────────────────────────────────────

  # Whole minutes are enough: the seams cut on whole hours, and the
  # minute candidates cluster around a cut (00, 15, 30, 45, 59).
  defp time_gen do
    gen all(
          hour <- StreamData.integer(0..23),
          minute <- StreamData.member_of([0, 15, 30, 45, 59])
        ) do
      Time.new!(hour, minute, 0)
    end
  end

  defp point_gen do
    StreamData.one_of([
      StreamData.map(StreamData.member_of(@weekdays), &Point.weekday/1),
      StreamData.map(StreamData.integer(1..31), &Point.day/1),
      StreamData.map(StreamData.integer(-31..-1), &Point.day/1),
      StreamData.map(
        StreamData.tuple(
          {StreamData.member_of([1, 2, 3, 4, 5, -1]), StreamData.member_of(@weekdays)}
        ),
        fn {n, wd} -> Point.day({:nth, n, wd}) end
      ),
      StreamData.map(StreamData.member_of(@months), &Point.month/1),
      StreamData.map(time_gen(), &Point.time/1)
    ])
  end

  # A daily wall window. from > until wraps across midnight - a
  # feature of the arc, which the kernel alone would reject.
  defp time_arc_gen do
    gen all(
          from <- time_gen(),
          until <- time_gen(),
          Time.compare(from, until) != :eq
        ) do
      Span.arc!(from: Point.time(from), until: Point.time(until))
    end
  end

  # A weekday window; Fri..Mon walks through the week seam.
  defp weekday_arc_gen do
    gen all(
          from <- StreamData.member_of(@weekdays),
          until <- StreamData.member_of(@weekdays),
          from != until
        ) do
      Span.arc!(from: Point.weekday(from), until: Point.weekday(until))
    end
  end

  defp base_span_gen do
    StreamData.one_of([
      StreamData.map(point_gen(), &Span.of/1),
      time_arc_gen(),
      weekday_arc_gen()
    ])
  end

  # Compound spans: union, intersection, complement, diff, and nth
  # over the base shapes - one level deep, so a shrunken failure
  # stays readable.
  defp span_gen do
    base = base_span_gen()

    StreamData.one_of([
      base,
      StreamData.map(StreamData.list_of(base, length: 2), &Span.union/1),
      StreamData.map(StreamData.list_of(base, length: 2), &Span.intersection/1),
      StreamData.map(base, &Span.complement/1),
      StreamData.map(StreamData.tuple({base, base}), fn {a, b} -> Span.diff(a, b) end),
      StreamData.map(
        StreamData.tuple({StreamData.member_of([1, 2, -1]), StreamData.member_of(@weekdays)}),
        fn {n, wd} -> Span.nth(n, Span.of(Point.weekday(wd)), per: :month) end
      )
    ])
  end

  # A bounded UTC horizon of 1..10 days that starts 0..3 days before
  # an anchor, so a seam usually sits inside it.
  defp horizon_gen do
    gen all(
          anchor <- StreamData.member_of(@anchor_days),
          start_offset_days <- StreamData.integer(-3..0),
          width_days <- StreamData.integer(1..10)
        ) do
      from = DateTime.new!(Date.add(anchor, start_offset_days), ~T[00:00:00], "Etc/UTC")

      %{
        from: from,
        until: DateTime.add(from, width_days * 86_400, :second),
        left: :closed,
        right: :open
      }
    end
  end

  # ── The law ────────────────────────────────────────────────────────

  # Is the UTC instant covered by the grounded set? The closings
  # decide the boundary instants, exactly as the kernel means them.
  defp covered?(set, at) do
    Enum.any?(set, fn piece ->
      after_from =
        piece.from == nil or
          case DateTime.compare(at, piece.from) do
            :gt -> true
            :eq -> piece.left == :closed
            :lt -> false
          end

      before_until =
        piece.until == nil or
          case DateTime.compare(at, piece.until) do
            :lt -> true
            :eq -> piece.right == :closed
            :gt -> false
          end

      after_from and before_until
    end)
  end

  # Probe instants: uniform picks inside the horizon, plus every
  # piece edge and its one-second neighbours - YUR-78 lived exactly
  # on such an edge. All probes stay inside the horizon [from, until).
  defp probes(set, horizon, offsets) do
    width = DateTime.diff(horizon.until, horizon.from, :second)

    uniform = Enum.map(offsets, &DateTime.add(horizon.from, rem(&1, width), :second))

    edges =
      set
      |> Enum.flat_map(fn piece -> [piece.from, piece.until] end)
      |> Enum.reject(&is_nil/1)
      |> Enum.flat_map(fn edge ->
        [DateTime.add(edge, -1, :second), edge, DateTime.add(edge, 1, :second)]
      end)

    Enum.filter(uniform ++ edges, fn at ->
      DateTime.compare(at, horizon.from) in [:gt, :eq] and
        DateTime.compare(at, horizon.until) == :lt
    end)
  end

  property "member?/2 and ground/3 read one denotation (ADR-005)" do
    check all(
            tz <- StreamData.member_of(@timezones),
            span <- span_gen(),
            horizon <- horizon_gen(),
            offsets <- StreamData.list_of(StreamData.integer(0..863_999), length: 8),
            max_runs: 120
          ) do
      set = Span.ground(span, horizon, tz)

      for at <- probes(set, horizon, offsets) do
        # member?/2 reads the wall clock, so the probe shifts into
        # the zone first; ground/3 answers in UTC, so coverage is
        # checked on the unshifted instant.
        wall = DateTime.shift_zone!(at, tz, Tzdata.TimeZoneDatabase)

        assert Span.member?(span, wall) == covered?(set, at),
               "member?/2 and ground/3 disagree at #{at} (wall #{wall}) " <>
                 "in #{tz} for span: #{inspect(span)}"
      end
    end
  end
end
