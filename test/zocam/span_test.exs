# [claude-code] Span tests. All Span functions are implemented; the old
# "draft stubs" tests are gone and the backlog tests now run by default.
# All calendar facts in the fixtures are machine-verified for 2026
# (Jan 7/14/21/28 = Wednesdays, Jan Fridays = 2/9/16/23/30, Feb has 28
# days and four Wednesdays 4/11/18/25, Apr Wednesdays = 1/8/15/22/29,
# Apr 30 = Thursday, May 29 = Friday, May 31 = Sunday, Dec 30 = Wednesday,
# US DST 2026: spring forward Mar 8, fall back Nov 1).
# Extended (2026-08-05) with the facts the doctests add: Jan 6 = Tuesday,
# Jan 10 = Saturday, May Wednesdays = 6/13/20/27.
defmodule Zocam.SpanTest do
  use ExUnit.Case, async: true

  # [claude-code] Added (2026-08-05): runs the doctests in the Span
  # docstrings, the moduledoc recipes included. The doctests reuse the
  # machine-verified 2026 facts above.
  doctest Zocam.Span

  # [claude-code] Added (2026-08-05, decision D1): runs the doctests
  # of the "Enumerate an arc" section in the Arc moduledoc.
  doctest Zocam.Span.Arc

  alias Zocam.{Point, Span}

  @utc "Etc/UTC"
  @new_york "America/New_York"

  defp horizon(from, until) do
    %{from: from, until: until, left: :closed, right: :open}
  end

  defp year_2026, do: horizon(~U[2026-01-01 00:00:00Z], ~U[2027-01-01 00:00:00Z])

  describe "canonical values" do
    test "the empty set is a union of nothing, the universe an intersection of no constraints" do
      assert Span.empty() == {:union, []}
      assert Span.universe() == {:intersection, []}
    end
  end

  describe "algebra laws" do
    test "union([]) and intersection([]) collapse to the canonical constants" do
      assert Span.union([]) == Span.empty()
      assert Span.intersection([]) == Span.universe()
    end

    test "empty and universe absorb correctly through the operators" do
      may = Span.of(Point.month(:may))

      # Without these laws a naive fold makes diff(a, empty) return
      # empty - the worst wrong answer for the operator the user
      # singled out.
      assert Span.diff(may, Span.empty()) == may
      assert Span.union([may, Span.empty()]) == may
      assert Span.intersection([may, Span.universe()]) == may
      assert Span.complement(Span.empty()) == Span.universe()
    end

    test "a double complement collapses" do
      may = Span.of(Point.month(:may))

      assert Span.complement(Span.complement(may)) == may
    end

    test "member? on the universe is always true" do
      assert Span.member?(Span.universe(), ~U[2026-05-15 12:00:00Z])
    end

    test "union merges touching same-cycle leaves into one compacted arc node" do
      # Jan and Feb tile the year cycle side by side, so the union is
      # ONE arc Jan..Feb - the "no overlapping intervals" invariant.
      jan_feb =
        Span.union([Span.of(Point.month(:january)), Span.of(Point.month(:february))])

      assert jan_feb ==
               Span.arc!(
                 from: Point.month(:january),
                 until: Point.month(:february),
                 left: :closed,
                 right: :closed
               )
    end
  end

  describe "arcs" do
    test "arc!/1 rejects bounds of different form" do
      # "May .. 15:00" is not an arc: the bounds live in different
      # cycles.
      assert_raise ArgumentError, fn ->
        Span.arc!(from: Point.month(:may), until: Point.time(~T[15:00:00]))
      end
    end

    test "arc!/1 requires both bounds" do
      # A cycle has no first or last unit to default to. Unbounded
      # sides belong to absolute!/1, where the timeline provides them.
      assert_raise ArgumentError, fn -> Span.arc!(from: Point.month(:may)) end
      assert_raise ArgumentError, fn -> Span.arc!(until: Point.month(:may)) end
    end

    test "from == until names the single unit; open sides exclude it wholly" do
      # closed-closed May..May is just May...
      may = Span.arc!(from: Point.month(:may), until: Point.month(:may))
      assert Span.member?(may, ~U[2026-05-15 12:00:00Z])
      refute Span.member?(may, ~U[2026-06-01 00:00:00Z])

      # ...and open-open is empty, never "everything except May".
      # Wrap is decided at the chain level, before closings expand.
      assert Span.arc!(
               from: Point.month(:may),
               until: Point.month(:may),
               left: :open,
               right: :open
             ) == Span.empty()
    end

    test "a wrap-around arc keeps its outer closings and stays whole at the seam" do
      # Nov..Feb, right-open: all of Nov, Dec, Jan; February excluded
      # entirely by the whole-unit :open. December must NOT fall into
      # the seam (the naive split would copy :open onto the Dec side).
      winter =
        Span.arc!(
          from: Point.month(:november),
          until: Point.month(:february),
          left: :closed,
          right: :open
        )

      assert Span.member?(winter, ~U[2026-12-15 12:00:00Z])
      assert Span.member?(winter, ~U[2027-01-15 12:00:00Z])
      refute Span.member?(winter, ~U[2027-02-15 12:00:00Z])

      grounded =
        Span.ground(winter, horizon(~U[2026-07-01 00:00:00Z], ~U[2027-07-01 00:00:00Z]), @utc)

      # The two split pieces re-fuse across the year seam.
      assert [%{from: ~U[2026-11-01 00:00:00Z], until: ~U[2027-02-01 00:00:00Z]}] =
               grounded.intervals
    end

    test "a step samples through the wrap seam, not per split piece" do
      # Fri..Mon step 2 = {Fri, Sun}. A split that restarts the phase
      # at the seam would wrongly include Monday.
      # 2026-01-09 = Friday, 10 = Saturday, 11 = Sunday, 12 = Monday.
      weekend_alt =
        Span.arc!(
          from: Point.weekday(:friday),
          until: Point.weekday(:monday),
          step: {2, :day}
        )

      assert Span.member?(weekend_alt, ~U[2026-01-09 12:00:00Z])
      refute Span.member?(weekend_alt, ~U[2026-01-10 12:00:00Z])
      assert Span.member?(weekend_alt, ~U[2026-01-11 12:00:00Z])
      refute Span.member?(weekend_alt, ~U[2026-01-12 12:00:00Z])
    end

    test "a step may use a coarser unit from the chain" do
      # "The 31st, monthly": day-grain bounds stepped by month, each
      # landing clamped to the month it falls in.
      monthly_31st =
        Span.arc!(
          from: Point.compose!(Point.month(:january), Point.day(31)),
          until: Point.compose!(Point.month(:december), Point.day(31)),
          step: {1, :month}
        )

      assert Span.member?(monthly_31st, ~U[2026-01-31 12:00:00Z])
      assert Span.member?(monthly_31st, ~U[2026-02-28 12:00:00Z])
      assert Span.member?(monthly_31st, ~U[2026-04-30 12:00:00Z])
      refute Span.member?(monthly_31st, ~U[2026-04-29 12:00:00Z])
    end

    test "at :time grain a bare integer step is rejected; a unit-carrying step works" do
      # A bare integer counts grain units, and Time has no unit cell.
      assert_raise ArgumentError, fn ->
        Span.arc!(from: Point.time(~T[09:00:00]), until: Point.time(~T[17:00:00]), step: 2)
      end

      # "Every 15 minutes between 09:00 and 17:00".
      every_15 =
        Span.arc!(
          from: Point.time(~T[09:00:00]),
          until: Point.time(~T[17:00:00]),
          step: {15, :minute}
        )

      assert Span.member?(every_15, ~U[2026-05-15 09:15:00Z])
      refute Span.member?(every_15, ~U[2026-05-15 09:07:00Z])
    end
  end

  describe "denotation" do
    test "day-number overflow clamps by default and skips on request" do
      # Feb 2026 has 28 days. Under :clamp "the 31st" fires on Feb 28...
      the_31st = Span.of(Point.day(31))
      assert Span.member?(the_31st, ~U[2026-02-28 12:00:00Z])

      # ...and under :skip February has no 31st at all. member? and
      # ground share this rule: it is one denotation function.
      literal_31st =
        Span.of(Point.new!(scope: :month, chain: [day: 31], overflow: :skip))

      refute Span.member?(literal_31st, ~U[2026-02-28 12:00:00Z])
      assert Span.member?(literal_31st, ~U[2026-01-31 12:00:00Z])
    end

    test "day(-1) is the honest 'last day of the month'" do
      last_day = Span.of(Point.day(-1))

      assert Span.member?(last_day, ~U[2026-02-28 12:00:00Z])
      assert Span.member?(last_day, ~U[2026-04-30 12:00:00Z])
      refute Span.member?(last_day, ~U[2026-04-29 12:00:00Z])
    end

    test "a missing ordinal skips and stays distinct from the last ordinal" do
      # Apr 2026 has five Wednesdays (the 29th is the 5th); Feb 2026
      # has four, so its "5th Wednesday" names nothing - it does NOT
      # clamp onto the last one.
      fifth_wed = Span.of(Point.day({:nth, 5, :wednesday}))
      last_wed = Span.of(Point.day({:nth, -1, :wednesday}))

      assert Span.member?(fifth_wed, ~U[2026-04-29 12:00:00Z])
      refute Span.member?(fifth_wed, ~U[2026-02-25 12:00:00Z])
      assert Span.member?(last_wed, ~U[2026-02-25 12:00:00Z])
    end

    test "a fortnightly point alternates weeks from its anchor" do
      # "Every other Wednesday", anchored in the week of Jan 7 2026.
      # Jan 7/14/21/28 are consecutive Wednesdays.
      fortnightly =
        Span.of(Point.every(Point.weekday(:wednesday), 2, ~D[2026-01-07]))

      assert Span.member?(fortnightly, ~U[2026-01-07 12:00:00Z])
      refute Span.member?(fortnightly, ~U[2026-01-14 12:00:00Z])
      assert Span.member?(fortnightly, ~U[2026-01-21 12:00:00Z])
      refute Span.member?(fortnightly, ~U[2026-01-28 12:00:00Z])
    end

    test "absolute!/1 carries a ray and clips at grounding" do
      # "From 2026-05-23 onward": cyclic arcs always need both bounds;
      # absolute intervals may leave one side open, like the kernel.
      onward = Span.absolute!(from: ~U[2026-05-23 00:00:00Z])

      assert Span.member?(onward, ~U[2026-08-01 12:00:00Z])
      refute Span.member?(onward, ~U[2026-05-22 12:00:00Z])

      grounded = Span.ground(onward, year_2026(), @utc)

      assert [%{from: ~U[2026-05-23 00:00:00Z], until: ~U[2027-01-01 00:00:00Z]}] =
               grounded.intervals
    end

    test "a cross-cycle intersection stays symbolic and answers member?" do
      # "Wednesdays in May": week cycle times year cycle. May 6 2026
      # is a Wednesday; Apr 29 is a Wednesday outside May.
      wednesdays_in_may =
        Span.intersection([Span.of(Point.month(:may)), Span.of(Point.weekday(:wednesday))])

      assert Span.member?(wednesdays_in_may, ~U[2026-05-06 12:00:00Z])
      refute Span.member?(wednesdays_in_may, ~U[2026-05-07 12:00:00Z])
      refute Span.member?(wednesdays_in_may, ~U[2026-04-29 12:00:00Z])
    end
  end

  describe "grounding" do
    test "a cyclic point grounds to one kernel interval per scope instance" do
      grounded = Span.ground(Span.of(Point.month(:may)), year_2026(), @utc)

      assert [%{from: ~U[2026-05-01 00:00:00Z], until: ~U[2026-06-01 00:00:00Z]}] =
               grounded.intervals
    end

    test "instances that straddle the horizon edge are grounded, then clipped" do
      # The last Wednesday of 2026 (Dec 30) sits in a week that runs
      # into 2027; enumerating only fully-contained weeks would lose it.
      grounded =
        Span.ground(
          Span.of(Point.weekday(:wednesday)),
          horizon(~U[2026-12-28 00:00:00Z], ~U[2027-01-01 00:00:00Z]),
          @utc
        )

      assert [%{from: ~U[2026-12-30 00:00:00Z], until: ~U[2026-12-31 00:00:00Z]}] =
               grounded.intervals
    end

    test "a fall-back day grounds one wall window to two kernel intervals" do
      # America/New_York, 2026-11-01: wall 00:30..01:30 exists in EDT
      # (04:30Z..05:30Z) and partly again in EST (06:00Z..06:30Z).
      night_slice =
        Span.arc!(
          from: Point.time(~T[00:30:00]),
          until: Point.time(~T[01:30:00]),
          left: :closed,
          right: :open
        )

      grounded =
        Span.ground(
          night_slice,
          horizon(~U[2026-11-01 00:00:00Z], ~U[2026-11-02 00:00:00Z]),
          @new_york
        )

      assert [
               %{from: ~U[2026-11-01 04:30:00Z], until: ~U[2026-11-01 05:30:00Z]},
               %{from: ~U[2026-11-01 06:00:00Z], until: ~U[2026-11-01 06:30:00Z]}
             ] = grounded.intervals
    end

    test "a wall time inside a spring-forward gap grounds to nothing" do
      # America/New_York, 2026-03-08: 02:30 never appears on any clock.
      grounded =
        Span.ground(
          Span.of(Point.time(~T[02:30:00])),
          horizon(~U[2026-03-08 00:00:00Z], ~U[2026-03-09 00:00:00Z]),
          @new_york
        )

      assert grounded.intervals == []
    end

    # [claude-code] Added (2026-08-05, Linear YUR-85, span half). The
    # kernel drops every piece that covers no instant, so a horizon
    # that covers no instant can hold nothing - whatever the span.
    test "ground/3 on a zero-width horizon returns the empty set struct" do
      may = Span.of(Point.month(:may))
      at = ~U[2026-05-15 12:00:00Z]

      # [t, t) covers no instant at all...
      assert Span.ground(may, %{from: at, until: at, left: :closed, right: :open}, @utc) ==
               %Zocam.Intervals{}

      # ...while the single-point horizon [t, t] covers exactly one,
      # and May does contain it.
      assert Span.ground(may, %{from: at, until: at, left: :closed, right: :closed}, @utc) ==
               %Zocam.Intervals{
                 intervals: [%{from: at, until: at, left: :closed, right: :closed}]
               }
    end

    test "nth selects within whole cycle instances, then clips to the horizon" do
      weekdays = Span.arc!(from: Point.weekday(:monday), until: Point.weekday(:friday))
      last_working_day = Span.nth(-1, weekdays, per: :month)

      # April 2026 ends on Thursday the 30th.
      grounded =
        Span.ground(
          last_working_day,
          horizon(~U[2026-04-01 00:00:00Z], ~U[2026-05-01 00:00:00Z]),
          @utc
        )

      assert [%{from: ~U[2026-04-30 00:00:00Z], until: ~U[2026-05-01 00:00:00Z]}] =
               grounded.intervals

      # A horizon cut at Jan 20 must NOT elect Jan 16 as "last Friday
      # of January": the true last Friday (Jan 30) is outside, so the
      # answer is nothing.
      last_friday = Span.nth(-1, Span.of(Point.weekday(:friday)), per: :month)

      cut =
        Span.ground(
          last_friday,
          horizon(~U[2026-01-01 00:00:00Z], ~U[2026-01-20 00:00:00Z]),
          @utc
        )

      assert cut.intervals == []
    end

    test "a multi-month window in a DST zone grounds through every timezone period" do
      # America/New_York 2026: EST -> EDT on Mar 8, EDT -> EST on
      # Nov 1. A preimage that reads only the periods at the window's
      # two endpoints loses the whole EDT summer between them, and
      # member? then disagrees with ground (the keystone property).
      year_span = Span.of(Point.year(2026))

      grounded =
        Span.ground(
          year_span,
          horizon(~U[2026-01-01 00:00:00Z], ~U[2027-01-02 00:00:00Z]),
          @new_york
        )

      # One contiguous block: wall Jan 1 2026 00:00 EST to wall
      # Jan 1 2027 00:00 EST, with the summer included seamlessly.
      assert [%{from: ~U[2026-01-01 05:00:00Z], until: ~U[2027-01-01 05:00:00Z]}] =
               grounded.intervals

      assert Span.member?(year_span, ~U[2026-07-04 12:00:00Z])
    end

    test "a wrapped arc with nth-weekday bounds resolves its until in the REAL next month" do
      # Last Saturday .. last Sunday wraps each month seam. 2026 facts:
      # Jan 31 = last Sat of Jan, Feb 22 = last Sun of Feb,
      # Feb 28 = last Sat of Feb, Mar 29 = last Sun of Mar.
      # A fake next-month container that copies the current month's
      # length elects the wrong "last Sunday".
      pay_stretch =
        Span.arc!(
          from: Point.day({:nth, -1, :saturday}),
          until: Point.day({:nth, -1, :sunday})
        )

      # Inside the January block [Jan 31, Feb 23).
      assert Span.member?(pay_stretch, ~U[2026-02-10 12:00:00Z])
      # In the gap between the January and February blocks.
      refute Span.member?(pay_stretch, ~U[2026-02-25 12:00:00Z])
      # Inside the February block [Feb 28, Mar 30).
      assert Span.member?(pay_stretch, ~U[2026-03-25 12:00:00Z])
    end

    test "a :month step samples through the year seam of a wrapping arc" do
      # "The 15th, monthly, from November to February": the sampling
      # must not stop at December.
      winter_15ths =
        Span.arc!(
          from: Point.compose!(Point.month(:november), Point.day(15)),
          until: Point.compose!(Point.month(:february), Point.day(15)),
          step: {1, :month}
        )

      assert Span.member?(winter_15ths, ~U[2026-11-15 12:00:00Z])
      assert Span.member?(winter_15ths, ~U[2026-12-15 12:00:00Z])
      assert Span.member?(winter_15ths, ~U[2027-01-15 12:00:00Z])
      assert Span.member?(winter_15ths, ~U[2027-02-15 12:00:00Z])
      refute Span.member?(winter_15ths, ~U[2027-01-20 12:00:00Z])
    end

    test "wrap is decided on the nominal chain, not on clamp-resolved dates" do
      # day 30 .. day 29 wraps every month. In February both bounds
      # clamp to Feb 28; a resolved-date comparison sees "one day, no
      # wrap" there and leaves a hole through March.
      around_month_end = Span.arc!(from: Point.day(30), until: Point.day(29))

      assert Span.member?(around_month_end, ~U[2026-03-05 12:00:00Z])
      assert Span.member?(around_month_end, ~U[2026-03-15 12:00:00Z])
      assert Span.member?(around_month_end, ~U[2026-03-29 12:00:00Z])
    end

    test "arc!/1 rejects unimplemented step families; a bare-month step works" do
      # Week-grain stepping is not implemented: reject loudly at
      # construction, never crash at evaluation.
      assert_raise ArgumentError, fn ->
        Span.arc!(from: Point.week(2), until: Point.week(40), step: {2, :week})
      end

      # A month step over a bare month chain is plain cell arithmetic.
      quarterly =
        Span.arc!(from: Point.month(:january), until: Point.month(:november), step: {3, :month})

      assert Span.member?(quarterly, ~U[2026-04-10 12:00:00Z])
      refute Span.member?(quarterly, ~U[2026-02-10 12:00:00Z])
    end

    test "absolute!/1 rejects closings outside the vocabulary" do
      assert_raise ArgumentError, fn ->
        Span.absolute!(%{from: ~U[2026-05-23 00:00:00Z], until: nil, left: :banana, right: nil})
      end
    end

    # [claude-code] Added (2026-08-05, Linear YUR-84, span half). The
    # keyword path runs the kernel's piece gate since the funnel
    # rebuild; the map path used to bypass it and accept an inverted
    # pair - a set that covers nothing but breaks the ordering laws.
    test "absolute!/1 rejects an inverted DateTime pair on both entry paths" do
      late = ~U[2026-06-01 00:00:00Z]
      early = ~U[2026-05-01 00:00:00Z]

      # The map path...
      assert_raise ArgumentError, ~r/runs forward/, fn ->
        Span.absolute!(%{from: late, until: early, left: :closed, right: :open})
      end

      # ...and the keyword path.
      assert_raise ArgumentError, ~r/runs forward/, fn ->
        Span.absolute!(from: late, until: early)
      end
    end

    # [claude-code] Added (2026-08-05, Linear YUR-88, span half). The
    # closing rule is the kernel's shared check now, lifted and not
    # copied, so the exact kernel wording proves the one source.
    test "absolute!/1 runs the kernel's shared closing check" do
      # A dead closing on an unbounded side is refused...
      error =
        assert_raise ArgumentError, fn ->
          Span.absolute!(%{
            from: ~U[2026-05-23 00:00:00Z],
            until: nil,
            left: :closed,
            right: :closed
          })
        end

      # ...with the kernel's own message, no local copy in front.
      assert error.message ==
               "right: must be :open or :closed on a bounded side, " <>
                 "nil on an unbounded side, got :closed"

      # A nil closing on a bounded side is refused the same way.
      assert_raise ArgumentError, ~r/left: must be :open or :closed/, fn ->
        Span.absolute!(%{from: ~U[2026-05-23 00:00:00Z], until: nil, left: nil, right: nil})
      end
    end

    test "member? agrees with ground everywhere inside the horizon" do
      # The keystone property, spot-checked: the two interpreters run
      # one shared denotation function.
      span =
        Span.intersection([Span.of(Point.month(:may)), Span.of(Point.weekday(:wednesday))])

      grounded = Span.ground(span, year_2026(), @utc)

      probes = [
        ~U[2026-05-06 12:00:00Z],
        ~U[2026-05-07 12:00:00Z],
        ~U[2026-04-29 12:00:00Z],
        ~U[2026-05-27 23:59:59Z],
        ~U[2026-06-03 12:00:00Z]
      ]

      for at <- probes do
        in_ground =
          Enum.any?(grounded.intervals, fn i ->
            DateTime.compare(i.from, at) != :gt and DateTime.compare(at, i.until) == :lt
          end)

        assert Span.member?(span, at) == in_ground
      end
    end
  end

  # [claude-code] Added (2026-08-05, decision D1). Unwrap the one arc
  # of a one-arc span: Enum walks the Arc struct, and the smart
  # constructors always hand it back inside an {:arcs, ...} node.
  defp one_arc({:arcs, _scope, _grain, [arc]}), do: arc

  # [claude-code] Added (2026-08-05, decision D1, span half). Enum
  # over an arc walks the symbolic cells of ONE instance. These tests
  # pin the walk against ground/3's interpretation of the same arcs:
  # the same wrap rule, the same whole-unit closings, and the same
  # step sampling (the doctests in the Arc moduledoc carry the four
  # canonical examples; here sit the sharper edges).
  describe "Enum over an arc (decision D1)" do
    test "an :open side drops that bound's cell" do
      arc =
        one_arc(
          Span.arc!(
            from: Point.weekday(:friday),
            until: Point.weekday(:monday),
            left: :open,
            right: :closed
          )
        )

      assert Enum.to_list(arc) == [:saturday, :sunday, :monday]
    end

    test "a grain-unit step samples every n-th cell; an until landing honors the right closing" do
      # Fri..Mon step 2 = {Fri, Sun}: the phase runs through the wrap
      # seam, exactly as the ground sampler runs it.
      alt =
        one_arc(
          Span.arc!(from: Point.weekday(:friday), until: Point.weekday(:monday), step: {2, :day})
        )

      assert Enum.to_list(alt) == [:friday, :sunday]

      # Step 3 lands exactly on Monday: kept while the right side is
      # :closed (the default)...
      landing =
        one_arc(
          Span.arc!(from: Point.weekday(:friday), until: Point.weekday(:monday), step: {3, :day})
        )

      assert Enum.to_list(landing) == [:friday, :monday]

      # ...and dropped when it is :open.
      open_landing =
        one_arc(
          Span.arc!(
            from: Point.weekday(:friday),
            until: Point.weekday(:monday),
            right: :open,
            step: {3, :day}
          )
        )

      assert Enum.to_list(open_landing) == [:friday]
    end

    test "a month step over month cells walks the quarters" do
      quarterly =
        one_arc(
          Span.arc!(from: Point.month(:january), until: Point.month(:november), step: {3, :month})
        )

      assert Enum.to_list(quarterly) == [:january, :april, :july, :october]
    end

    test "year cells enumerate as the years themselves" do
      years = one_arc(Span.arc!(from: Point.year(2026), until: Point.year(2028)))

      assert Enum.to_list(years) == [2026, 2027, 2028]
    end

    test "a stepped :time arc wraps its samples through midnight" do
      night =
        one_arc(
          Span.arc!(
            from: Point.time(~T[22:00:00]),
            until: Point.time(~T[06:00:00]),
            step: {2, :hour}
          )
        )

      # The right side defaults to :open at :time grain, so the 06:00
      # landing is dropped.
      assert Enum.to_list(night) == [~T[22:00:00], ~T[00:00:00], ~T[02:00:00], ~T[04:00:00]]
    end

    test "bounds with a prefix yield chains in which only the grain cell varies" do
      mid_may =
        one_arc(
          Span.arc!(
            from: Point.compose!(Point.month(:may), Point.day(10)),
            until: Point.compose!(Point.month(:may), Point.day(12))
          )
        )

      assert Enum.to_list(mid_may) == [
               [month: :may, day: 10],
               [month: :may, day: 11],
               [month: :may, day: 12]
             ]
    end

    test "a step whose unit is not the grain refuses with a pointer to ground/3" do
      # "The 31st, monthly": the samples resolve per real month (a
      # 31st clamps or skips), so they are not fixed cells of one
      # instance.
      monthly_31st =
        one_arc(
          Span.arc!(
            from: Point.compose!(Point.month(:january), Point.day(31)),
            until: Point.compose!(Point.month(:december), Point.day(31)),
            step: {1, :month}
          )
        )

      error = assert_raise ArgumentError, fn -> Enum.to_list(monthly_31st) end
      assert error.message =~ "not inside one instance"
      assert error.message =~ "Zocam.Span.ground/3"
    end

    test "cells without a fixed number refuse with a pointer to ground/3" do
      # Each month elects its own "last Saturday": no fixed cell.
      pay =
        one_arc(
          Span.arc!(
            from: Point.day({:nth, -1, :saturday}),
            until: Point.day({:nth, -1, :sunday})
          )
        )

      assert_raise ArgumentError, ~r/Zocam\.Span\.ground\/3/, fn -> Enum.to_list(pay) end

      # Day cells wrap in a cycle whose length changes per month, so
      # a wrapped day row is not fixed either.
      around = one_arc(Span.arc!(from: Point.day(30), until: Point.day(29)))
      assert_raise ArgumentError, ~r/Zocam\.Span\.ground\/3/, fn -> Enum.to_list(around) end

      # Bounds that differ above the grain cell cross a prefix
      # boundary: those cells resolve on the real calendar.
      spring =
        one_arc(
          Span.arc!(
            from: Point.compose!(Point.month(:may), Point.day(20)),
            until: Point.compose!(Point.month(:june), Point.day(10))
          )
        )

      assert_raise ArgumentError, ~r/Zocam\.Span\.ground\/3/, fn -> Enum.to_list(spring) end
    end

    test "Enum.count and Enum.member? follow the cell row" do
      weekend = one_arc(Span.arc!(from: Point.weekday(:friday), until: Point.weekday(:monday)))

      assert Enum.count(weekend) == 4
      assert Enum.member?(weekend, :sunday)
      refute Enum.member?(weekend, :wednesday)
    end
  end

  # [claude-code] Added (2026-08-05, Linear YUR-78). Helpers for the
  # DST-seam recipes below. covered?/2 asks the grounded set the same
  # question member?/2 answers on the span, closings included - the
  # keystone property needs both sides of the comparison to be honest
  # about a :closed or :open edge.
  defp covered?(%Zocam.Intervals{} = set, %DateTime{} = at) do
    Enum.any?(set, fn i ->
      lower =
        case DateTime.compare(at, i.from) do
          :gt -> true
          :eq -> i.left == :closed
          :lt -> false
        end

      upper =
        case DateTime.compare(at, i.until) do
          :lt -> true
          :eq -> i.right == :closed
          :gt -> false
        end

      lower and upper
    end)
  end

  defp local!(%DateTime{} = at, tz), do: DateTime.shift_zone!(at, tz, Tzdata.TimeZoneDatabase)

  # The arc under test: the wall window [01:00, 03:00), which
  # straddles both 2026 America/New_York seams (the clocks move at
  # wall 02:00 on both days).
  defp night_window do
    Span.arc!(
      from: Point.time(~T[01:00:00]),
      until: Point.time(~T[03:00:00]),
      left: :closed,
      right: :open
    )
  end

  # [claude-code] Added (2026-08-05, Linear YUR-78). At a DST seam the
  # tz-period boundary can supply the upper edge of a grounded piece.
  # The boundary instant belongs to the NEXT period, so the edge must
  # come out :open; when the window still covers the instant's new
  # wall reading, the next period's own piece re-covers it. Forcing
  # :closed there made ground/3 cover ~U[2026-03-08 07:00:00Z] (local
  # 03:00 EDT, outside [01:00, 03:00)) while member?/2 said no - the
  # keystone property broke at every spring-forward seam.
  describe "DST seams (YUR-78)" do
    test "the gap edge comes out :open: 07:00Z is not covered and one wall hour remains" do
      # 2026-03-08, America/New_York: the wall clock jumps from 02:00
      # to 03:00, so [01:00, 03:00) holds ONE real hour (01:00..02:00
      # EST) and ~U[2026-03-08 07:00:00Z] reads as 03:00 EDT - outside
      # the window.
      grounded =
        Span.ground(
          night_window(),
          horizon(~U[2026-03-08 00:00:00Z], ~U[2026-03-09 00:00:00Z]),
          @new_york
        )

      assert grounded.intervals == [
               %{
                 from: ~U[2026-03-08 06:00:00Z],
                 until: ~U[2026-03-08 07:00:00Z],
                 left: :closed,
                 right: :open
               }
             ]

      refute covered?(grounded, ~U[2026-03-08 07:00:00Z])
      # member?/2 reads the wall clock, so give it the local reading.
      refute Span.member?(night_window(), local!(~U[2026-03-08 07:00:00Z], @new_york))
      assert Span.member?(night_window(), local!(~U[2026-03-08 06:30:00Z], @new_york))
    end

    test "the fold day keeps its full width: the doubled wall hour stays covered" do
      # 2026-11-01: the wall clock falls back at 02:00 EDT to 01:00
      # EST, so [01:00, 03:00) holds THREE real hours (01:00..02:00
      # EDT, then 01:00..03:00 EST) - one contiguous UTC block.
      grounded =
        Span.ground(
          night_window(),
          horizon(~U[2026-11-01 00:00:00Z], ~U[2026-11-02 00:00:00Z]),
          @new_york
        )

      assert [%{from: ~U[2026-11-01 05:00:00Z], until: ~U[2026-11-01 08:00:00Z]}] =
               grounded.intervals
    end

    # [claude-code] Added (2026-08-05, Linear YUR-78, second round).
    # The first fix made the right-OPEN window honest at the seams.
    # A right-CLOSED window still broke: when the window's upper wall
    # value sits exactly on a period start, the successor period's
    # clip remnant is one wall instant wide - and period_piece/3
    # dropped it. member?/2 reads the wall clock and says yes; the
    # grounded set said no. Two recipes pin both seam kinds.
    test "a closed right edge at the gap seam: the boundary instant stays covered" do
      # 2026-03-08: the wall clock jumps 02:00 -> 03:00 EDT at
      # ~U[2026-03-08 07:00:00Z]. The window [01:00, 03:00] ends ON
      # the post-jump reading, and the closed edge includes it. So
      # 07:00Z (wall 03:00 EDT) is a member - the grounded set must
      # close its upper edge there, not stop one instant short.
      window =
        Span.arc!(
          from: Point.time(~T[01:00:00]),
          until: Point.time(~T[03:00:00]),
          left: :closed,
          right: :closed
        )

      grounded =
        Span.ground(
          window,
          horizon(~U[2026-03-08 00:00:00Z], ~U[2026-03-09 00:00:00Z]),
          @new_york
        )

      # One fused piece: the EST hour [06:00Z, 07:00Z) and the EDT
      # single point [07:00Z, 07:00Z] touch, so compress joins them.
      assert grounded.intervals == [
               %{
                 from: ~U[2026-03-08 06:00:00Z],
                 until: ~U[2026-03-08 07:00:00Z],
                 left: :closed,
                 right: :closed
               }
             ]

      assert covered?(grounded, ~U[2026-03-08 07:00:00Z])
      assert Span.member?(window, local!(~U[2026-03-08 07:00:00Z], @new_york))
      # One minute past the seam the wall reads 03:01 - outside.
      refute covered?(grounded, ~U[2026-03-08 07:01:00Z])
      refute Span.member?(window, local!(~U[2026-03-08 07:01:00Z], @new_york))
    end

    test "a closed right edge at the fold seam: the second wall reading survives" do
      # 2026-11-01: the wall clock falls back 02:00 EDT -> 01:00 EST
      # at ~U[2026-11-01 06:00:00Z]. Wall 01:00 happens twice: once
      # as 05:00Z (EDT) and once as 06:00Z (EST). member?/2 accepts
      # BOTH readings of a closed until at 01:00, so the grounded set
      # must cover both - the EST reading is a single-point piece.
      window =
        Span.arc!(
          from: Point.time(~T[00:30:00]),
          until: Point.time(~T[01:00:00]),
          left: :closed,
          right: :closed
        )

      grounded =
        Span.ground(
          window,
          horizon(~U[2026-11-01 00:00:00Z], ~U[2026-11-02 00:00:00Z]),
          @new_york
        )

      assert grounded.intervals == [
               %{
                 from: ~U[2026-11-01 04:30:00Z],
                 until: ~U[2026-11-01 05:00:00Z],
                 left: :closed,
                 right: :closed
               },
               %{
                 from: ~U[2026-11-01 06:00:00Z],
                 until: ~U[2026-11-01 06:00:00Z],
                 left: :closed,
                 right: :closed
               }
             ]

      # Both readings of wall 01:00 are members, and both are covered.
      for at <- [~U[2026-11-01 05:00:00Z], ~U[2026-11-01 06:00:00Z]] do
        assert covered?(grounded, at)
        assert Span.member?(window, local!(at, @new_york))
      end

      # Between the two readings the wall shows 01:01..02:00 EDT -
      # past the window - so that stretch stays uncovered.
      refute covered?(grounded, ~U[2026-11-01 05:30:00Z])
      refute Span.member?(window, local!(~U[2026-11-01 05:30:00Z], @new_york))
    end

    test "member?/2 agrees with ground/3 on a 15-minute grid across both 2026 seams" do
      # A deterministic sample, not the full property test - that one
      # stays open as Linear YUR-83. Each seam day is sampled every 15
      # minutes from its horizon start, 96 probes per day, so both
      # seam instants (07:00Z in March, 06:00Z in November) sit
      # exactly on the grid.
      # [claude-code] Changed (2026-08-05, Linear YUR-78, second
      # round): the grid now also runs two right-CLOSED windows. A
      # closed upper edge that lands exactly on a period start is the
      # case the first fix missed, so the closings must both sit on
      # the grid.
      seam_days = [
        {~U[2026-03-08 00:00:00Z], ~U[2026-03-09 00:00:00Z]},
        {~U[2026-11-01 00:00:00Z], ~U[2026-11-02 00:00:00Z]}
      ]

      windows = [
        night_window(),
        Span.arc!(
          from: Point.time(~T[01:00:00]),
          until: Point.time(~T[03:00:00]),
          left: :closed,
          right: :closed
        ),
        Span.arc!(
          from: Point.time(~T[00:30:00]),
          until: Point.time(~T[01:00:00]),
          left: :closed,
          right: :closed
        )
      ]

      for window <- windows, {h_from, h_until} <- seam_days do
        grounded = Span.ground(window, horizon(h_from, h_until), @new_york)

        for quarter_hour <- 0..95 do
          at = DateTime.add(h_from, quarter_hour * 15 * 60, :second)
          local = local!(at, @new_york)

          assert covered?(grounded, at) == Span.member?(window, local),
                 "ground/3 and member?/2 disagree at #{inspect(at)} " <>
                   "(local #{inspect(local)})"
        end
      end
    end
  end

  # [claude-code] Added 2026-08-05 for Linear YUR-57. Span takes a
  # `%DateTime{}` from the caller in four places. A foreign-calendar
  # instant reached `DateTime.to_naive/1`, and from there its year,
  # month, and day fields were read as ISO numbers: a wrong answer with
  # no crash. Every door now runs the same check. The arc bounds need no
  # door of their own — they are `Zocam.Point` values, checked there.
  describe "the ISO calendar" do
    alias Zocam.ForeignCalendar

    @foreign_at %{~U[2026-05-06 12:00:00Z] | calendar: ForeignCalendar}

    setup do
      %{span: Span.of(Point.weekday(:wednesday))}
    end

    test "absolute!/1 refuses a foreign bound, on either side" do
      for side <- [:from, :until] do
        interval =
          %{
            from: ~U[2026-05-01 00:00:00Z],
            until: ~U[2026-06-01 00:00:00Z],
            left: :closed,
            right: :open
          }
          |> Map.put(side, @foreign_at)

        assert_raise ArgumentError, ~r/Zocam\.ForeignCalendar/, fn ->
          Span.absolute!(interval)
        end
      end
    end

    test "ground/3 refuses a foreign horizon", %{span: span} do
      assert_raise ArgumentError, ~r/Zocam\.ForeignCalendar/, fn ->
        Span.ground(span, horizon(@foreign_at, ~U[2026-06-01 00:00:00Z]), @utc)
      end
    end

    test "member?/2 refuses a foreign instant", %{span: span} do
      error = assert_raise ArgumentError, fn -> Span.member?(span, @foreign_at) end

      assert error.message =~ "Zocam.ForeignCalendar"
      assert error.message =~ "DateTime.convert!"
    end

    test "stream/3 refuses a foreign start, at the call and not at the first take", %{span: span} do
      # Stream.resource/3 is lazy, so a check inside the start function
      # would only fire on enumeration - far from the wrong call. The
      # check sits in the body of stream/3, thus this raises here.
      assert_raise ArgumentError, ~r/Zocam\.ForeignCalendar/, fn ->
        Span.stream(span, @foreign_at, @utc)
      end
    end

    test "the same instant on the ISO calendar still passes", %{span: span} do
      assert Span.member?(span, ~U[2026-05-06 12:00:00Z])
    end
  end
end
