defmodule Zocam.IntervalsTest do
  use ExUnit.Case
  doctest Zocam.Intervals

  alias Zocam.Intervals

  # [claude-code] Added 2026-08-05 (decision D3). The struct now uses
  # TypedStruct with `default: []`, so the bare literal IS the empty
  # set. Before, `%Intervals{}` meant `intervals: nil`, a value no
  # operation could take.
  describe "the struct" do
    test "the bare struct literal is the empty set" do
      assert %Intervals{}.intervals == []
    end

    test "the empty struct flows through the set operations" do
      piece = %{from: ~T[08:00:00], until: ~T[10:00:00], left: :closed, right: :open}

      assert Intervals.diff(%Intervals{}, [piece]).intervals == []
      assert Intervals.intersect(%Intervals{}, [piece]).intervals == []
      refute Intervals.overlaps?(%Intervals{}, [piece])
    end
  end

  # [claude-code] Added 2026-08-05 (decision D2, Linear YUR-55). One
  # rule for shapes: an operation on sets answers with the set struct,
  # whatever shape the operands came in; a piece constructor answers
  # with a piece. Before, the answer followed the shape of the first
  # argument, and every caller had to branch on three return shapes.
  describe "set operations always answer with the struct (D2)" do
    setup do
      %{
        piece: %{from: ~T[09:00:00], until: ~T[12:00:00], left: :closed, right: :open},
        other: %{from: ~T[11:00:00], until: ~T[17:00:00], left: :closed, right: :open}
      }
    end

    test "new!/1 answers with one piece, not a set" do
      assert Intervals.new!(from: ~T[09:00:00], until: ~T[17:00:00]) ==
               %{from: ~T[09:00:00], until: ~T[17:00:00], left: :closed, right: :open}
    end

    test "union/2 returns the struct for two bare pieces", %{piece: piece, other: other} do
      assert %Intervals{intervals: [%{from: ~T[09:00:00], until: ~T[17:00:00]}]} =
               Intervals.union(piece, other)
    end

    test "each operation returns the struct for every input shape", %{piece: piece} do
      shapes = [
        piece,
        [from: ~T[09:00:00], until: ~T[12:00:00]],
        [piece],
        %Intervals{intervals: [piece]}
      ]

      for shape <- shapes do
        assert %Intervals{} = Intervals.union(shape, piece)
        assert %Intervals{} = Intervals.intersect(shape, piece)
        assert %Intervals{} = Intervals.diff(shape, piece)
        assert %Intervals{} = Intervals.complement(shape)
        assert %Intervals{} = Intervals.compress(shape)
      end
    end

    test "a piece-level 'nothing remains' is the empty set, not nil", %{piece: piece} do
      assert Intervals.diff(piece, piece) == %Intervals{intervals: []}

      assert Intervals.intersect(piece, %{piece | from: ~T[14:00:00], until: ~T[15:00:00]}) ==
               %Intervals{intervals: []}
    end

    test "overlaps?/2 stays boolean and accepts all shapes", %{piece: piece, other: other} do
      assert Intervals.overlaps?(piece, other) == true
      assert Intervals.overlaps?([piece], %Intervals{intervals: [other]}) == true
      assert Intervals.overlaps?([from: ~T[09:00:00], until: ~T[12:00:00]], [other]) == true
    end
  end

  # [claude-code] Added 2026-08-05 (Linear YUR-79 and YUR-89). The
  # funnel must stop bad shapes with a taught error. Before, the
  # partial map re-entered the set clause forever (an infinite loop),
  # and the other shapes died with a bare FunctionClauseError.
  describe "the input funnel rejects bad shapes with a taught error" do
    @tag timeout: 2_000
    test "a partial map terminates with an error instead of looping (YUR-79)" do
      partial = %{from: ~T[09:00:00], until: ~T[12:00:00]}

      error = assert_raise ArgumentError, fn -> Intervals.diff(partial, partial) end
      assert error.message =~ ":left"
      assert error.message =~ ":right"
    end

    test "a map with :from but no :until raises and names the shape (YUR-89)" do
      # [cursor-agent] Changed 2026-08-06 (Linear YUR-72): the call
      # goes through apply/3 so the compile-time checker cannot see
      # the deliberate misuse and the suite stays free of warnings.
      error =
        assert_raise ArgumentError, fn ->
          apply(Intervals, :union, [%{from: ~T[09:00:00]}, %{from: ~T[10:00:00]}])
        end

      assert error.message =~ ":until"
    end

    test "a struct nested in a list raises and teaches the way out (YUR-89)" do
      set =
        Intervals.compress([
          %{from: ~T[09:00:00], until: ~T[12:00:00], left: :closed, right: :open}
        ])

      error = assert_raise ArgumentError, fn -> Intervals.compress([set]) end
      assert error.message =~ "intervals"
    end

    test "a scalar raises and names the accepted shapes (YUR-89)" do
      error =
        assert_raise ArgumentError, fn ->
          Intervals.intersect(5, %{
            from: ~T[09:00:00],
            until: ~T[12:00:00],
            left: :closed,
            right: :open
          })
        end

      assert error.message =~ "%Zocam.Intervals{}"
    end

    # [claude-code] Added 2026-08-05 (verifier pass, YUR-79/YUR-89).
    # Three shapes slipped past the first fix: an improper list, a
    # keyword list with a stray element, and a map with the four keys
    # plus extras. The first two died with a bare FunctionClauseError
    # deep inside Enum/Keyword; the third passed silently, and the
    # extra key survived into the result set and broke normal-form
    # equality. Every door must reject them with a taught error.
    @tag timeout: 2_000
    test "an improper list of maps raises and teaches the fix (YUR-89)" do
      good = %{from: ~T[09:00:00], until: ~T[17:00:00], left: :closed, right: :open}

      # [good | good] is a cons cell whose tail is a map, not a list.
      error = assert_raise ArgumentError, fn -> Intervals.compress([good | good]) end
      assert error.message =~ "improper"
      assert error.message =~ "%Zocam.Intervals{}"
    end

    @tag timeout: 2_000
    test "an improper keyword list raises and teaches the fix (YUR-89)" do
      error =
        assert_raise ArgumentError, fn ->
          Intervals.compress([{:from, ~T[09:00:00]} | ~T[17:00:00]])
        end

      assert error.message =~ "improper"
    end

    @tag timeout: 2_000
    test "an improper piece list inside the struct raises too (YUR-89)" do
      good = %{from: ~T[09:00:00], until: ~T[17:00:00], left: :closed, right: :open}

      error =
        assert_raise ArgumentError, fn ->
          Intervals.compress(%Intervals{intervals: [good | good]})
        end

      assert error.message =~ "improper"
    end

    test "an option list with a stray element raises and names it (YUR-89)" do
      error =
        assert_raise ArgumentError, fn ->
          Intervals.compress([{:from, ~T[09:00:00]}, :oops])
        end

      assert error.message =~ ":oops"

      # The same guard covers the piece constructor's door.
      improper = [{:from, ~T[09:00:00]} | ~T[17:00:00]]
      assert_raise ArgumentError, fn -> Intervals.new!(improper) end
    end

    # [cursor-agent] Added 2026-08-06 (Linear YUR-87). One operation
    # works on one kind of endpoint. A Time piece is a daily wall
    # window; a DateTime piece is one concrete window. The kernel
    # cannot compare the two kinds, so every door rejects the mix
    # with a lesson - before, Timex raised a bare protocol error far
    # from the mistake, possibly deep inside Span.ground/3.
    test "a piece cannot mix a Time and a DateTime endpoint (YUR-87)" do
      error =
        assert_raise ArgumentError, fn ->
          Intervals.new!(from: ~T[09:00:00], until: ~U[2026-01-01 18:00:00Z])
        end

      assert error.message =~ "Time"
      assert error.message =~ "DateTime"
      assert error.message =~ "ground"
    end

    test "a mixed map operand is stopped at the funnel (YUR-87)" do
      mixed = %{
        from: ~T[09:00:00],
        until: ~U[2026-01-01 18:00:00Z],
        left: :closed,
        right: :open
      }

      assert_raise ArgumentError, fn -> Intervals.compress(mixed) end
    end

    test "one operation cannot mix a Time set and a DateTime set (YUR-87)" do
      daily = Intervals.new!(from: ~T[09:00:00], until: ~T[17:00:00])

      jan7 = %{
        from: ~U[2026-01-07 00:00:00Z],
        until: ~U[2026-01-08 00:00:00Z],
        left: :closed,
        right: :open
      }

      for operation <- [
            fn -> Intervals.diff(jan7, daily) end,
            fn -> Intervals.union(jan7, daily) end,
            fn -> Intervals.intersect(daily, jan7) end,
            fn -> Intervals.compress([daily, jan7]) end,
            fn -> Intervals.overlaps?(jan7, daily) end
          ] do
        error = assert_raise ArgumentError, operation
        assert error.message =~ "ground"
      end
    end

    test "a ray beside a bounded piece of the same kind stays fine (YUR-87)" do
      # A nil endpoint has no kind: the one bounded side decides alone.
      ray = Intervals.new!(from: ~T[09:00:00])
      noon = Intervals.new!(from: ~T[12:00:00], until: ~T[13:00:00])

      assert %Intervals{} = Intervals.union(ray, noon)
    end

    test "a map with the four keys plus extras raises and names them (YUR-89)" do
      good = %{from: ~T[09:00:00], until: ~T[17:00:00], left: :closed, right: :open}

      # In a list operand.
      error =
        assert_raise ArgumentError, fn ->
          Intervals.compress([Map.put(good, :extra, 1)])
        end

      assert error.message =~ ":extra"

      # As a bare map operand.
      error =
        assert_raise ArgumentError, fn -> Intervals.union(Map.put(good, :note, "x"), good) end

      assert error.message =~ ":note"
    end
  end

  # [claude-code] Added 2026-08-05 (decision D1, kernel half). A set
  # is one value, and a value that holds pieces can hand them out:
  # enumerating a %Intervals{} yields its concrete interval() pieces,
  # in order. The moduledoc's "Enumerate a set" doctests carry the
  # lessons; these tests pin the protocol contract.
  describe "Enumerable (D1)" do
    @p1 %{from: ~T[08:00:00], until: ~T[09:00:00], left: :closed, right: :open}
    @p2 %{from: ~T[10:00:00], until: ~T[11:00:00], left: :closed, right: :open}
    @p3 %{from: ~T[12:00:00], until: ~T[13:00:00], left: :closed, right: :open}

    test "Enum.map walks the pieces in normal-form order" do
      set = Intervals.compress([@p3, @p1, @p2])

      assert Enum.map(set, & &1.from) == [~T[08:00:00], ~T[10:00:00], ~T[12:00:00]]
    end

    test "count is honest" do
      assert Enum.count(Intervals.compress([@p1, @p2])) == 2
    end

    test "member? asks about pieces, not about covered instants" do
      set = Intervals.compress([@p1])

      assert Enum.member?(set, @p1)
      refute Enum.member?(set, ~T[08:30:00])
    end

    test "slice is honest" do
      set = Intervals.compress([@p1, @p2, @p3])

      assert Enum.slice(set, 1, 2) == [@p2, @p3]
      assert Enum.at(set, 0) == @p1
    end

    test "the empty set enumerates to nothing" do
      assert Enum.to_list(%Intervals{}) == []
      assert Enum.count(%Intervals{}) == 0
    end
  end

  # [claude-code] Added 2026-08-05 (Linear YUR-84). An inverted
  # interval (from strictly after until) used to build, and then it
  # broke the algebra's laws: it was "completely before itself",
  # intersect lost it, diff of it with itself crashed, compress kept
  # two copies. Now no door lets one in, so each law holds for every
  # value that can exist.
  describe "inverted intervals are rejected (YUR-84)" do
    @valid_from ~T[06:00:00]
    @valid_until ~T[22:00:00]
    @inverted %{from: ~T[22:00:00], until: ~T[06:00:00], left: :closed, right: :open}

    test "new!/1 rejects from strictly after until, and teaches the wrap arc" do
      error =
        assert_raise ArgumentError, fn ->
          Intervals.new!(from: ~T[22:00:00], until: ~T[06:00:00])
        end

      assert error.message =~ "22:00"
      assert error.message =~ "arc"
    end

    test "new!/1 rejects an inverted DateTime pair too" do
      assert_raise ArgumentError, fn ->
        Intervals.new!(from: ~U[2026-01-02 00:00:00Z], until: ~U[2026-01-01 00:00:00Z])
      end
    end

    test "law: no interval is completely before itself" do
      x = Intervals.new!(from: @valid_from, until: @valid_until)

      refute Intervals.completely_before?(x, x)
      assert_raise ArgumentError, fn -> Intervals.compress([@inverted]) end
    end

    test "law: intersect(x, x) is x" do
      x = Intervals.new!(from: @valid_from, until: @valid_until)

      assert Intervals.intersect(x, x).intervals == [x]
      assert_raise ArgumentError, fn -> Intervals.intersect(@inverted, @inverted) end
    end

    test "law: diff([x], [x]) is the empty set" do
      x = Intervals.new!(from: @valid_from, until: @valid_until)

      assert Intervals.diff([x], [x]).intervals == []
      assert_raise ArgumentError, fn -> Intervals.diff([@inverted], [@inverted]) end
    end

    test "law: compress([x, x]) is [x]" do
      x = Intervals.new!(from: @valid_from, until: @valid_until)

      assert Intervals.compress([x, x]).intervals == [x]
      assert_raise ArgumentError, fn -> Intervals.compress([@inverted, @inverted]) end
    end
  end

  # [claude-code] Added 2026-08-05 (Linear YUR-85). from == until
  # covers the single instant [t, t] only when BOTH sides are closed;
  # with any open side the interval covers nothing. Such zero-width
  # pieces used to survive compress/1 and reach schedulers as
  # zero-width "slots".
  describe "compress/1 drops intervals that cover no instant (YUR-85)" do
    @t ~T[12:00:00]

    test "[t, t) covers nothing and is dropped" do
      assert Intervals.compress([%{from: @t, until: @t, left: :closed, right: :open}]).intervals ==
               []
    end

    test "(t, t) covers nothing and is dropped" do
      assert Intervals.compress([%{from: @t, until: @t, left: :open, right: :open}]).intervals ==
               []
    end

    test "(t, t] covers nothing and is dropped" do
      assert Intervals.compress([%{from: @t, until: @t, left: :open, right: :closed}]).intervals ==
               []
    end

    test "[t, t] covers exactly one instant and is kept" do
      point = %{from: @t, until: @t, left: :closed, right: :closed}

      assert Intervals.compress([point]).intervals == [point]
    end

    test "a no-instant piece vanishes from a bigger set" do
      real = %{from: ~T[08:00:00], until: ~T[10:00:00], left: :closed, right: :open}
      empty = %{from: @t, until: @t, left: :closed, right: :open}

      assert Intervals.compress([real, empty]).intervals == [real]
    end
  end

  # [claude-code] Added 2026-08-05 (Linear YUR-86). The kernel can
  # only order Time and DateTime endpoints. A weekday atom used to be
  # stored and then crashed the first comparison; a NaiveDateTime or
  # a Date "worked" but fell to structural ==, which silently unioned
  # a real hole away. Now interval_from_opts/1 rejects them at the
  # door, naming the side and the value.
  describe "endpoints the kernel cannot compare are rejected (YUR-86)" do
    test "new!/1 rejects weekday atoms and names the side and the value" do
      error =
        assert_raise ArgumentError, fn ->
          Intervals.new!(from: :saturday, until: :sunday)
        end

      assert error.message =~ "from"
      assert error.message =~ ":saturday"
    end

    test "new!/1 rejects a NaiveDateTime endpoint" do
      error =
        assert_raise ArgumentError, fn ->
          Intervals.new!(from: ~N[2026-01-01 09:00:00])
        end

      assert error.message =~ "~N[2026-01-01 09:00:00]"
    end

    test "new!/1 rejects a Date endpoint on the until side" do
      error =
        assert_raise ArgumentError, fn ->
          Intervals.new!(until: ~D[2026-01-01])
        end

      assert error.message =~ "until"
      assert error.message =~ "~D[2026-01-01]"
    end

    test "a map with an incomparable endpoint is stopped at the funnel" do
      bad = %{from: ~D[2026-01-01], until: nil, left: :closed, right: nil}

      assert_raise ArgumentError, fn -> Intervals.compress([bad]) end
    end
  end

  # [claude-code] Added 2026-08-05 (Linear YUR-88). Closings were
  # never validated: a dead closing on an unbounded side was kept,
  # and a bogus atom (left: :half) propagated into results, where it
  # silently behaved as :open. The rule, per side: an unbounded side
  # (endpoint nil) has no boundary, so its closing is nil; a bounded
  # side is :open or :closed.
  describe "closings are validated per side (YUR-88)" do
    test "a dead closing on an unbounded side raises" do
      error =
        assert_raise ArgumentError, fn ->
          Intervals.new!(from: ~T[08:00:00], right: :closed)
        end

      assert error.message =~ "right"
    end

    test "a bogus closing atom raises and names it" do
      error =
        assert_raise ArgumentError, fn ->
          Intervals.new!(from: ~T[08:00:00], until: ~T[10:00:00], left: :half)
        end

      assert error.message =~ ":half"
    end

    test "a nil closing on a bounded side raises" do
      error =
        assert_raise ArgumentError, fn ->
          Intervals.new!(from: ~T[08:00:00], until: ~T[10:00:00], left: nil)
        end

      assert error.message =~ "left"
    end

    test "a map with a bad closing is stopped at the funnel" do
      bad = %{from: ~T[08:00:00], until: ~T[10:00:00], left: :closed, right: :sometimes}

      assert_raise ArgumentError, fn -> Intervals.compress([bad]) end
    end
  end

  # [claude-code] Changed 2026-08-05 (decision D2): new!/1 builds one
  # piece map now, and the multi-entry `interval:` form died with
  # that. A set comes from a set operation, for example compress/1.
  describe "new/1" do
    test "the piece has from [time] and no until (a ray)" do
      piece = Intervals.new!(from: ~T[00:30:00])

      assert piece.from == ~T[00:30:00]
      assert piece.until == nil
    end

    test "the piece has from [time] and until [time]" do
      piece = Intervals.new!(from: ~T[00:30:00], until: ~T[10:00:00])

      assert %{from: from, until: until} = piece
      assert from == ~T[00:30:00]
      assert until == ~T[10:00:00]
    end

    test "new!/1 fails if more than one from or until is passed" do
      assert_raise ArgumentError, fn ->
        Intervals.new!(from: ~T[00:30:00], until: ~T[10:00:00], from: ~T[00:30:00])
      end
    end
  end

  describe "compress/1 while creating a set" do
    test "intervals get unionized when possible" do
      intervals =
        Intervals.compress([
          [from: ~T[00:30:00], until: ~T[10:00:00]],
          [from: ~T[05:00:00], until: ~T[08:00:00]],
          [from: ~T[09:00:00], until: ~T[12:00:00]]
        ])

      assert [%{from: from, until: until}] = intervals.intervals
      assert from == ~T[00:30:00]
      assert until == ~T[12:00:00]
    end
  end

  test "two intervals overlaps" do
    interval1 = [from: ~T[00:30:00], until: ~T[10:00:00]]
    interval2 = [from: ~T[09:00:00], until: ~T[12:00:00]]
    interval3 = [from: ~T[10:00:00]]
    # [claude-code] Changed 2026-08-05 (Linear YUR-88): left was
    # :closed here, a dead closing on the unbounded side. The funnel
    # rejects that now, and the unbounded side carries nil.
    interval4 = %{until: ~T[09:00:00], from: nil, right: :open, left: nil}

    assert Intervals.overlaps?(interval1, interval2) === true
    assert Intervals.overlaps?(interval1, interval3) === false
    assert Intervals.overlaps?(interval1, interval4) === true
    assert Intervals.overlaps?(interval2, interval3) === true
    assert Intervals.overlaps?(interval2, interval4) === false
    assert Intervals.overlaps?(interval3, [interval1, interval4]) === false
  end

  test "intersect intervals" do
    piece1 = Intervals.new!(from: ~T[00:30:00], until: ~T[10:00:00])
    piece2 = Intervals.new!(from: ~T[05:00:00], until: ~T[11:00:00])

    expected = [
      %{from: ~T[05:00:00], until: ~T[10:00:00], left: :closed, right: :open}
    ]

    assert Intervals.intersect(piece1, piece2).intervals === expected
    assert Intervals.intersect(piece2, piece1).intervals === expected

    set3 =
      Intervals.compress([
        [from: ~T[11:00:00], until: ~T[12:00:00]],
        [from: ~T[13:00:00], until: ~T[14:00:00]]
      ])

    set4 =
      Intervals.compress([
        [from: ~T[10:00:00], until: ~T[11:00:00]],
        [from: ~T[12:00:00], until: ~T[13:00:00]]
      ])

    assert Intervals.intersect(piece1, set3).intervals === []
    assert Intervals.intersect(set3, set4).intervals === []
  end

  test "complement intervals" do
    piece = Intervals.new!(from: ~T[00:30:00], until: ~T[10:00:00])

    assert [i1, i2] = Intervals.complement(piece).intervals
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
      assert Intervals.complement(%{from: nil, until: ~T[05:00:00], left: nil, right: :open}).intervals ==
               [%{from: ~T[05:00:00], until: nil, left: :closed, right: nil}]
    end

    test "complement of a right-unbounded interval ends at its start" do
      assert Intervals.complement(%{from: ~T[05:00:00], until: nil, left: :closed, right: nil}).intervals ==
               [%{from: nil, until: ~T[05:00:00], left: nil, right: :open}]
    end

    test "complement of the whole timeline is the empty set" do
      whole = %{from: nil, until: nil, left: nil, right: nil}

      assert Intervals.complement([whole]).intervals == []
    end

    test "complement stays empty once the pieces cover everything" do
      covering = [
        %{from: nil, until: ~T[05:00:00], left: nil, right: :open},
        %{from: ~T[03:00:00], until: nil, left: :open, right: nil},
        %{from: ~T[08:00:00], until: ~T[09:00:00], left: :closed, right: :open}
      ]

      assert Intervals.complement(covering).intervals == []
    end
  end

  # [claude-code] Coalescing of touching intervals. Before the fix,
  # compress/union kept [a, b) and [b, c) separate although together
  # they cover [a, c) with no hole.
  describe "compress/1 coalescing of touching intervals" do
    test "touching closed-open intervals merge into one" do
      intervals =
        Intervals.compress([
          [from: ~T[06:00:00], until: ~T[12:00:00]],
          [from: ~T[12:00:00], until: ~T[18:00:00]]
        ])

      assert [%{from: ~T[06:00:00], until: ~T[18:00:00], left: :closed, right: :open}] =
               intervals.intervals
    end

    test "the merge happens whatever the insertion order" do
      intervals =
        Intervals.compress([
          [from: ~T[12:00:00], until: ~T[18:00:00]],
          [from: ~T[06:00:00], until: ~T[12:00:00]]
        ])

      assert [%{from: ~T[06:00:00], until: ~T[18:00:00]}] = intervals.intervals
    end

    test "a chain of touching intervals collapses into one" do
      intervals =
        Intervals.compress([
          [from: ~T[00:00:00], until: ~T[06:00:00]],
          [from: ~T[12:00:00], until: ~T[18:00:00]],
          [from: ~T[06:00:00], until: ~T[12:00:00]]
        ])

      assert [%{from: ~T[00:00:00], until: ~T[18:00:00]}] = intervals.intervals
    end

    test "either side covering the shared endpoint is enough" do
      # Left side covers 12:00: [06, 12] plus (12, 18).
      merged =
        Intervals.compress([
          %{from: ~T[06:00:00], until: ~T[12:00:00], left: :closed, right: :closed},
          %{from: ~T[12:00:00], until: ~T[18:00:00], left: :open, right: :open}
        ])

      assert [%{from: ~T[06:00:00], until: ~T[18:00:00], left: :closed, right: :open}] =
               merged.intervals
    end

    test "two open sides leave a hole and do not merge" do
      # (06, 12) plus (12, 18): the instant 12:00 is in neither.
      kept =
        Intervals.compress([
          %{from: ~T[06:00:00], until: ~T[12:00:00], left: :open, right: :open},
          %{from: ~T[12:00:00], until: ~T[18:00:00], left: :open, right: :open}
        ])

      assert length(kept.intervals) == 2
    end

    test "union/2 merges a new interval that touches an existing one" do
      existing = [%{from: ~T[08:00:00], until: ~T[12:00:00], left: :closed, right: :open}]
      new = %{from: ~T[12:00:00], until: ~T[14:00:00], left: :closed, right: :open}

      assert [%{from: ~T[08:00:00], until: ~T[14:00:00], left: :closed, right: :open}] =
               Intervals.union(existing, new).intervals
    end

    test "mixed microsecond precision does not fake an overlap" do
      # Same instant, different precision: structural == is false for
      # ~T[10:00:00] vs ~T[10:00:00.000000], but they are the same
      # moment. Both sides open at 10:00 - the hole must survive.
      a = %{from: ~T[09:00:00], until: ~T[10:00:00], left: :open, right: :open}
      b = %{from: ~T[10:00:00.000000], until: ~T[11:00:00], left: :open, right: :open}

      refute Intervals.overlaps?(a, b)
      assert length(Intervals.compress([a, b]).intervals) == 2
    end

    test "mixed microsecond precision still coalesces a covered endpoint" do
      a = %{from: ~T[06:00:00], until: ~T[12:00:00], left: :closed, right: :open}
      b = %{from: ~T[12:00:00.000], until: ~T[18:00:00], left: :closed, right: :open}

      assert [%{from: ~T[06:00:00], until: ~T[18:00:00]}] = Intervals.compress([a, b]).intervals
    end
  end

  # [claude-code] The algebra is closed over the empty set it can
  # produce: complement of a covering set and diff(x, x) both return
  # the empty struct, and every set operation must accept the empty
  # list and the empty struct back.
  # Changed 2026-08-05 (decision D2): the answers are structs now.
  describe "empty set closure" do
    test "set operations accept the empty set" do
      a = [%{from: ~T[08:00:00], until: ~T[10:00:00], left: :closed, right: :open}]
      whole = %{from: nil, until: nil, left: nil, right: nil}

      assert Intervals.diff(a, []).intervals == a
      assert Intervals.diff([], a).intervals == []
      assert Intervals.intersect(a, []).intervals == []
      refute Intervals.overlaps?(a, [])
      assert Intervals.complement([]).intervals == [whole]
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

      assert Intervals.diff(a, Intervals.complement(covering)).intervals == a
    end

    test "a complement result feeds straight back into set operations" do
      a = [%{from: ~T[00:00:00], until: ~T[10:00:00], left: :closed, right: :open}]
      b = %{from: ~T[02:00:00], until: ~T[07:00:00], left: :closed, right: :open}

      # complement(b) is a struct (two rays); the set operations
      # accept it directly.
      assert Intervals.diff(a, Intervals.complement(b)).intervals == [
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
      assert Intervals.diff(lhs, rhs).intervals == [lhs]
    end

    test "partial overlap - lhs starts first" do
      lhs = %{from: ~T[08:00:00], until: ~T[10:00:00], left: :closed, right: :closed}
      rhs = %{from: ~T[09:00:00], until: ~T[11:00:00], left: :closed, right: :closed}

      assert Intervals.diff(lhs, rhs).intervals == [
               %{
                 from: ~T[08:00:00],
                 until: ~T[09:00:00],
                 left: :closed,
                 right: :open
               }
             ]
    end

    test "full overlap - lhs within rhs" do
      lhs = %{from: ~T[09:00:00], until: ~T[10:00:00], left: :closed, right: :closed}
      rhs = %{from: ~T[08:00:00], until: ~T[11:00:00], left: :closed, right: :closed}
      assert Intervals.diff(lhs, rhs).intervals == []
    end

    # [claude-code] Before the fix, the intersection of two whole
    # timelines complements to nil, and that nil crashed intersect/2.
    test "subtracting the whole timeline from itself leaves nothing" do
      whole = %{from: nil, until: nil, left: nil, right: nil}

      assert Intervals.diff(whole, whole).intervals == []
      assert Intervals.diff([whole], [whole]).intervals == []
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

      assert Intervals.diff([kept], [busy]).intervals == [kept]
    end

    test "an unbounded subtrahend cuts a bounded minuend" do
      # Before the fix, the from/until comparison helpers passed a nil
      # endpoint into Timex and raised Protocol.UndefinedError as soon
      # as a bounded and an unbounded interval met in a set operation.
      day = %{from: ~T[06:00:00], until: ~T[18:00:00], left: :closed, right: :open}
      before_eight = %{from: nil, until: ~T[08:00:00], left: nil, right: :open}

      assert Intervals.diff([day], [before_eight]).intervals == [
               %{from: ~T[08:00:00], until: ~T[18:00:00], left: :closed, right: :open}
             ]
    end

    test "union merges a bounded interval into an unbounded one" do
      unbounded = %{from: ~T[08:00:00], until: nil, left: :closed, right: nil}
      bounded = %{from: ~T[06:00:00], until: ~T[09:00:00], left: :closed, right: :open}

      assert Intervals.union([unbounded], bounded).intervals == [
               %{from: ~T[06:00:00], until: nil, left: :closed, right: nil}
             ]
    end

    test "intersect clips an unbounded interval to a bounded one" do
      unbounded = %{from: nil, until: ~T[10:00:00], left: nil, right: :open}
      bounded = %{from: ~T[05:00:00], until: ~T[11:00:00], left: :closed, right: :open}

      assert Intervals.intersect(unbounded, bounded).intervals ==
               [%{from: ~T[05:00:00], until: ~T[10:00:00], left: :closed, right: :open}]
    end

    test "one subtrahend can cut across several minuends" do
      morning = %{from: ~T[08:00:00], until: ~T[12:00:00], left: :closed, right: :open}
      afternoon = %{from: ~T[13:00:00], until: ~T[18:00:00], left: :closed, right: :open}
      busy = %{from: ~T[11:00:00], until: ~T[14:00:00], left: :closed, right: :open}

      assert Intervals.diff([morning, afternoon], [busy]).intervals == [
               %{from: ~T[08:00:00], until: ~T[11:00:00], left: :closed, right: :open},
               %{from: ~T[14:00:00], until: ~T[18:00:00], left: :closed, right: :open}
             ]
    end
  end
end
