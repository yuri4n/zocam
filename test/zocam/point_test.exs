# [claude-code] Point tests. All Point functions are implemented:
# constructors in step 1, composition and the readers in step 2. The
# TDD backlog for the set layer lives in span_test.exs.
defmodule Zocam.PointTest do
  use ExUnit.Case, async: true

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

    test "constructors reject values outside their vocabulary" do
      assert_raise ArgumentError, fn -> Point.month(:wednesday) end
      assert_raise ArgumentError, fn -> Point.weekday(:may) end
      assert_raise ArgumentError, fn -> Point.day(0) end
      assert_raise ArgumentError, fn -> Point.day(32) end
      assert_raise ArgumentError, fn -> Point.week(54) end
      assert_raise ArgumentError, fn -> Point.day({:nth, 6, :wednesday}) end
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
