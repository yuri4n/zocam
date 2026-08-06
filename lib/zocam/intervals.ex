# [claude-code] The code in this module is the project owner's linear
# interval kernel. Claude Code added the comments and docstrings on
# 2026-08-04 with a one-time permission, moved the module from the
# s7r app into the zocam library, and narrowed timables/0 (see
# below). Lines marked "Changed" are earlier reviewed fixes; the
# bodies are otherwise the owner's.
# Changed (2026-08-05): doctests added to the docstrings for the
# "Examples and recipes" rule (already wired in
# test/zocam/intervals_test.exs). Docstrings only; no body changed.
# Changed (2026-08-05, second pass): decisions D2 and D3 and the bug
# batch YUR-79/84/85/86/88/89. The struct is a TypedStruct now, the
# set operations always answer with the struct, one funnel validates
# every operand, and new!/1 builds one piece. The piece-level
# algebra (intersect_pieces/2 and friends) keeps the owner's bodies
# as private helpers.
defmodule Zocam.Intervals do
  @moduledoc """
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
  """

  use Timex
  use TypedStruct

  # [claude-code] Whether an endpoint belongs to its interval.
  @type closing :: :open | :closed

  # [claude-code] Changed (2026-08-04): narrowed from
  # `Time.t() | DateTime.t() | month() | weekday()`. Weekday and month
  # atoms cannot be ordered by the comparison helpers below (Timex
  # raised on every one), so they were data no operation could touch.
  # The calendar vocabulary now lives in `Zocam.Point`, and
  # `Zocam.Span.ground/3` is the path from "a Saturday" to concrete
  # intervals. The kernel stays calendar-free.
  @type timables :: Time.t() | DateTime.t()

  @type only_from :: [from: timables(), left: closing(), right: closing()]
  @type only_until :: [until: timables(), left: closing(), right: closing()]
  @type both :: [from: timables(), until: timables(), left: closing(), right: closing()]
  @type interval_opts :: only_from() | only_until() | both()

  # [claude-code] Typedoc added (2026-08-05); see "The four names"
  # in the Zocam moduledoc.
  @typedoc """
  One concrete piece of the timeline: a plain map with exactly four
  keys. It happens once — nothing repeats here. A `nil` endpoint
  means "unbounded on this side" (a ray). The symbolic counterpart
  that *does* repeat is `Zocam.Span.Arc`.
  """
  @type interval :: %{
          from: timables() | nil,
          until: timables() | nil,
          left: closing() | nil,
          right: closing() | nil
        }

  defguard is_interval(i)
           when is_map_key(i, :from) and is_map_key(i, :until) and
                  is_map_key(i, :left) and is_map_key(i, :right)

  @type valid_interval :: interval_opts() | interval()

  # [claude-code] Changed (2026-08-05): TypedStruct replaces the bare
  # defstruct (decision D3), so the struct type and the struct fields
  # are one definition. The default [] makes the bare literal
  # `%Zocam.Intervals{}` the empty set; before, it meant
  # `intervals: nil`, a value no operation could take. The list may
  # be empty: the set operations produce the empty set (diff(x, x),
  # complement of a covering set) and ground/3 can find nothing in a
  # horizon.
  typedstruct do
    @typedoc """
    A concrete *set* of pieces: the struct wraps one list of
    `interval/0` maps, which `compress/1` keeps sorted and disjoint.
    An empty list inside is the empty set, and so is the bare
    literal `%Zocam.Intervals{}`. This is what `Zocam.Span.ground/3`
    returns. The symbolic counterpart is `t:Zocam.Span.t/0`.
    """
    field :intervals, [interval()], default: []
  end

  # [claude-code] Changed (2026-08-05): the {:interval, opts} entry
  # form died with the multi-interval new!/1 (decision D2). A list
  # operand holds interval maps and option lists only.
  @type valid_intervals :: [interval() | interval_opts()] | t()

  @type at_least_one_valid :: valid_interval() | valid_intervals()

  # [claude-code] Comment only: complementing an interval flips each
  # closing - the boundary instant moves to the other side. nil stays
  # nil because an unbounded side has no boundary to flip.
  defp opposite_closing(:open), do: :closed
  defp opposite_closing(:closed), do: :open
  defp opposite_closing(nil), do: nil

  @doc """
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
  """
  # [claude-code] Changed (2026-08-05, YUR-89 verifier pass): the
  # shape guard came first. Keyword.get_values/2 raised a bare
  # FunctionClauseError on an improper list ([{:from, a} | b]) and on
  # a stray non-pair element, so the taught checks below were never
  # reached.
  @spec check_interval_opts!(interval_opts()) :: interval_opts()
  def check_interval_opts!(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError,
            "Invalid options: an interval option list holds {key, value} pairs " <>
              "only, and #{inspect(first_non_pair(opts))} is not one. Got: #{inspect(opts)}"
    end

    get_opts = fn key -> Keyword.get_values(opts, key) end

    froms = get_opts.(:from)
    untils = get_opts.(:until)
    left = get_opts.(:left)
    right = get_opts.(:right)

    cond do
      [froms, untils, left, right] |> Enum.map(&Enum.count/1) |> Enum.any?(&(&1 > 1)) ->
        raise ArgumentError,
              "Invalid options: from, until, left and right cannot be specified more than once"

      [froms, untils] |> Enum.map(&Enum.count/1) |> Enum.all?(&(&1 == 0)) ->
        raise ArgumentError,
              "Invalid options: from or until must be specified"

      true ->
        opts
    end
  end

  @doc """
  Build the interval map from an option list. A missing side stays
  `nil` (unbounded). The default closings are `:closed` on the left
  and `:open` on the right, the half-open convention that lets
  adjacent intervals tile without overlap; an absent side gets `nil`.

      iex> Zocam.Intervals.interval_from_opts(from: ~T[09:00:00])
      %{from: ~T[09:00:00], until: nil, left: :closed, right: nil}
  """
  # [claude-code] Changed (2026-08-05): the built map now passes the
  # piece gate (check_piece!/1), so an invalid piece cannot leave
  # this function.
  @spec interval_from_opts(interval_opts()) :: interval()
  def interval_from_opts(opts) do
    from = Keyword.get(opts, :from, nil)
    until = Keyword.get(opts, :until, nil)
    left = Keyword.get(opts, :left, (from && :closed) || nil)
    right = Keyword.get(opts, :right, (until && :open) || nil)

    check_piece!(%{from: from, until: until, left: left, right: right})
  end

  @doc """
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
  """
  # [claude-code] Changed (2026-08-05, decision D2): new!/1 is the
  # piece constructor now. It used to build a whole compressed set
  # (with a multi-entry `interval:` form); the set builders are the
  # set operations themselves.
  @spec new!(interval_opts()) :: interval()
  def new!(opts) when is_list(opts) do
    opts
    |> check_interval_opts!()
    |> interval_from_opts()
  end

  # [claude-code] Added (2026-08-05): the shapes the funnel accepts,
  # spelled once for every rejection message. (It sits before the
  # piece gate because the gate's messages read it at compile time.)
  @accepted_shapes "The set operations accept: a %Zocam.Intervals{} struct, " <>
                     "one interval map with the four keys :from, :until, :left, " <>
                     "and :right, one keyword list of interval options " <>
                     "(from:/until:/left:/right:), or a list of interval maps " <>
                     "and option lists. Build one valid piece with " <>
                     "Zocam.Intervals.new!/1."

  # [claude-code] Added (2026-08-05): the one gate for one piece.
  # Every interval map that enters the kernel passes here, whatever
  # door it came through (new!/1, interval_from_opts/1, or a map
  # handed to a set operation). The checks close YUR-86 (endpoints),
  # YUR-88 (closings), YUR-84 (order), and the exact-keys rule
  # (YUR-89), one item at a time.
  @spec check_piece!(interval()) :: interval()
  defp check_piece!(piece) do
    piece
    |> check_exact_keys!()
    |> check_endpoints!()
    |> check_closings!()
    |> check_order!()
  end

  # [claude-code] Added (2026-08-05, YUR-89 verifier pass): a map
  # with the four keys AND more is not a piece. The extra keys would
  # ride into the result set, and then two sets that cover the same
  # instants compare unequal (normal-form equality breaks on the
  # stowaway key). The funnel promises a taught error for every shape
  # that looks like an interval and is not exactly one, so this map
  # is rejected, not silently stripped: a silent strip would hide the
  # caller's mistake.
  @spec check_exact_keys!(interval()) :: interval()
  defp check_exact_keys!(piece) when map_size(piece) == 4, do: piece

  defp check_exact_keys!(piece) do
    extras =
      piece
      |> Map.keys()
      |> Kernel.--([:from, :until, :left, :right])
      |> Enum.map_join(" and ", &inspect/1)

    raise ArgumentError,
          "This map is not an interval: besides the four keys it carries " <>
            "#{extras}. Extra keys ride into the result set and break " <>
            "normal-form equality, so drop them, or build the piece with " <>
            "Zocam.Intervals.new!/1. Got: #{inspect(piece)}. " <> @accepted_shapes
  end

  # [claude-code] Added (2026-08-05, YUR-89 verifier pass): the first
  # element that is not a {atom, value} pair, for the option-list
  # rejection message. On an improper list the "element" can be the
  # tail itself. Safe on any term, where Keyword functions are not.
  @spec first_non_pair(term()) :: term()
  defp first_non_pair([{key, _value} | rest]) when is_atom(key), do: first_non_pair(rest)
  defp first_non_pair([other | _rest]), do: other
  defp first_non_pair(tail), do: tail

  # [claude-code] Added (2026-08-05, YUR-89 verifier pass): stop an
  # improper list before Enum or Keyword walks into its tail and dies
  # with a bare FunctionClauseError. is_list/1 only checks the first
  # cons cell, so [a | b] with a non-list b passes every list guard;
  # this walk checks the whole spine.
  @spec check_proper_list!(maybe_improper_list(term(), term())) :: [term()]
  defp check_proper_list!(list) do
    if proper_list?(list), do: list, else: reject_improper!(list)
  end

  @spec proper_list?(term()) :: boolean()
  defp proper_list?([]), do: true
  defp proper_list?([_head | tail]), do: proper_list?(tail)
  defp proper_list?(_tail), do: false

  @spec reject_improper!(term()) :: no_return()
  defp reject_improper!(list) do
    raise ArgumentError,
          "This list is improper: its tail is not a list. It usually comes " <>
            "from [a | b] where b is one piece and not a list - write [a, b] " <>
            "instead. Got: #{inspect(list)}. " <> @accepted_shapes
  end

  @doc """
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
  """
  # [claude-code] Added (2026-08-05, Linear YUR-88). This is the
  # closing rule lifted out of Zocam.Span.check_absolute!/1 into one
  # shared, public place; Span calls it instead of keeping a copy.
  @spec check_closings!(interval()) :: interval()
  def check_closings!(interval) do
    for {side, closing, endpoint} <- [
          {:left, interval.left, interval.from},
          {:right, interval.right, interval.until}
        ] do
      valid? = if endpoint == nil, do: closing == nil, else: closing in [:open, :closed]

      unless valid? do
        raise ArgumentError,
              "#{side}: must be :open or :closed on a bounded side, " <>
                "nil on an unbounded side, got #{inspect(closing)}"
      end
    end

    interval
  end

  @doc """
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
  """
  # [claude-code] Added (2026-08-05, Linear YUR-86). The wording
  # mirrors Zocam.Span.check_absolute!/1, which runs the same kind
  # of door check one layer up (there only DateTime passes).
  @spec check_endpoints!(interval()) :: interval()
  def check_endpoints!(interval) do
    for {side, value} <- [from: interval.from, until: interval.until], value != nil do
      unless match?(%Time{}, value) or match?(%DateTime{}, value) do
        raise ArgumentError,
              "#{side}: must be a Time, a DateTime, or nil, got #{inspect(value)}. " <>
                "Calendar values (:saturday, :may) belong to Zocam.Point, and " <>
                "Zocam.Span.ground/3 turns them into kernel intervals. A " <>
                "NaiveDateTime or a Date is rejected too: without a timezone it " <>
                "names no instant the kernel can compare."
      end
    end

    interval
  end

  @doc """
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
  """
  # [claude-code] Added (2026-08-05, Linear YUR-84). A nil side has
  # no order to check, and mixed Time/DateTime endpoints have no
  # order here (the moduledoc forbids mixing them) - both fall
  # through to the last clause.
  @spec check_order!(interval()) :: interval()
  def check_order!(%{from: %Time{} = from, until: %Time{} = until} = interval) do
    if Time.compare(from, until) == :gt, do: raise_inverted!(from, until)
    interval
  end

  def check_order!(%{from: %DateTime{} = from, until: %DateTime{} = until} = interval) do
    if DateTime.compare(from, until) == :gt, do: raise_inverted!(from, until)
    interval
  end

  def check_order!(interval), do: interval

  @spec raise_inverted!(timables(), timables()) :: no_return()
  defp raise_inverted!(from, until) do
    raise ArgumentError,
          "from #{inspect(from)} is after until #{inspect(until)}: an interval " <>
            "runs forward. For a window that crosses midnight, such as " <>
            "22:00..06:00, build a wrapping arc with Zocam.Span.arc!/1 instead."
  end

  @doc """
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
  """
  # [claude-code] Changed (2026-08-05, YUR-79 and YUR-89): rebuilt.
  # The old funnel matched a map on :from/:until alone, so a partial
  # map slipped through as a "piece", failed the four-key guard of
  # the piece-level operation, fell back into the set clause, and
  # looped forever. It also let {left, right} tuples and nil in
  # (piece-level results that no longer exist) and died with a bare
  # FunctionClauseError on a nested struct or a scalar.
  # Changed (2026-08-05, verifier pass): every list walks through
  # check_proper_list!/1 first - an improper list passed is_list/1
  # and then died with a bare FunctionClauseError inside Enum or
  # Keyword. The piece clauses exclude structs, so a foreign struct
  # with the four field names falls to the taught rejection.
  @spec check_and_extract_as_list!(at_least_one_valid()) :: [interval()]
  def check_and_extract_as_list!(%__MODULE__{intervals: pieces}) when is_list(pieces) do
    pieces
    |> check_proper_list!()
    |> Enum.map(&check_element!/1)
  end

  def check_and_extract_as_list!(%{from: _, until: _, left: _, right: _} = piece)
      when not is_struct(piece) do
    [check_piece!(piece)]
  end

  def check_and_extract_as_list!(%{} = other) when not is_struct(other), do: reject!(other)

  def check_and_extract_as_list!(list) when is_list(list) do
    check_proper_list!(list)

    if root_interval_opts?(list) do
      [list |> check_interval_opts!() |> interval_from_opts()]
    else
      Enum.map(list, &check_element!/1)
    end
  end

  def check_and_extract_as_list!(other), do: reject!(other)

  # [claude-code] Added (2026-08-05): one element of a list operand.
  # A nested struct is rejected with its own lesson: flatten it
  # first, or pass it alone.
  @spec check_element!(interval() | interval_opts()) :: interval()
  defp check_element!(%__MODULE__{} = struct) do
    raise ArgumentError,
          "A %Zocam.Intervals{} struct cannot sit inside a list. Pass the " <>
            "struct alone, or pass its .intervals list. Got: #{inspect(struct)}. " <>
            @accepted_shapes
  end

  defp check_element!(%{from: _, until: _, left: _, right: _} = piece)
       when not is_struct(piece),
       do: check_piece!(piece)

  defp check_element!(element) when is_list(element) do
    check_proper_list!(element)

    if root_interval_opts?(element) do
      element |> check_interval_opts!() |> interval_from_opts()
    else
      reject!(element)
    end
  end

  defp check_element!(other), do: reject!(other)

  # [claude-code] Added (2026-08-05): the taught rejection. A plain
  # map gets told which of the four keys it misses; everything else
  # gets the list of accepted shapes.
  @spec reject!(term()) :: no_return()
  defp reject!(%{} = map) when not is_struct(map) do
    missing =
      [:from, :until, :left, :right]
      |> Enum.reject(&Map.has_key?(map, &1))
      |> Enum.map_join(" and ", &inspect/1)

    raise ArgumentError,
          "This map is not an interval: it misses the keys #{missing}. " <>
            "Got: #{inspect(map)}. " <> @accepted_shapes
  end

  defp reject!(other) do
    raise ArgumentError,
          "Cannot read this value as intervals: #{inspect(other)}. " <> @accepted_shapes
  end

  # [claude-code] Added (2026-08-05): does the list spell ONE interval
  # at its root (from:/until: directly in it)? The old check was
  # Keyword.has_key?/2, whose contract admits only keyword lists -
  # Dialyzer then proved that a plain list of interval maps (what
  # Zocam.Span passes) "can never succeed". This scan accepts any
  # element shape, so the contract now matches the funnel's intent.
  @spec root_interval_opts?([term()]) :: boolean()
  defp root_interval_opts?(opts) do
    Enum.any?(opts, fn
      {:from, _} -> true
      {:until, _} -> true
      _other -> false
    end)
  end

  # [claude-code] Instant equality for endpoints. Structural == misses
  # equal instants written differently (Time microsecond precision,
  # a DateTime in another zone), while Timex.before?/after? treat them
  # as equal - classification and ordering must share one notion of
  # equality, or a hole between two open intervals silently merges.
  @spec same_instant?(timables() | nil, timables() | nil) :: boolean()
  defp same_instant?(%Time{} = a, %Time{} = b), do: Time.compare(a, b) == :eq
  defp same_instant?(%DateTime{} = a, %DateTime{} = b), do: DateTime.compare(a, b) == :eq
  defp same_instant?(a, b), do: a == b

  @doc """
  Is `lhs` entirely before `rhs`, with no shared instant? Touching
  endpoints count as "before" only when at least one side is `:open`
  (the shared instant then belongs to at most one of them).

      iex> Zocam.Intervals.completely_before?(
      ...>   %{from: ~T[09:00:00], until: ~T[12:00:00], left: :closed, right: :open},
      ...>   %{from: ~T[12:00:00], until: ~T[17:00:00], left: :closed, right: :open}
      ...> )
      true
  """
  # [claude-code] Changed: endpoint equality via same_instant?/2.
  @spec completely_before?(interval(), interval()) :: boolean()
  def completely_before?(lhs, rhs) do
    lhs.until != nil && rhs.from != nil &&
      (Timex.before?(lhs.until, rhs.from) ||
         (same_instant?(lhs.until, rhs.from) && (lhs.right == :open || rhs.left == :open)))
  end

  @doc """
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
  """
  # [claude-code] Changed (2026-08-05, decision D2): one clause, all
  # shapes through the funnel. The piece-level core moved to the
  # private overlapping_pieces?/2.
  @spec overlaps?(at_least_one_valid(), at_least_one_valid()) :: boolean()
  def overlaps?(lhs, rhs) do
    lhs = check_and_extract_as_list!(lhs)
    rhs = check_and_extract_as_list!(rhs)

    Enum.any?(lhs, fn l -> Enum.any?(rhs, &overlapping_pieces?(l, &1)) end)
  end

  # [claude-code] The piece-level core of overlaps?/2: two pieces
  # share an instant unless one is completely before the other.
  @spec overlapping_pieces?(interval(), interval()) :: boolean()
  defp overlapping_pieces?(lhs, rhs) do
    not completely_before?(lhs, rhs) and not completely_before?(rhs, lhs)
  end

  # [claude-code] True when lhs ends exactly where rhs starts and at
  # least one of the two sides includes that shared instant: their
  # union has no hole, so one spanning interval can replace them
  # ([a, b) plus [b, c) covers [a, c)). When both sides are open, the
  # shared instant is in neither interval - they must stay separate.
  @spec touching?(interval(), interval()) :: boolean()
  defp touching?(lhs, rhs) do
    lhs.until != nil && rhs.from != nil && same_instant?(lhs.until, rhs.from) &&
      (lhs.right == :closed || rhs.left == :closed)
  end

  # [claude-code] True when the union step can replace the two
  # intervals with one spanning interval: they overlap, or they touch
  # with the shared endpoint covered.
  @spec coalesces?(interval(), interval()) :: boolean()
  defp coalesces?(a, b) do
    overlapping_pieces?(a, b) || touching?(a, b) || touching?(b, a)
  end

  # [claude-code] Changed the four comparison helpers: a nil endpoint
  # (nil from = no lower bound, nil until = no upper bound) is now
  # handled on both sides before anything reaches Timex. Before, a nil
  # in the uncovered position raised Protocol.UndefinedError as soon
  # as a bounded and an unbounded interval met in a set operation.
  @spec le_from?(interval(), interval()) :: boolean()
  defp le_from?(a, b) do
    cond do
      a.from == nil ->
        true

      b.from == nil ->
        false

      true ->
        Timex.before?(a.from, b.from) || (same_instant?(a.from, b.from) && a.left == :closed)
    end
  end

  @spec ge_from?(interval(), interval()) :: boolean()
  defp ge_from?(a, b) do
    cond do
      b.from == nil -> true
      a.from == nil -> false
      true -> Timex.after?(a.from, b.from) || (same_instant?(a.from, b.from) && a.left == :open)
    end
  end

  @spec le_until?(interval(), interval()) :: boolean()
  defp le_until?(a, b) do
    cond do
      b.until == nil ->
        true

      a.until == nil ->
        false

      true ->
        Timex.before?(a.until, b.until) || (same_instant?(a.until, b.until) && a.right == :open)
    end
  end

  @spec ge_until?(interval(), interval()) :: boolean()
  defp ge_until?(a, b) do
    cond do
      a.until == nil ->
        true

      b.until == nil ->
        false

      true ->
        Timex.before?(b.until, a.until) ||
          (same_instant?(a.until, b.until) && a.right == :closed)
    end
  end

  @doc """
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
  """
  # [claude-code] Changed (2026-08-05, decision D2): union/2 takes
  # any two funnel shapes and answers with the struct. The old
  # union/1 (union of one list) fell: it had become the same
  # operation as compress/1, and one meaning gets one name. The old
  # fold step lives on as the private union_step/2.
  @spec union(at_least_one_valid(), at_least_one_valid()) :: t()
  def union(this, other) do
    (check_and_extract_as_list!(this) ++ check_and_extract_as_list!(other))
    |> normalize()
    |> wrap()
  end

  # [claude-code] The fold step of the normal-form pass: add one
  # interval to a minimal list and keep it minimal. Every member
  # that overlaps or touches `new_ival` fuses with it into one
  # spanning interval. (This is the owner's union/2 body.)
  @spec union_step([interval()], interval()) :: [interval()]
  defp union_step(ivals, new_ival) do
    case Enum.split_with(ivals, &coalesces?(&1, new_ival)) do
      {[], rest} ->
        [new_ival | rest]

      {overlaps, rest} ->
        overlaps_with_new = [new_ival | overlaps]

        {min, max} = {
          Enum.min(overlaps_with_new, &le_from?/2),
          Enum.max(overlaps_with_new, &ge_until?/2)
        }

        new = %{from: min.from, until: max.until, left: min.left, right: max.right}

        [new | rest]
    end
  end

  # [claude-code] Added (2026-08-05): the one normal-form pass every
  # set operation ends in - drop what covers no instant, fuse
  # everything that overlaps or touches, then sort by the left
  # endpoint (nil first: an unbounded left side starts before
  # everything).
  @spec normalize([interval()]) :: [interval()]
  defp normalize(pieces) do
    pieces
    |> Enum.reject(&no_instant?/1)
    |> Enum.reduce([], &union_step(&2, &1))
    |> Enum.sort(fn a, b ->
      a.from == nil || (b.from !== nil && Timex.before?(a.from, b.from))
    end)
  end

  # [claude-code] Added (2026-08-05, Linear YUR-85): does the
  # interval cover no instant at all? from == until covers the
  # single instant [t, t] only when BOTH sides are closed; with any
  # open side the boundary instant is cut away and nothing remains.
  # Such zero-width pieces used to survive compress/1.
  @spec no_instant?(interval()) :: boolean()
  defp no_instant?(%{from: from, until: until} = piece) do
    from != nil and until != nil and same_instant?(from, until) and
      not (piece.left == :closed and piece.right == :closed)
  end

  @spec wrap([interval()]) :: t()
  defp wrap(pieces), do: %__MODULE__{intervals: pieces}

  @doc """
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
  """
  # [claude-code] Changed (2026-08-05, decision D2): any funnel shape
  # in, the struct out.
  @spec compress(at_least_one_valid()) :: t()
  def compress(operand) do
    operand
    |> check_and_extract_as_list!()
    |> normalize()
    |> wrap()
  end

  @doc """
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
  """
  # [claude-code] Changed (2026-08-05, decision D2): one clause, all
  # shapes through the funnel, the struct out. The piece-level body
  # moved to the private intersect_pieces/2.
  @spec intersect(at_least_one_valid(), at_least_one_valid()) :: t()
  def intersect(this, other) do
    intersect_lists(check_and_extract_as_list!(this), check_and_extract_as_list!(other))
    |> normalize()
    |> wrap()
  end

  # [claude-code] All pairwise piece intersections of two lists.
  # complement/1 folds with this, so the fold stays list-based.
  @spec intersect_lists([interval()], [interval()]) :: [interval()]
  defp intersect_lists(these, others) do
    for l <- these, r <- others, (its = intersect_pieces(l, r)) != nil, do: its
  end

  # [claude-code] The piece-level core: one interval or nil. (This is
  # the owner's intersect/2 body.)
  @spec intersect_pieces(interval(), interval()) :: interval() | nil
  defp intersect_pieces(this, other) do
    if overlapping_pieces?(this, other) do
      {from, left} =
        (ge_from?(this, other) && {this.from, this.left}) || {other.from, other.left}

      {until, right} =
        (le_until?(this, other) && {this.until, this.right}) || {other.until, other.right}

      %{from: from, until: until, left: left, right: right}
    else
      nil
    end
  end

  @doc """
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
  """
  # [claude-code] Changed (2026-08-05, decision D2): one clause, all
  # shapes through the funnel, the struct out. The complement of the
  # set is the intersection of the per-piece complements; a
  # whole-timeline member complements to nil (the empty set), and an
  # intersection that became empty stays empty. The piece-level body
  # moved to the private complement_piece/1.
  @spec complement(at_least_one_valid()) :: t()
  def complement(operand) do
    per_interval =
      check_and_extract_as_list!(operand)
      |> Enum.map(&complement_piece/1)
      |> Enum.map(fn
        nil -> []
        {l, r} -> [l, r]
        comp -> [comp]
      end)

    case per_interval do
      [] ->
        wrap([%{from: nil, until: nil, left: nil, right: nil}])

      [first | rest] ->
        rest
        |> Enum.reduce(first, fn pieces, acc ->
          if acc == [] or pieces == [], do: [], else: intersect_lists(acc, pieces)
        end)
        |> normalize()
        |> wrap()
    end
  end

  # [claude-code] The piece-level core: one bounded interval
  # complements to two rays (a {left_ray, right_ray} pair), a
  # half-unbounded one to a single ray, the whole timeline to nil.
  # (This is the owner's complement/1 body; the two half-unbounded
  # branches carry an earlier reviewed fix - they used to read the
  # endpoint from the side that is nil.)
  @spec complement_piece(interval()) :: interval() | {interval(), interval()} | nil
  defp complement_piece(interval) do
    case interval do
      %{from: nil, until: nil} ->
        nil

      %{from: nil, until: _} ->
        %{from: interval.until, until: nil, left: opposite_closing(interval.right), right: nil}

      %{from: _, until: nil} ->
        %{from: nil, until: interval.from, left: nil, right: opposite_closing(interval.left)}

      %{from: _, until: _} ->
        {
          %{from: nil, until: interval.from, left: nil, right: opposite_closing(interval.left)},
          %{from: interval.until, until: nil, left: opposite_closing(interval.right), right: nil}
        }
    end
  end

  @doc """
  Set difference: the instants of `this` that are not in `other`,
  as a set. Computed piece by piece as `this` intersected with the
  complement of `other`, so the three operations stay consistent by
  construction.

  ## Examples

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
  """
  # [claude-code] Changed (2026-08-05, decision D2): one clause, all
  # shapes through the funnel, the struct out. The subtraction
  # subtracts the subtrahends one after the other from the remaining
  # pieces (successive subtraction); the piece-level step moved to
  # the private diff_pieces/2.
  @spec diff(at_least_one_valid(), at_least_one_valid()) :: t()
  def diff(this, other) do
    these = check_and_extract_as_list!(this)
    others = check_and_extract_as_list!(other)

    others
    |> Enum.reduce(these, fn rhs, pieces ->
      Enum.flat_map(pieces, &diff_pieces(&1, rhs))
    end)
    |> normalize()
    |> wrap()
  end

  # [claude-code] The piece-level step: what remains of `this` after
  # `other` is cut out - zero, one, or two pieces, always as a list
  # so the set fold can flat_map it. (This is the owner's diff/2
  # body, reshaped from interval-or-tuple-or-nil to a list.)
  @spec diff_pieces(interval(), interval()) :: [interval()]
  defp diff_pieces(this, other) do
    if overlapping_pieces?(this, other) do
      case intersect_pieces(this, other) |> complement_piece() do
        {l, r} ->
          [intersect_pieces(this, l), intersect_pieces(this, r)]
          |> Enum.reject(&is_nil/1)

        # The intersection can be the whole timeline (both operands
        # unbounded on both sides); its complement is nil and nothing
        # remains of `this`.
        nil ->
          []

        c ->
          case intersect_pieces(this, c) do
            nil -> []
            d -> [d]
          end
      end
    else
      [this]
    end
  end
end

# [claude-code] Added (2026-08-05, decision D1, kernel half): a set
# is one value, and a value that holds pieces hands them out.
# Enumerating a %Zocam.Intervals{} yields its concrete interval()
# pieces, in normal-form order. The three optional callbacks are
# honest about the piece list: count is its length, member? is
# structural piece membership (NOT instant coverage - see "Enumerate
# a set" in the moduledoc), and slice indexes into it.
defimpl Enumerable, for: Zocam.Intervals do
  @impl true
  def count(%Zocam.Intervals{intervals: pieces}), do: {:ok, length(pieces)}

  @impl true
  def member?(%Zocam.Intervals{intervals: pieces}, value) do
    {:ok, Enum.member?(pieces, value)}
  end

  @impl true
  def slice(%Zocam.Intervals{intervals: pieces}) do
    # The slicing contract: from `start`, take every `step`-th
    # piece, `amount` of them.
    {:ok, length(pieces),
     fn start, amount, step ->
       pieces |> Enum.drop(start) |> Enum.take_every(step) |> Enum.take(amount)
     end}
  end

  @impl true
  def reduce(%Zocam.Intervals{intervals: pieces}, acc, fun) do
    Enumerable.List.reduce(pieces, acc, fun)
  end
end
