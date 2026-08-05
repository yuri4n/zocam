# [claude-code] The code in this module is the project owner's linear
# interval kernel. Claude Code added the comments and docstrings on
# 2026-08-04 with a one-time permission, moved the module from the
# s7r app into the zocam library, and narrowed timables/0 (see
# below). Lines marked "Changed" are earlier reviewed fixes; the
# bodies are otherwise the owner's.
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
  """

  # The struct is a bare defstruct by the owner's design: it holds one
  # list and nothing else, and the list type is documented on t/0.
  defstruct [:intervals]

  use Timex

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

  @type t :: %__MODULE__{
          intervals: [interval(), ...]
          # step: Timex.shift_options()
        }

  @type interval_opt :: {:interval, interval_opts()}

  @type valid_intervals :: [interval_opt() | interval(), ...] | t()

  @type at_least_one_valid :: valid_interval() | valid_intervals()

  # [claude-code] Comment only: complementing an interval flips each
  # closing - the boundary instant moves to the other side. nil stays
  # nil because an unbounded side has no boundary to flip.
  defp opposite_closing(:open), do: :closed
  defp opposite_closing(:closed), do: :open
  defp opposite_closing(nil), do: nil

  @doc """
  Check one interval option list: `from`/`until`/`left`/`right` at
  most once each, and at least one of `from`/`until` present. Returns
  the options unchanged; raises `ArgumentError` otherwise.
  """
  @spec check_interval_opts!(interval_opts()) :: interval_opts()
  def check_interval_opts!(opts) do
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
  Check the options for `new!/1`. Two forms are legal: a root-level
  interval (`from:`/`until:` directly in the list) or one or more
  `interval:` entries. Mixing the two forms raises, and every
  `interval:` entry is checked with `check_interval_opts!/1`.
  """
  # [claude-code] Changed spec only: the function also accepts the
  # root-level from/until keyword form, not just [interval: ...].
  @spec check_new_opts!([new_opts()] | interval_opts()) :: [new_opts()] | interval_opts()
  def check_new_opts!(opts) do
    case {Keyword.get_values(opts, :interval), Keyword.get_values(opts, :from),
          Keyword.get_values(opts, :until)} do
      {[], [], []} ->
        raise ArgumentError,
              "Invalid options: at least one of interval, from or until must be specified"

      {[_ | _], froms, untils} when length(froms) > 0 or length(untils) > 0 ->
        raise ArgumentError,
              "Invalid options: intervals cannot be specified in the presence of from or until"

      {[], _froms, _untils} ->
        opts |> check_interval_opts!()

      {intervals, _, _} ->
        {_intervals, errors} =
          Enum.map_reduce(intervals, [], fn interval_opts, errors ->
            try do
              {check_interval_opts!(interval_opts), errors}
            rescue
              e ->
                {interval_opts, Enum.reverse([e | errors])}
            end
          end)

        cond do
          Enum.count(errors) > 0 ->
            raise(ArgumentError, "Invalid options: \n#{Enum.join(errors, "\n")}")

          true ->
            opts
        end
    end
  end

  @doc """
  Build the interval map from an option list. A missing side stays
  `nil` (unbounded). The default closings are `:closed` on the left
  and `:open` on the right, the half-open convention that lets
  adjacent intervals tile without overlap; an absent side gets `nil`.
  """
  @spec interval_from_opts(interval_opts()) :: interval()
  def interval_from_opts(opts) do
    from = Keyword.get(opts, :from, nil)
    until = Keyword.get(opts, :until, nil)
    left = Keyword.get(opts, :left, (from && :closed) || nil)
    right = Keyword.get(opts, :right, (until && :open) || nil)

    %{from: from, until: until, left: left, right: right}
  end

  @spec extract_from_new_opts([new_opts()]) :: [interval()]
  defp extract_from_new_opts(opts) do
    if Keyword.has_key?(opts, :interval) do
      # intervals are defined separately.
      Keyword.get_values(opts, :interval) |> Enum.map(&interval_from_opts/1)
    else
      # interval is in the root opts.
      [interval_from_opts(opts)]
    end
  end

  @spec check_and_extract!(t()) :: [interval()]
  defp check_and_extract!(%__MODULE__{} = intervals), do: intervals.intervals

  @spec check_and_extract!(interval()) :: interval()
  defp check_and_extract!(%{from: _, until: _} = interval), do: interval

  # [claude-code] Changed: the empty list is the empty set. The set
  # operations both produce it (complement of a covering set, x minus
  # x) and accept it back; new!/1 still rejects an empty specification
  # in check_new_opts!/1.
  @spec check_and_extract!([]) :: []
  defp check_and_extract!([]), do: []

  # [claude-code] Added: accept the shapes the interval-level clauses
  # of complement/1 and diff/2 return - a {left, right} tuple or nil -
  # so compositions like diff(a, complement(b)) work without wrapping.
  @spec check_and_extract!({interval(), interval()}) :: [interval()]
  defp check_and_extract!({l, r}) when is_interval(l) and is_interval(r), do: [l, r]

  @spec check_and_extract!(nil) :: []
  defp check_and_extract!(nil), do: []

  @spec check_and_extract!(interval_opts() | [interval_opt() | interval() | interval_opts()]) ::
          [interval()] | interval()
  defp check_and_extract!(opts) when is_list(opts) do
    check_and_extract_opts! = fn opts_ ->
      opts_ |> check_interval_opts!() |> interval_from_opts()
    end

    if Keyword.has_key?(opts, :from) || Keyword.has_key?(opts, :until) do
      # We got a keyword list of interval options, instead of multiple intervals.
      check_and_extract_opts!.(opts)
    else
      # We got a list of intervals, specified in multiple ways.

      Enum.map(opts, fn
        # It could be already an interval.
        %{from: _, until: _} = interval ->
          interval

        # Or an interval option.
        {:interval, interval_opts} ->
          check_and_extract_opts!.(interval_opts)

        # Or the interval options themselves.
        o ->
          check_and_extract_opts!.(o)
      end)
    end
  end

  @doc """
  Normalize any accepted shape (a struct, an interval map, option
  lists, a mixed list, `{left, right}` pairs, `nil`, `[]`) into a
  plain list of interval maps. This is the funnel every set operation
  pours its input through, so each operation handles ONE shape.
  """
  @spec check_and_extract_as_list!(valid_interval() | valid_intervals()) :: [interval()]
  def check_and_extract_as_list!(unknown) do
    case check_and_extract!(unknown) do
      l when is_list(l) -> l
      i -> [i]
    end
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
  be single intervals or whole sets; two sets overlap when any pair
  of their members does.
  """
  @spec overlaps?(interval(), interval()) :: boolean()
  def overlaps?(%{from: _, until: _} = lhs, %{from: _, until: _} = rhs) do
    cond do
      completely_before?(lhs, rhs) ->
        false

      completely_before?(rhs, lhs) ->
        false

      :otherwise ->
        true
    end
  end

  @spec overlaps?(valid_interval(), valid_interval() | valid_intervals()) :: boolean()
  def overlaps?(lhs, rhs) do
    lhs = check_and_extract_as_list!(lhs)
    rhs = check_and_extract_as_list!(rhs)

    Enum.any?(lhs, fn l -> Enum.any?(rhs, &overlaps?(l, &1)) end)
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

  # [claude-code] True when union/2 can replace the two intervals with
  # one spanning interval: they overlap, or they touch with the shared
  # endpoint covered.
  @spec coalesces?(interval(), interval()) :: boolean()
  defp coalesces?(a, b) do
    overlaps?(a, b) || touching?(a, b) || touching?(b, a)
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
  Union a list of intervals into a minimal list: overlapping and
  touching members fuse into one spanning interval (`union/1`), or
  add one interval into an existing list (`union/2`). The result is
  not sorted; `compress/1` also sorts.
  """
  @spec union([interval()]) :: [interval()]
  def union(ivals) do
    Enum.reduce(ivals, [], &union(&2, &1))
  end

  # [claude-code] Changed: merges touching intervals too (coalesces?/2),
  # not only overlapping ones.
  @spec union([interval()], interval()) :: [interval()]
  def union(ivals, new_ival) do
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

  @doc """
  Bring a set into its normal form: fuse everything that overlaps or
  touches, then sort by the left endpoint (`nil` first: an unbounded
  left side starts before everything). Two sets with the same
  content compress to the same list, which makes normal forms
  comparable with `==`.
  """
  @spec compress(t()) :: t()
  def compress(%__MODULE__{} = intervals) do
    %__MODULE__{intervals | intervals: compress(intervals.intervals)}
  end

  @spec compress([interval()]) :: [interval()]
  def compress(intervals) do
    Enum.reduce(intervals, [], &union(&2, &1))
    |> Enum.sort(fn a, b ->
      a.from == nil || (b.from !== nil && Timex.before?(a.from, b.from))
    end)
  end

  @type new_opts :: interval_opt()

  @doc """
  Build a compressed interval set from options:

      new!(from: ~T[09:00:00], until: ~T[17:00:00])
      new!(interval: [from: a, until: b], interval: [from: c, until: d])

  Raises `ArgumentError` on an empty or mixed specification. The
  result is already in normal form (see `compress/1`).
  """
  # [claude-code] Changed spec only: also admits the root-level
  # from/until form (new!(from: ..., until: ...)).
  @spec new!([new_opts()] | interval_opts()) :: t()
  def new!(opts) do
    intervals =
      opts
      |> check_new_opts!()
      |> extract_from_new_opts()
      |> compress()

    %__MODULE__{intervals: intervals}
  end

  @doc """
  The instants shared by both operands. On two single intervals the
  result is one interval or `nil`; on sets it is the compressed set
  of all pairwise intersections. The tighter bound wins on each
  side, closing included: `[a, b]` meets `(a, c)` in `(a, b]`.
  """
  @spec intersect(interval(), interval()) :: interval() | nil
  def intersect(this, other) when is_interval(this) and is_interval(other) do
    if overlaps?(this, other) do
      {from, left} =
        (ge_from?(this, other) && {this.from, this.left}) || {other.from, other.left}

      {until, right} =
        (le_until?(this, other) && {this.until, this.right}) || {other.until, other.right}

      %{from: from, until: until, left: left, right: right}
    else
      nil
    end
  end

  @spec intersect(t(), at_least_one_valid()) :: t()
  def intersect(%__MODULE__{} = this, others) do
    %__MODULE__{intervals: intersect(this.intervals, others)}
  end

  @spec intersect(at_least_one_valid(), at_least_one_valid()) :: [interval()]
  def intersect(this, other) do
    this = check_and_extract_as_list!(this)
    other = check_and_extract_as_list!(other)

    new_intervals =
      for l <- this, r <- other, (its = intersect(l, r)) != nil, do: its

    new_intervals |> compress()
  end

  @doc """
  Everything outside the operand. One bounded interval complements
  to two rays (a `{left_ray, right_ray}` pair); a half-unbounded one
  to a single ray; the whole timeline to `nil`; the empty set to the
  whole timeline. Each boundary closing flips (see
  `opposite_closing/1`): the instants `[a, b]` covers are exactly
  the instants `(-inf, a)` and `(b, +inf)` miss.
  """
  @spec complement(interval()) :: interval() | {interval(), interval()} | nil
  def complement(interval) when is_interval(interval) do
    case interval do
      %{from: nil, until: nil} ->
        nil

      # [claude-code] Changed both half-unbounded branches: they read
      # the endpoint from the side that is nil, so each returned the
      # whole timeline instead of the piece outside the interval.
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

  @spec complement(t()) :: t()
  def complement(%__MODULE__{} = intervals) do
    %__MODULE__{intervals: complement(intervals.intervals)}
  end

  # [claude-code] Changed the fold: the complement of the set is the
  # intersection of the per-interval complements. A whole-timeline
  # member complements to nil (the empty set), and an intersection
  # that became empty stays empty - both used to crash the old fold.
  # The complement of the empty set is the whole timeline.
  @spec complement(at_least_one_valid()) :: [interval()]
  def complement(intervals) do
    per_interval =
      check_and_extract_as_list!(intervals)
      |> Enum.map(&complement/1)
      |> Enum.map(fn
        nil -> []
        {l, r} -> [l, r]
        comp -> [comp]
      end)

    case per_interval do
      [] ->
        [%{from: nil, until: nil, left: nil, right: nil}]

      [first | rest] ->
        rest
        |> Enum.reduce(first, fn pieces, acc ->
          if acc == [] or pieces == [], do: [], else: intersect(acc, pieces)
        end)
        |> compress()
    end
  end

  @doc """
  Set difference: the instants of `this` that are not in `other`.
  Computed as `this` intersected with the complement of `other`, so
  the three operations stay consistent by construction. Subtracting
  a middle slice cuts one interval into two; on sets the subtrahends
  subtract one after the other from what remains.
  """
  @spec diff(interval(), interval()) :: interval() | {interval(), interval()} | nil
  def diff(this, other) when is_interval(this) and is_interval(other) do
    if overlaps?(this, other) do
      case intersect(this, other) |> complement() do
        {l, r} ->
          case {intersect(this, l), intersect(this, r)} do
            {nil, nil} -> nil
            {nil, r} -> r
            {l, nil} -> l
            {l, r} -> {l, r}
          end

        # [claude-code] Changed: the intersection can be the whole
        # timeline (both operands unbounded on both sides); its
        # complement is nil and nothing remains of `this`.
        nil ->
          nil

        c ->
          intersect(this, c)
      end
    else
      this
    end
  end

  @spec diff(t(), at_least_one_valid()) :: t()
  def diff(%__MODULE__{} = this, others) do
    %__MODULE__{intervals: diff(this.intervals, others)}
  end

  # [claude-code] Changed: subtracts the subtrahends one after the
  # other from the remaining pieces (successive subtraction). The old
  # pairwise form unioned the per-subtrahend diffs, which put each
  # subtracted slot back, and it dropped a minuend that overlapped no
  # subtrahend.
  @spec diff(at_least_one_valid(), at_least_one_valid()) :: [interval()]
  def diff(these, others) do
    these = check_and_extract_as_list!(these)
    others = check_and_extract_as_list!(others)

    others
    |> Enum.reduce(these, fn rhs, pieces ->
      Enum.flat_map(pieces, fn lhs ->
        case diff(lhs, rhs) do
          {l, r} -> [l, r]
          nil -> []
          d -> [d]
        end
      end)
    end)
    |> compress()
  end
end
