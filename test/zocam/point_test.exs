# [claude-code] Point tests. All Point functions are implemented:
# constructors in step 1, composition and the readers in step 2. The
# TDD backlog for the set layer lives in span_test.exs.
defmodule Zocam.PointTest do
  use ExUnit.Case, async: true

  # [claude-code] Added (2026-08-05): runs the doctests in the Point
  # docstrings. Each public function carries runnable examples; this
  # line makes the suite prove them.
  doctest Zocam.Point

  alias Zocam.Point
  alias Zocam.Point.ComposeError

  describe "struct" do
    test "defaults: day-number overflow clamps to the month end" do
      point = struct!(Point, scope: :year, chain: [month: :may])

      assert point.overflow == :clamp
    end
  end

  describe "constructors" do
    test "constructors infer the smallest scope that makes the value repeat" do
      assert Point.year(2026) == %Point{scope: :absolute, chain: [year: 2026], overflow: :clamp}
      assert Point.month(:may) == %Point{scope: :year, chain: [month: :may], overflow: :clamp}
      assert Point.week(33) == %Point{scope: :year, chain: [week: 33], overflow: :clamp}
      assert Point.day(23) == %Point{scope: :month, chain: [day: 23], overflow: :clamp}

      assert Point.weekday(:wednesday) ==
               %Point{scope: :week, chain: [weekday: :wednesday], overflow: :clamp}

      assert Point.time(~T[15:00:00]) ==
               %Point{scope: :day, chain: [time: ~T[15:00:00]], overflow: :clamp}
    end

    test "day/1 also takes negative indices and ordinal weekday selectors" do
      # -1 is the last day of the month: the honest spelling, distinct
      # from day(31) + clamping.
      assert Point.day(-1).chain == [day: -1]
      # First Wednesday of the month.
      assert Point.day({:nth, 1, :wednesday}).chain == [day: {:nth, 1, :wednesday}]
    end

    # [cursor-agent] Changed 2026-08-06 (Linear YUR-81 and YUR-72).
    # The vocabulary heads stay guard-only: the compile-time checker
    # flags a bad literal, and the runtime FunctionClauseError is the
    # accepted price. The calls go through apply/3 so the checker
    # cannot see the literals - these misuses are deliberate, and the
    # suite must stay free of warnings (YUR-72).
    test "vocabulary constructors reject a value outside their vocabulary" do
      misuse = fn fun, arg -> apply(Point, fun, [arg]) end

      assert_raise FunctionClauseError, fn -> misuse.(:month, :wednesday) end
      assert_raise FunctionClauseError, fn -> misuse.(:weekday, :may) end
      assert_raise FunctionClauseError, fn -> misuse.(:year, :nope) end
      assert_raise FunctionClauseError, fn -> misuse.(:time, :noon) end
      assert_raise FunctionClauseError, fn -> misuse.(:day, {:nth, 1, :may}) end
    end

    # [cursor-agent] Added 2026-08-06 (Linear YUR-81). A range guard
    # buys no compile-time flag: the checker carries integer(), not
    # 1..53, so week(54) compiled in silence AND raised a bare
    # FunctionClauseError. These heads teach at run time instead -
    # the fallback raises an ArgumentError that names the range.
    test "range constructors teach when the number is out of range" do
      assert_raise ArgumentError, ~r/1\.\.53/, fn -> Point.week(54) end
      assert_raise ArgumentError, ~r/1\.\.53/, fn -> Point.week(0) end
      assert_raise ArgumentError, ~r/1\.\.31/, fn -> Point.day(0) end
      assert_raise ArgumentError, ~r/1\.\.31/, fn -> Point.day(32) end
      assert_raise ArgumentError, ~r/1\.\.31/, fn -> Point.day(-99) end
      assert_raise ArgumentError, ~r/1\.\.5/, fn -> Point.day({:nth, 6, :wednesday}) end
    end

    # [claude-code] The other half of the same decision: values that reach a
    # constructor through new!/1 are computed, not literals, so the checker
    # cannot see them. There validate_value!/2 stays the authority and still
    # raises the taught ArgumentError.
    test "new!/1 still teaches when a computed value is outside the vocabulary" do
      assert_raise ArgumentError, fn ->
        Point.new!(scope: :year, chain: [month: :wednesday])
      end
    end

    test "new!/1 rejects a chain that skips a level under its scope" do
      # Under :year the chain must start at month or week, never at day.
      assert_raise ArgumentError, fn ->
        Point.new!(scope: :year, chain: [day: 23])
      end
    end
  end

  describe "compose/2 and compose!/2" do
    test "compose/2 concatenates chains when the units meet" do
      # "2026" + "May" = "May 2026": grain year meets scope year.
      assert {:ok, may_2026} = Point.compose(Point.year(2026), Point.month(:may))

      assert may_2026 == %Point{
               scope: :absolute,
               chain: [year: 2026, month: :may],
               overflow: :clamp
             }

      # "Jan" + "the 23rd" = "Jan 23 of every year".
      assert {:ok, jan_23} = Point.compose(Point.month(:january), Point.day(23))
      assert jan_23.scope == :year
      assert jan_23.chain == [month: :january, day: 23]
    end

    test "compose/2 accepts sibling units of the same class" do
      # A weekday is day-sized, so a time-of-day refines it: the guard
      # compares grain CLASS, not unit identity.
      assert {:ok, wed_15} = Point.compose(Point.weekday(:wednesday), Point.time(~T[15:00:00]))

      assert wed_15 == %Point{
               scope: :week,
               chain: [weekday: :wednesday, time: ~T[15:00:00]],
               overflow: :clamp
             }
    end

    test "compose/2 rejects a gap in the chain and hints at intersection" do
      # "May" + "15:00": the day is free in the middle, so the meaning
      # is a set ("15:00 of every day of May"), not one point.
      assert {:error, %ComposeError{reason: :grain_gap, hint: hint}} =
               Point.compose(Point.month(:may), Point.time(~T[15:00:00]))

      assert hint =~ "intersection"
    end

    test "compose/2 rejects cross-cycle combinations" do
      # "2026" + "a Wednesday": weeks do not nest in years. The set
      # "Wednesdays of 2026" exists, but only as an intersection.
      assert {:error, %ComposeError{reason: :cross_cycle}} =
               Point.compose(Point.year(2026), Point.weekday(:wednesday))
    end

    test "compose/2 rejects a repeated unit" do
      # "May of June" is meaningless: one chain cannot hold month twice.
      assert {:error, %ComposeError{reason: :invalid}} =
               Point.compose(Point.month(:may), Point.month(:june))
    end

    test "compose!/2 raises the same error compose/2 returns" do
      assert_raise ComposeError, fn ->
        Point.compose!(Point.month(:may), Point.time(~T[15:00:00]))
      end
    end

    test "compose/2 keeps the overflow policy of the day segment" do
      # Overflow only means something where a day number sits, and a
      # composed chain holds at most one day segment. So the policy of
      # the operand that contributes the day segment travels with it.
      jan_31_skip = Point.new!(scope: :month, chain: [day: 31], overflow: :skip)

      # The day segment comes from the inner point: its :skip wins.
      assert {:ok, jan_31} = Point.compose(Point.month(:january), jan_31_skip)
      assert jan_31.overflow == :skip

      # The day segment sits in the outer point: the inner time point's
      # default :clamp must not erase the :skip.
      assert {:ok, jan_31_15} = Point.compose(jan_31, Point.time(~T[15:00:00]))
      assert jan_31_15.overflow == :skip
    end

    test "compose/2 keeps an every-scoped outer but rejects an every-scoped inner" do
      anchor = ~D[2026-01-07]

      # Outer side: the rhythm lives in the scope, and compose keeps
      # the outer scope. "Every other Wednesday" + "15:00" works.
      fortnightly = Point.every(Point.weekday(:wednesday), 2, anchor)
      assert {:ok, wed_15} = Point.compose(fortnightly, Point.time(~T[15:00:00]))
      assert wed_15.scope == {:every, 2, :week, anchor}

      # Inner side: a chain has no place for the inner's phase, so a
      # composed result would silently drop k and the anchor. Rejected.
      every_other_23rd = Point.every(Point.day(23), 2, anchor)

      assert {:error, %ComposeError{reason: :anchored, hint: hint}} =
               Point.compose(Point.month(:may), every_other_23rd)

      assert hint =~ "every/3"
    end
  end

  describe "every/3" do
    test "every/3 re-scopes a cyclic point to every k-th cycle instance" do
      # "Every other Wednesday", in phase with the week of Jan 7 2026.
      fortnightly = Point.every(Point.weekday(:wednesday), 2, ~D[2026-01-07])

      assert fortnightly.scope == {:every, 2, :week, ~D[2026-01-07]}
      assert fortnightly.chain == [weekday: :wednesday]
    end

    test "every/3 rejects an absolute point" do
      # "May 2026" happens once; "every 2nd May 2026" means nothing.
      assert_raise ArgumentError, fn ->
        Point.every(Point.year(2026), 2, ~D[2026-01-07])
      end
    end

    test "every/3 rejects re-anchoring an already multi-cycle point" do
      # Nested anchors would hide which phase wins. Restate the rhythm
      # from the base cycle instead.
      fortnightly = Point.every(Point.weekday(:wednesday), 2, ~D[2026-01-07])

      assert_raise ArgumentError, fn ->
        Point.every(fortnightly, 3, ~D[2026-02-04])
      end
    end
  end

  # [claude-code] Added 2026-08-05 for Linear YUR-57. A point stores two
  # stdlib values that carry a calendar: the `:time` segment and the
  # `every/3` anchor. Every month, weekday, and day number in this
  # library is read as an ISO number, so a value on another calendar
  # validated and then meant something else, with no crash and no
  # warning. Both entry paths (the constructor and `new!/1`) now reach
  # the same check, so both raise the same taught error.
  describe "the ISO calendar" do
    alias Zocam.ForeignCalendar

    @foreign_time %{~T[09:00:00] | calendar: ForeignCalendar}
    @foreign_date %{~D[2026-05-15] | calendar: ForeignCalendar}

    test "time/1 refuses a %Time{} on another calendar" do
      error = assert_raise ArgumentError, fn -> Point.time(@foreign_time) end

      assert error.message =~ "Zocam.ForeignCalendar"
      assert error.message =~ "Time.convert!"
    end

    test "new!/1 refuses a foreign %Time{} in the chain" do
      # The constructors are guard-only, so this is the path a computed
      # value takes. It must teach the same lesson.
      assert_raise ArgumentError, ~r/Zocam\.ForeignCalendar/, fn ->
        Point.new!(scope: :day, chain: [time: @foreign_time])
      end
    end

    test "every/3 refuses a foreign %Date{} anchor" do
      error =
        assert_raise ArgumentError, fn ->
          Point.every(Point.weekday(:monday), 2, @foreign_date)
        end

      assert error.message =~ "Zocam.ForeignCalendar"
      assert error.message =~ "Date.convert!"
    end

    test "new!/1 refuses a foreign anchor inside an {:every, ...} scope" do
      assert_raise ArgumentError, ~r/Zocam\.ForeignCalendar/, fn ->
        Point.new!(scope: {:every, 2, :week, @foreign_date}, chain: [weekday: :monday])
      end
    end

    test "the ISO values that mean the same thing still pass" do
      assert Point.time(~T[09:00:00]).chain == [time: ~T[09:00:00]]

      assert Point.every(Point.weekday(:monday), 2, ~D[2026-05-15]).scope ==
               {:every, 2, :week, ~D[2026-05-15]}
    end
  end

  describe "grain_class/1 and scope_class/1" do
    test "grain_class/1 and scope_class/1 read the two type axes" do
      wed_15 = Point.compose!(Point.weekday(:wednesday), Point.time(~T[15:00:00]))

      assert Point.grain_class(wed_15) == :time
      assert Point.scope_class(wed_15) == :week
      assert Point.grain_class(Point.month(:may)) == :month
      assert Point.scope_class(Point.year(2026)) == :absolute
    end
  end
end
