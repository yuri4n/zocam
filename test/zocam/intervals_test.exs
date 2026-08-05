defmodule Zocam.IntervalsTest do
  use ExUnit.Case
  doctest Zocam.Intervals

  alias Zocam.Intervals

  describe "new/1" do
    test "interval has from [time] and until last time of the day" do
      interval = Intervals.new!(from: ~T[00:30:00])

      assert hd(interval.intervals).from == ~T[00:30:00]
      assert hd(interval.intervals).until == nil
    end

    test "interval has from [time] and until [time]" do
      interval = Intervals.new!(from: ~T[00:30:00], until: ~T[10:00:00])

      assert %{from: from, until: until} = hd(interval.intervals)
      assert from == ~T[00:30:00]
      assert until == ~T[10:00:00]
    end

    test "interval fails if more than one from or until is passed" do
      assert_raise ArgumentError, fn ->
        Intervals.new!(from: ~T[00:30:00], until: ~T[10:00:00], from: ~T[00:30:00])
      end
    end
  end

  describe "compress/1 while creating intervals" do
    test "intervals get unionized when possible" do
      intervals =
        Intervals.new!(
          interval: [from: ~T[00:30:00], until: ~T[10:00:00]],
          interval: [from: ~T[05:00:00], until: ~T[08:00:00]],
          interval: [from: ~T[09:00:00], until: ~T[12:00:00]]
        )

      assert [%{from: from, until: until}] = intervals.intervals
      assert from == ~T[00:30:00]
      assert until == ~T[12:00:00]
    end
  end

  test "two intervals overlaps" do
    interval1 = [from: ~T[00:30:00], until: ~T[10:00:00]]
    interval2 = [from: ~T[09:00:00], until: ~T[12:00:00]]
    interval3 = [from: ~T[10:00:00]]
    interval4 = %{until: ~T[09:00:00], from: nil, right: :open, left: :closed}

    assert Intervals.overlaps?(interval1, interval2) === true
    assert Intervals.overlaps?(interval1, interval3) === false
    assert Intervals.overlaps?(interval1, interval4) === true
    assert Intervals.overlaps?(interval2, interval3) === true
    assert Intervals.overlaps?(interval2, interval4) === false
    assert Intervals.overlaps?(interval3, [interval1, interval4]) === false
  end

  test "intersect intervals" do
    intervals1 = Intervals.new!(from: ~T[00:30:00], until: ~T[10:00:00])
    intervals2 = Intervals.new!(from: ~T[05:00:00], until: ~T[11:00:00])

    expected = [
      %{from: ~T[05:00:00], until: ~T[10:00:00], left: :closed, right: :open}
    ]

    assert Intervals.intersect(intervals1, intervals2).intervals === expected
    assert Intervals.intersect(intervals2, intervals1).intervals === expected

    intervals3 =
      Intervals.new!(
        interval: [from: ~T[11:00:00], until: ~T[12:00:00]],
        interval: [from: ~T[13:00:00], until: ~T[14:00:00]]
      )

    intervals4 =
      Intervals.new!(
        interval: [from: ~T[10:00:00], until: ~T[11:00:00]],
        interval: [from: ~T[12:00:00], until: ~T[13:00:00]]
      )

    assert Intervals.intersect(intervals1, intervals3).intervals === []
    assert Intervals.intersect(intervals3, intervals4).intervals === []
  end

  test "complement intervals" do
    intervals = Intervals.new!(from: ~T[00:30:00], until: ~T[10:00:00])

    assert [i1, i2] = Intervals.complement(intervals).intervals
    assert %{from: nil, until: ~T[00:30:00], left: nil, right: :open} == i1
    assert %{from: ~T[10:00:00], until: nil, left: :closed, right: nil} == i2
  end

  # [claude-code] Complement of half-unbounded intervals and of covering
  # sets. Before the fix, both half-unbounded branches read the endpoint
  # from the side that is nil, so they returned the whole timeline; and
  # the list clause crashed on a whole-timeline member (nil piece) or
  # once the running intersection became empty.
  describe "complement/1 edge cases" do
    test "complement of a left-unbounded interval starts at its end" do
      assert Intervals.complement(%{from: nil, until: ~T[05:00:00], left: nil, right: :open}) ==
               %{from: ~T[05:00:00], until: nil, left: :closed, right: nil}
    end

    test "complement of a right-unbounded interval ends at its start" do
      assert Intervals.complement(%{from: ~T[05:00:00], until: nil, left: :closed, right: nil}) ==
               %{from: nil, until: ~T[05:00:00], left: nil, right: :open}
    end

    test "complement of the whole timeline is the empty set" do
      whole = %{from: nil, until: nil, left: nil, right: nil}

      assert Intervals.complement([whole]) == []
    end

    test "complement stays empty once the pieces cover everything" do
      covering = [
        %{from: nil, until: ~T[05:00:00], left: nil, right: :open},
        %{from: ~T[03:00:00], until: nil, left: :open, right: nil},
        %{from: ~T[08:00:00], until: ~T[09:00:00], left: :closed, right: :open}
      ]

      assert Intervals.complement(covering) == []
    end
  end

  # [claude-code] Coalescing of touching intervals. Before the fix,
  # compress/union kept [a, b) and [b, c) separate although together
  # they cover [a, c) with no hole.
  describe "compress/1 coalescing of touching intervals" do
    test "touching closed-open intervals merge into one" do
      intervals =
        Intervals.new!(
          interval: [from: ~T[06:00:00], until: ~T[12:00:00]],
          interval: [from: ~T[12:00:00], until: ~T[18:00:00]]
        )

      assert [%{from: ~T[06:00:00], until: ~T[18:00:00], left: :closed, right: :open}] =
               intervals.intervals
    end

    test "the merge happens whatever the insertion order" do
      intervals =
        Intervals.new!(
          interval: [from: ~T[12:00:00], until: ~T[18:00:00]],
          interval: [from: ~T[06:00:00], until: ~T[12:00:00]]
        )

      assert [%{from: ~T[06:00:00], until: ~T[18:00:00]}] = intervals.intervals
    end

    test "a chain of touching intervals collapses into one" do
      intervals =
        Intervals.new!(
          interval: [from: ~T[00:00:00], until: ~T[06:00:00]],
          interval: [from: ~T[12:00:00], until: ~T[18:00:00]],
          interval: [from: ~T[06:00:00], until: ~T[12:00:00]]
        )

      assert [%{from: ~T[00:00:00], until: ~T[18:00:00]}] = intervals.intervals
    end

    test "either side covering the shared endpoint is enough" do
      # Left side covers 12:00: [06, 12] plus (12, 18).
      merged =
        Intervals.compress([
          %{from: ~T[06:00:00], until: ~T[12:00:00], left: :closed, right: :closed},
          %{from: ~T[12:00:00], until: ~T[18:00:00], left: :open, right: :open}
        ])

      assert [%{from: ~T[06:00:00], until: ~T[18:00:00], left: :closed, right: :open}] = merged
    end

    test "two open sides leave a hole and do not merge" do
      # (06, 12) plus (12, 18): the instant 12:00 is in neither.
      kept =
        Intervals.compress([
          %{from: ~T[06:00:00], until: ~T[12:00:00], left: :open, right: :open},
          %{from: ~T[12:00:00], until: ~T[18:00:00], left: :open, right: :open}
        ])

      assert length(kept) == 2
    end

    test "union/2 merges a new interval that touches an existing one" do
      existing = [%{from: ~T[08:00:00], until: ~T[12:00:00], left: :closed, right: :open}]
      new = %{from: ~T[12:00:00], until: ~T[14:00:00], left: :closed, right: :open}

      assert [%{from: ~T[08:00:00], until: ~T[14:00:00], left: :closed, right: :open}] =
               Intervals.union(existing, new)
    end

    test "mixed microsecond precision does not fake an overlap" do
      # Same instant, different precision: structural == is false for
      # ~T[10:00:00] vs ~T[10:00:00.000000], but they are the same
      # moment. Both sides open at 10:00 - the hole must survive.
      a = %{from: ~T[09:00:00], until: ~T[10:00:00], left: :open, right: :open}
      b = %{from: ~T[10:00:00.000000], until: ~T[11:00:00], left: :open, right: :open}

      refute Intervals.overlaps?(a, b)
      assert length(Intervals.compress([a, b])) == 2
    end

    test "mixed microsecond precision still coalesces a covered endpoint" do
      a = %{from: ~T[06:00:00], until: ~T[12:00:00], left: :closed, right: :open}
      b = %{from: ~T[12:00:00.000], until: ~T[18:00:00], left: :closed, right: :open}

      assert [%{from: ~T[06:00:00], until: ~T[18:00:00]}] = Intervals.compress([a, b])
    end
  end

  # [claude-code] The algebra is closed over the empty set it can
  # produce: complement of a covering set and diff(x, x) both return
  # [], and every set operation must accept that [] back. The
  # interval-level {left, right} and nil results compose too.
  describe "empty set closure" do
    test "set operations accept the empty set" do
      a = [%{from: ~T[08:00:00], until: ~T[10:00:00], left: :closed, right: :open}]
      whole = %{from: nil, until: nil, left: nil, right: nil}

      assert Intervals.diff(a, []) == a
      assert Intervals.diff([], a) == []
      assert Intervals.intersect(a, []) == []
      refute Intervals.overlaps?(a, [])
      assert Intervals.complement([]) == [whole]
    end

    test "complement of an empty result is the whole timeline" do
      s = Intervals.new!(from: ~T[01:00:00], until: ~T[02:00:00])
      empty = Intervals.diff(s, s)

      assert empty.intervals == []

      assert Intervals.complement(empty).intervals == [
               %{from: nil, until: nil, left: nil, right: nil}
             ]
    end

    test "diff composes with a complement that covers everything" do
      a = [%{from: ~T[08:00:00], until: ~T[10:00:00], left: :closed, right: :open}]

      covering = [
        %{from: nil, until: ~T[05:00:00], left: nil, right: :open},
        %{from: ~T[05:00:00], until: nil, left: :closed, right: nil}
      ]

      assert Intervals.diff(a, Intervals.complement(covering)) == a
    end

    test "interval-level complement and diff results feed back into set operations" do
      a = [%{from: ~T[00:00:00], until: ~T[10:00:00], left: :closed, right: :open}]
      b = %{from: ~T[02:00:00], until: ~T[07:00:00], left: :closed, right: :open}

      # complement(b) is a {left, right} tuple; the set operations
      # accept it directly.
      assert Intervals.diff(a, Intervals.complement(b)) == [
               %{from: ~T[02:00:00], until: ~T[07:00:00], left: :closed, right: :open}
             ]
    end
  end

  describe "diff/2" do
    test "diff intervals" do
      intervals1 = Intervals.new!(from: ~T[00:30:00], until: ~T[10:00:00])
      intervals2 = Intervals.new!(from: ~T[05:00:00], until: ~T[08:00:00])
      intervals3 = Intervals.new!(from: ~T[09:00:00], until: ~T[09:30:00])

      assert Intervals.diff(intervals1, intervals2).intervals === [
               %{from: ~T[00:30:00], until: ~T[05:00:00], left: :closed, right: :open},
               %{from: ~T[08:00:00], until: ~T[10:00:00], left: :closed, right: :open}
             ]

      assert Intervals.diff(intervals1, intervals3).intervals === [
               %{from: ~T[00:30:00], until: ~T[09:00:00], left: :closed, right: :open},
               %{from: ~T[09:30:00], until: ~T[10:00:00], left: :closed, right: :open}
             ]

      assert Intervals.diff(intervals2, intervals1).intervals === []
    end

    test "no overlap between intervals" do
      lhs = %{from: ~T[08:00:00], until: ~T[09:00:00], left: :closed, right: :closed}
      rhs = %{from: ~T[10:00:00], until: ~T[11:00:00], left: :closed, right: :closed}
      assert Intervals.diff(lhs, rhs) == lhs
    end

    test "partial overlap - lhs starts first" do
      lhs = %{from: ~T[08:00:00], until: ~T[10:00:00], left: :closed, right: :closed}
      rhs = %{from: ~T[09:00:00], until: ~T[11:00:00], left: :closed, right: :closed}

      assert Intervals.diff(lhs, rhs) == %{
               from: ~T[08:00:00],
               until: ~T[09:00:00],
               left: :closed,
               right: :open
             }
    end

    test "full overlap - lhs within rhs" do
      lhs = %{from: ~T[09:00:00], until: ~T[10:00:00], left: :closed, right: :closed}
      rhs = %{from: ~T[08:00:00], until: ~T[11:00:00], left: :closed, right: :closed}
      assert Intervals.diff(lhs, rhs) == nil
    end

    # [claude-code] Before the fix, the intersection of two whole
    # timelines complements to nil, and that nil crashed intersect/2.
    test "subtracting the whole timeline from itself leaves nothing" do
      whole = %{from: nil, until: nil, left: nil, right: nil}

      assert Intervals.diff(whole, whole) == nil
      assert Intervals.diff([whole], [whole]) == []
    end
  end

  # [claude-code] Successive subtraction over interval sets. Before the
  # fix, the multi-subtrahend diff unioned the pairwise diffs (so each
  # subtracted slot came back through the other diff), and a minuend
  # that overlapped no subtrahend was dropped from the result.
  describe "diff/2 over interval sets" do
    test "subtracting two busy slots removes both" do
      free = Intervals.new!(from: ~T[08:00:00], until: ~T[18:00:00])

      busy = [
        %{from: ~T[09:00:00], until: ~T[10:00:00], left: :closed, right: :open},
        %{from: ~T[12:00:00], until: ~T[13:00:00], left: :closed, right: :open}
      ]

      assert Intervals.diff(free, busy).intervals == [
               %{from: ~T[08:00:00], until: ~T[09:00:00], left: :closed, right: :open},
               %{from: ~T[10:00:00], until: ~T[12:00:00], left: :closed, right: :open},
               %{from: ~T[13:00:00], until: ~T[18:00:00], left: :closed, right: :open}
             ]
    end

    test "a minuend that overlaps no subtrahend stays whole" do
      kept = %{from: ~T[09:00:00], until: ~T[10:00:00], left: :closed, right: :open}
      busy = %{from: ~T[14:00:00], until: ~T[15:00:00], left: :closed, right: :open}

      assert Intervals.diff([kept], [busy]) == [kept]
    end

    test "an unbounded subtrahend cuts a bounded minuend" do
      # Before the fix, the from/until comparison helpers passed a nil
      # endpoint into Timex and raised Protocol.UndefinedError as soon
      # as a bounded and an unbounded interval met in a set operation.
      day = %{from: ~T[06:00:00], until: ~T[18:00:00], left: :closed, right: :open}
      before_eight = %{from: nil, until: ~T[08:00:00], left: nil, right: :open}

      assert Intervals.diff([day], [before_eight]) == [
               %{from: ~T[08:00:00], until: ~T[18:00:00], left: :closed, right: :open}
             ]
    end

    test "union merges a bounded interval into an unbounded one" do
      unbounded = %{from: ~T[08:00:00], until: nil, left: :closed, right: nil}
      bounded = %{from: ~T[06:00:00], until: ~T[09:00:00], left: :closed, right: :open}

      assert Intervals.union([unbounded], bounded) == [
               %{from: ~T[06:00:00], until: nil, left: :closed, right: nil}
             ]
    end

    test "intersect clips an unbounded interval to a bounded one" do
      unbounded = %{from: nil, until: ~T[10:00:00], left: nil, right: :open}
      bounded = %{from: ~T[05:00:00], until: ~T[11:00:00], left: :closed, right: :open}

      assert Intervals.intersect(unbounded, bounded) ==
               %{from: ~T[05:00:00], until: ~T[10:00:00], left: :closed, right: :open}
    end

    test "one subtrahend can cut across several minuends" do
      morning = %{from: ~T[08:00:00], until: ~T[12:00:00], left: :closed, right: :open}
      afternoon = %{from: ~T[13:00:00], until: ~T[18:00:00], left: :closed, right: :open}
      busy = %{from: ~T[11:00:00], until: ~T[14:00:00], left: :closed, right: :open}

      assert Intervals.diff([morning, afternoon], [busy]) == [
               %{from: ~T[08:00:00], until: ~T[11:00:00], left: :closed, right: :open},
               %{from: ~T[14:00:00], until: ~T[18:00:00], left: :closed, right: :open}
             ]
    end
  end
end
