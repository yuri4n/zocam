# [claude-code] The set layer over Zocam.Point. Generated from the
# temporal-things design (2026-08-04) and implemented in step 3 (arcs and
# smart set constructors), step 4 (member?/2), and step 5 (ground/3 with
# timezone resolution). No stubs remain in this module.
# Changed (2026-08-05): moduledoc recipes and doctests across the public
# API for the "Examples and recipes" rule (wired in
# test/zocam/span_test.exs). All calendar facts in the examples are
# machine-verified for 2026; see the fixture note in span_test.exs.
defmodule Zocam.Span do
  @moduledoc """
  Sets of instants built from calendar points: arcs, unions,
  intersections, complements, and ordinal selection.

  This module is the set layer over `Zocam.Point`. The layers:

      Point ──▶ Arc ──▶ Span ──▶ ground/3 ──▶ Zocam.Intervals
      (thing)   (from..until    (recursive     (linear kernel,
                 + closings      set: the       already tested)
                 + step)         algebra)

  A span is one recursive type. The *set* is primary and a single
  interval is only a one-arc set. The reason is closure: the
  complement of one arc is already two pieces, and a diff can cut one
  interval into two. A standalone interval type cannot be closed
  under its own operators.

  Keep the names apart: `Zocam.Span.Arc` is *one symbolic piece*
  and `t:t/0` is the *symbolic set* built over such pieces, while
  `t:Zocam.Intervals.interval/0` is *one concrete piece* and
  `t:Zocam.Intervals.t/0` is the *concrete set*. "The four names" in
  the `Zocam` moduledoc shows the full two-by-two map.

  ## Recipes

  You want every second Friday, 09:00–12:00, as concrete UTC
  intervals. Do these steps: name the day, set the rhythm, cut the
  hours, intersect, and ground. (January 2026 has Fridays on the
  2nd, 9th, 16th, 23rd, and 30th; the anchor Jan 2 keeps the 2nd,
  the 16th, and the 30th.)

      iex> fridays =
      ...>   Zocam.Point.weekday(:friday)
      ...>   |> Zocam.Point.every(2, ~D[2026-01-02])
      ...>   |> Zocam.Span.of()
      iex> morning =
      ...>   Zocam.Span.arc!(
      ...>     from: Zocam.Point.time(~T[09:00:00]),
      ...>     until: Zocam.Point.time(~T[12:00:00])
      ...>   )
      iex> span = Zocam.Span.intersection([fridays, morning])
      iex> horizon = %{
      ...>   from: ~U[2026-01-01 00:00:00Z],
      ...>   until: ~U[2026-02-01 00:00:00Z],
      ...>   left: :closed,
      ...>   right: :open
      ...> }
      iex> Zocam.Span.ground(span, horizon, "Etc/UTC").intervals
      [
        %{from: ~U[2026-01-02 09:00:00Z], until: ~U[2026-01-02 12:00:00Z], left: :closed, right: :open},
        %{from: ~U[2026-01-16 09:00:00Z], until: ~U[2026-01-16 12:00:00Z], left: :closed, right: :open},
        %{from: ~U[2026-01-30 09:00:00Z], until: ~U[2026-01-30 12:00:00Z], left: :closed, right: :open}
      ]

  You want the last working day of each month. Select it with
  `nth/3`, then ask with `member?/2` — no horizon needed. April 2026
  ends on Thursday the 30th; May 2026 ends on Sunday the 31st, so
  its last working day is Friday the 29th:

      iex> weekdays =
      ...>   Zocam.Span.arc!(
      ...>     from: Zocam.Point.weekday(:monday),
      ...>     until: Zocam.Point.weekday(:friday)
      ...>   )
      iex> last_working_day = Zocam.Span.nth(-1, weekdays, per: :month)
      iex> Zocam.Span.member?(last_working_day, ~U[2026-04-30 12:00:00Z])
      true
      iex> Zocam.Span.member?(last_working_day, ~U[2026-05-29 12:00:00Z])
      true
      iex> Zocam.Span.member?(last_working_day, ~U[2026-05-31 12:00:00Z])
      false

  ## Two evaluation regimes

  - **Within one cycle** the algebra is eager where it can be: when
    same-scope arc nodes merge in a union, the plain arcs (one
    segment, both sides closed, no step, no wrap) compact to sorted,
    disjoint integer cell ranges (january=1..december=12,
    monday=1..sunday=7), so `Jan..Jan` plus `Feb..Feb` IS `Jan..Feb`.
    All other arcs (wraps, steps, ordinals, open sides) ride along
    unchanged: the form is quasi-canonical, not minimal. A step
    samples cells forward from the `from` bound after the `until`
    bound has been resolved across the wrap seam, so the sampling
    phase runs through the seam.
  - **Across cycles** the tree stays symbolic and lazy: "Wednesdays
    in May" has no finite normal form before grounding, so the
    intersection node holds it as data. This is the interpreter
    pattern: constructors build a free algebra, and `member?/2` and
    `ground/3` are its two interpreters.

  Both interpreters share ONE denotation function: clamping, ordinal
  skipping, and closings behave identically in `member?/2` and
  `ground/3`. Keeping them equal is the keystone property test:
  `member?(span, t) == member of t in ground(span, horizon, tz)`.

  ## How an arc becomes kernel intervals

  The shared denotation core works in *wall time* and meets the real
  timeline only at the very end:

      arc                     one per scope instance
       │ chain_window/3        (year 2026, week of Jan 5, ...)
       ▼
      wall windows            [~N[2026-11-01 00:00:00],
       │ preimage/3            ~N[2027-02-01 00:00:00])
       ▼
      UTC intervals           the tzdata period table maps each wall
       │ clip + compress       window to 0, 1, or 2 UTC pieces
       ▼
      Zocam.Intervals

  `member?/2` stops at the second stage: it reads the wall clock of
  the given `DateTime` and checks the wall windows directly. That is
  why the two interpreters cannot disagree: they run the same code up
  to the point where a timezone exists.

  ## Wrap-around

  `Fri..Mon`, `Nov..Feb`, and `22:00..06:00` are legal arcs. A wrap
  is decided at the chain level, before closings expand: `May..May`
  is the single-unit case, never a wrap. A wrapping arc materializes
  *forward*: the until bound resolves in the next cycle instance, so
  `Nov..Feb` becomes one continuous block `[Nov 1, Feb 1)` of the
  following year and nothing needs to re-fuse at the seam.
  `member?/2` therefore checks the instance of the probed instant
  *and its predecessor*: a block that started last instance can
  still cover the probe.

  ## Timezone

  Only `ground/3` and `member?/2` on real `DateTime`s meet the
  timeline. `member?/2` reads the wall clock of the given DateTime.
  `ground/3` resolves wall times in the given timezone: an instance
  can ground to *two* kernel intervals on a fall-back day (the wall
  window exists twice), and a wall time inside a spring-forward gap
  grounds to nothing.

  ## One calendar

  Every `DateTime` this module takes must be on `Calendar.ISO`:
  `absolute!/1`, the `ground/3` horizon, `member?/2`, and `stream/3`
  all check it and refuse anything else. The wall dates that come out
  of those instants are read as ISO dates — `instance_index/2` reads
  `date.year` and `date.month` as Gregorian numbers — so the check is
  what makes the reading true. See `Zocam.ISO`.
  """

  use TypedStruct

  alias Zocam.{Intervals, ISO, Point}

  # [claude-code] A step samples an arc every n units. The unit must
  # be the arc's grain, a coarser unit on its chain (day-grain bounds
  # may step {1, :month}: "the 31st, monthly", clamped per landing),
  # or a sub-day time unit when the grain is :time ({15, :minute}:
  # "every 15 minutes"). Time.t has no natural unit cell, so a bare
  # integer step means nothing at :time grain and is rejected there.
  @type time_unit :: :hour | :minute | :second
  @type step :: {pos_integer(), Point.unit() | time_unit()}

  # [claude-code]
  defmodule Arc do
    @moduledoc """
    A directed span between two bounds of the same form, with
    per-side closings, a step, and an overflow policy.

    An arc always lives inside an `{:arcs, scope, grain, arcs}` node.
    The node owns the scope and the grain — the arc holds only the
    bounds, so the two can never disagree. The smart constructors
    guarantee that every arc's chains match its node.

    On a bare coarse unit the closing covers the whole unit:
    `until: february, right: :open` excludes all of February;
    `right: :closed` includes all of it.

    `step: nil` means "no sampling": the arc covers the whole block
    between its bounds. A `{1, grain}` step is the same set, so the
    constructors normalize it to `nil` — one canonical spelling for
    one meaning. The overflow policy comes from the bound points and
    acts where a day number lands in a short month.

    An arc is not a `t:Zocam.Intervals.interval/0`. The arc is
    symbolic and *repeats* — "Fri..Mon" happens once in every week.
    The interval is concrete and happens *once*. `Zocam.Span.ground/3`
    turns each instance of an arc into 0, 1, or 2 concrete intervals
    (a DST gap, a normal day, a DST fold). See "The four names" in
    the `Zocam` moduledoc for the full map.

    ## Enumerate an arc

    One instance of an arc is a row of grain cells, and `Enum` walks
    that row: the struct implements `Enumerable` and yields the
    symbolic cells of ONE instance, in walking order. Each cell comes
    out as the simplest honest value — the bare cell value when the
    bounds are single-segment chains (`:friday`, `:november`, `15`,
    `~T[09:15:00]`), and a chain in which only the grain cell varies
    when the bounds carry a prefix (`[month: :may, day: 11]`). The
    walk reuses `Zocam.Span.ground/3`'s reading of "cell": the same
    wrap rule, the same whole-unit closings, the same step sampling.

    The common call — the four weekday cells of "Friday through
    Monday" (the smart constructors hand the arc back inside an
    `{:arcs, ...}` node, so match it out first):

        iex> {:arcs, _, _, [weekend]} =
        ...>   Zocam.Span.arc!(
        ...>     from: Zocam.Point.weekday(:friday),
        ...>     until: Zocam.Point.weekday(:monday)
        ...>   )
        iex> Enum.to_list(weekend)
        [:friday, :saturday, :sunday, :monday]

    Closings are honored: an `:open` side drops that bound's whole
    cell, exactly as it does under grounding:

        iex> {:arcs, _, _, [stay]} =
        ...>   Zocam.Span.arc!(
        ...>     from: Zocam.Point.weekday(:friday),
        ...>     until: Zocam.Point.weekday(:monday),
        ...>     right: :open
        ...>   )
        iex> Enum.to_list(stay)
        [:friday, :saturday, :sunday]

    The edge: a wrapping arc walks through the cycle seam, inside
    one instance — November through February is four month cells:

        iex> {:arcs, _, _, [winter]} =
        ...>   Zocam.Span.arc!(
        ...>     from: Zocam.Point.month(:november),
        ...>     until: Zocam.Point.month(:february)
        ...>   )
        iex> Enum.to_list(winter)
        [:november, :december, :january, :february]

    The integrated use: a step whose unit is the grain samples every
    n-th cell, so a stepped `:time` arc yields its sampled `Time`
    values:

        iex> {:arcs, _, _, [morning]} =
        ...>   Zocam.Span.arc!(
        ...>     from: Zocam.Point.time(~T[09:00:00]),
        ...>     until: Zocam.Point.time(~T[12:00:00]),
        ...>     step: {15, :minute}
        ...>   )
        iex> Enum.count(morning)
        12
        iex> Enum.take(morning, 3)
        [~T[09:00:00], ~T[09:15:00], ~T[09:30:00]]

    The pitfall: an UNstepped `:time` arc is continuous — between
    any two instants sit infinitely many more — so it has no cells
    to walk, and `Enum` on it raises with the two ways out:

        iex> {:arcs, _, _, [window]} =
        ...>   Zocam.Span.arc!(
        ...>     from: Zocam.Point.time(~T[09:00:00]),
        ...>     until: Zocam.Point.time(~T[12:00:00])
        ...>   )
        iex> Enum.to_list(window)
        ** (ArgumentError) a :time-grain arc without a step is continuous, so it has no cells to enumerate. Two ways out: give the arc a step (for example step: {15, :minute}), or ground the span with Zocam.Span.ground/3 and walk the concrete intervals.

    The same honesty applies to every arc whose one-instance cell
    row is not fixed: a step whose unit is not the grain ("the 31st,
    monthly" samples across real months), an ordinal or negative
    bound (each month elects its own "last Saturday"), bounds that
    differ above the grain cell, and a wrap in a cycle without a
    fixed length (a month has 28 to 31 days). Each raises an
    `ArgumentError` that points to `Zocam.Span.ground/3` — the
    interpreter that walks the real calendar.
    """
    use TypedStruct

    typedstruct enforce: true do
      field :from, Point.chain()
      field :until, Point.chain()
      field :left, Intervals.closing()
      field :right, Intervals.closing()
      field :step, Zocam.Span.step() | nil, default: nil
      field :overflow, Point.overflow(), default: :clamp
    end
  end

  # [claude-code] The span type: a free Boolean algebra over arc
  # leaves, plus ordinal selection.
  # {:arcs, scope, grain, arcs} - same-cycle leaves, normalized.
  # {:absolute, interval} - an already-linear kernel interval lifted
  # into the algebra; the only place a bound may be nil (a ray).
  # {:union, []} and {:intersection, []} are the canonical empty set
  # and universe: a union of nothing is nothing, an intersection of
  # no constraints is everything.
  # {:nth, n, span, per} - the n-th grain cell of the inner span
  # within each instance of the `per` cycle (negative n counts from
  # the end): nth(-1, weekdays, per: :month) is the last working day
  # of the month.
  @type n :: pos_integer() | neg_integer()
  @type t ::
          {:arcs, Point.scope(), Point.grain_class(), [Arc.t(), ...]}
          | {:absolute, Intervals.interval()}
          | {:union, [t()]}
          | {:intersection, [t()]}
          | {:complement, t()}
          | {:nth, n(), t(), Point.cycle()}

  # [claude-code] Added (2026-08-05, Linear YUR-80 / decision D4).
  # The horizon used to be spec'd as the kernel's interval(), which
  # admits nil endpoints and Time values - shapes check_horizon!/1
  # rejects. A spec that admits values the code refuses is a lie, so
  # the type is now exactly what the code takes. The timezone specs
  # below narrowed the same way: Timex.Types.valid_timezone() admits
  # atoms and integers, but wall_date/2 and the tzdata walk take a
  # zone NAME only, so the honest type is String.t().
  @typedoc """
  A bounded evaluation window for `ground/3`: a kernel-shaped map
  whose two endpoints are both present and both `DateTime`. Many
  spans are infinite, so an unbounded ground cannot terminate — the
  type has no `nil` sides. When there is no right bound, use
  `stream/3` instead.
  """
  @type horizon :: %{
          from: DateTime.t(),
          until: DateTime.t(),
          left: Intervals.closing(),
          right: Intervals.closing()
        }

  @cycles [:year, :month, :week, :day]

  # [claude-code] Canonical constants: every smart constructor
  # rewrites toward them, so tests may pin them structurally.

  @doc """
  The empty set: a union of nothing.

      iex> Zocam.Span.empty()
      {:union, []}
  """
  @spec empty() :: t()
  def empty, do: {:union, []}

  @doc """
  The whole timeline: an intersection of no constraints.

      iex> Zocam.Span.universe()
      {:intersection, []}

  The two constants are dual under complement:

      iex> Zocam.Span.complement(Zocam.Span.empty()) == Zocam.Span.universe()
      true
  """
  @spec universe() :: t()
  def universe, do: {:intersection, []}

  # ── Constructors ───────────────────────────────────────────────────

  # [claude-code]
  @doc """
  Lift a point into the set algebra: the set of all instants the
  point denotes (one grain-sized interval per scope instance).

  The result is a one-arc node whose bounds are both the point's
  chain, closed on both sides: "May" is the arc `May..May`.

      iex> may = Zocam.Span.of(Zocam.Point.month(:may))
      iex> match?({:arcs, :year, :month, [%Zocam.Span.Arc{}]}, may)
      true
      iex> Zocam.Span.member?(may, ~U[2026-05-15 12:00:00Z])
      true
      iex> Zocam.Span.member?(may, ~U[2026-06-01 00:00:00Z])
      false
  """
  @spec of(Point.t()) :: t()
  def of(%Point{} = point) do
    {:arcs, point.scope, Point.grain_class(point),
     [
       %Arc{
         from: point.chain,
         until: point.chain,
         left: :closed,
         right: :closed,
         step: nil,
         overflow: point.overflow
       }
     ]}
  end

  # [claude-code]
  @doc """
  Build a one-arc span between two points of the same form.

  Options: `from:`, `until:` (both `Point.t()`, required, same scope
  and grain class), `left:`, `right:` (closings; defaults: `:closed`
  on both sides for bare-unit grains, `:closed`/`:open` when the
  grain is `:time`), `step:` (default: no sampling). A bare integer
  step means `{n, grain}` and is legal only at discrete grains; at
  `:time` grain the unit is mandatory (`{15, :minute}`).

  `from == until` names the single unit (`:open` on any side excludes
  it entirely, so the result is `empty/0`). A bound order that runs
  backward in cycle order wraps: `november..february`,
  `friday..monday`. On the `:absolute` scope there is no cycle to
  wrap in, so backward bounds raise.

  ## Examples

  The common arc: a block of weekdays, "Friday through Monday".
  Jan 10 2026 is a Saturday; Jan 7 is a Wednesday:

      iex> weekend = Zocam.Span.arc!(
      ...>   from: Zocam.Point.weekday(:friday),
      ...>   until: Zocam.Point.weekday(:monday)
      ...> )
      iex> Zocam.Span.member?(weekend, ~U[2026-01-10 12:00:00Z])
      true
      iex> Zocam.Span.member?(weekend, ~U[2026-01-07 12:00:00Z])
      false

  A time window with a step: "every 15 minutes from 09:00 to 17:00":

      iex> every_15 = Zocam.Span.arc!(
      ...>   from: Zocam.Point.time(~T[09:00:00]),
      ...>   until: Zocam.Point.time(~T[17:00:00]),
      ...>   step: {15, :minute}
      ...> )
      iex> Zocam.Span.member?(every_15, ~U[2026-05-15 09:15:00Z])
      true
      iex> Zocam.Span.member?(every_15, ~U[2026-05-15 09:07:00Z])
      false

  The edge: backward bounds wrap. "November through February" is one
  continuous block across the year seam, so December is inside:

      iex> winter = Zocam.Span.arc!(
      ...>   from: Zocam.Point.month(:november),
      ...>   until: Zocam.Point.month(:february)
      ...> )
      iex> Zocam.Span.member?(winter, ~U[2026-12-15 12:00:00Z])
      true
      iex> Zocam.Span.member?(winter, ~U[2027-02-15 12:00:00Z])
      true
      iex> Zocam.Span.member?(winter, ~U[2026-06-15 12:00:00Z])
      false

  The pitfall: `May..May` with an open side is the empty set, never
  "everything except May". Wrap is decided at the chain level, before
  closings expand, and a whole-unit `:open` excludes the whole unit:

      iex> Zocam.Span.arc!(
      ...>   from: Zocam.Point.month(:may),
      ...>   until: Zocam.Point.month(:may),
      ...>   left: :open,
      ...>   right: :open
      ...> )
      {:union, []}

  On the `:absolute` scope there is no cycle to wrap in, so backward
  bounds raise instead:

      iex> Zocam.Span.arc!(from: Zocam.Point.year(2027), until: Zocam.Point.year(2026))
      ** (ArgumentError) absolute bounds run backward: [year: 2027] is after [year: 2026]. The timeline has no cycle to wrap in; swap the bounds.

  A bare integer step at `:time` grain is rejected — `Time` has no
  unit cell, so the unit must be explicit:

      iex> Zocam.Span.arc!(
      ...>   from: Zocam.Point.time(~T[09:00:00]),
      ...>   until: Zocam.Point.time(~T[17:00:00]),
      ...>   step: 2
      ...> )
      ** (ArgumentError) a bare integer step counts grain units, and :time has no unit cell. Give the unit explicitly: {2, :minute}, {2, :hour}, ...
  """
  @spec arc!(
          from: Point.t(),
          until: Point.t(),
          left: Intervals.closing(),
          right: Intervals.closing(),
          step: pos_integer() | step()
        ) :: t()
  def arc!(opts) when is_list(opts) do
    from = fetch_point!(opts, :from)
    until = fetch_point!(opts, :until)

    if from.scope != until.scope or Point.grain_class(from) != Point.grain_class(until) do
      raise ArgumentError,
            "arc bounds must have the same form (scope and grain): " <>
              "#{inspect(from.chain)} repeats per #{inspect(Point.scope_class(from))} at grain " <>
              "#{inspect(Point.grain_class(from))}, but #{inspect(until.chain)} repeats per " <>
              "#{inspect(Point.scope_class(until))} at grain #{inspect(Point.grain_class(until))}. " <>
              "Bounds in different cycles describe a set: build it with Span.intersection/1."
    end

    if from.overflow != until.overflow do
      raise ArgumentError,
            "arc bounds disagree on overflow (#{inspect(from.overflow)} vs " <>
              "#{inspect(until.overflow)}). Give both bounds the same policy."
    end

    grain = Point.grain_class(from)
    left = fetch_closing!(opts, :left, :closed)
    right = fetch_closing!(opts, :right, if(grain == :time, do: :open, else: :closed))
    step = normalize_step!(Keyword.get(opts, :step), grain, from.chain)

    cond do
      # Single unit + an open side: the whole unit is excluded, so
      # nothing remains. Decided at the chain level, before any
      # closing expands - May..May is never a wrap.
      from.chain == until.chain and grain != :time and (left == :open or right == :open) ->
        empty()

      from.chain == until.chain and grain == :time and (left == :open or right == :open) ->
        empty()

      from.scope == :absolute and backward_absolute?(from, until) ->
        raise ArgumentError,
              "absolute bounds run backward: #{inspect(from.chain)} is after " <>
                "#{inspect(until.chain)}. The timeline has no cycle to wrap in; swap the bounds."

      true ->
        {:arcs, from.scope, grain,
         [
           %Arc{
             from: from.chain,
             until: until.chain,
             left: left,
             right: right,
             step: step,
             overflow: from.overflow
           }
         ]}
    end
  end

  # [claude-code]
  @doc """
  Wrap an already-linear interval (`Zocam.Intervals` spec) as a
  span, e.g. "from 2026-05-23 onward". This is where unbounded sides
  live: cyclic arcs always have both bounds, absolute ones may not.
  Bounds must be `DateTime` (or `nil` for a ray): a span meets the
  timeline as instants, never as bare wall values.

      iex> onward = Zocam.Span.absolute!(from: ~U[2026-05-23 00:00:00Z])
      iex> Zocam.Span.member?(onward, ~U[2026-08-01 12:00:00Z])
      true
      iex> Zocam.Span.member?(onward, ~U[2026-05-22 12:00:00Z])
      false

  The pitfall: a wall value is not an instant, so a `Time` bound is
  refused here — build a daily window with `arc!/1` instead:

      iex> Zocam.Span.absolute!(from: ~T[09:00:00])
      ** (ArgumentError) absolute!/1 from: must be a DateTime or nil, got ~T[09:00:00]. Wall values (Time, month atoms) belong to Point and arc!/1.
  """
  @spec absolute!(Intervals.valid_interval()) :: t()
  def absolute!(%{from: _, until: _} = interval), do: check_absolute!(interval)

  def absolute!(opts) when is_list(opts) do
    opts
    |> Intervals.check_interval_opts!()
    |> Intervals.interval_from_opts()
    |> check_absolute!()
  end

  # ── Set operators ──────────────────────────────────────────────────
  # [claude-code] Smart constructors, not raw tuples: they flatten
  # nested unions/intersections, absorb empty and universe, merge
  # same-(scope, grain) arc leaves, and collapse double complements.
  # Equality on spans is equality of this quasi-canonical form; true
  # semantic equality needs a horizon.

  @doc """
  The union of the given spans. `union([])` is `empty/0`.

      iex> weekend = Zocam.Span.union([
      ...>   Zocam.Span.of(Zocam.Point.weekday(:saturday)),
      ...>   Zocam.Span.of(Zocam.Point.weekday(:sunday))
      ...> ])
      iex> Zocam.Span.member?(weekend, ~U[2026-01-10 12:00:00Z])
      true

  The edge: same-cycle leaves merge eagerly. January and February
  tile the year cycle side by side, so their union *is* the arc
  `Jan..Feb` — one node, not two:

      iex> Zocam.Span.union([
      ...>   Zocam.Span.of(Zocam.Point.month(:january)),
      ...>   Zocam.Span.of(Zocam.Point.month(:february))
      ...> ]) == Zocam.Span.arc!(from: Zocam.Point.month(:january), until: Zocam.Point.month(:february))
      true
  """
  @spec union([t()]) :: t()
  def union(spans) when is_list(spans) do
    flat =
      spans
      |> Enum.flat_map(fn
        {:union, inner} -> inner
        other -> [other]
      end)
      |> Enum.uniq()

    if universe() in flat do
      universe()
    else
      case merge_arc_nodes(flat) do
        [] -> empty()
        [single] -> single
        many -> {:union, many}
      end
    end
  end

  @doc """
  The intersection of the given spans. `intersection([])` is
  `universe/0`.

  A cross-cycle intersection ("Wednesdays in May") has no finite
  normal form before grounding, so the node holds it as data and the
  two interpreters answer. May 6 2026 is a Wednesday; Apr 29 is a
  Wednesday outside May:

      iex> weds_in_may = Zocam.Span.intersection([
      ...>   Zocam.Span.of(Zocam.Point.month(:may)),
      ...>   Zocam.Span.of(Zocam.Point.weekday(:wednesday))
      ...> ])
      iex> Zocam.Span.member?(weds_in_may, ~U[2026-05-06 12:00:00Z])
      true
      iex> Zocam.Span.member?(weds_in_may, ~U[2026-04-29 12:00:00Z])
      false
  """
  @spec intersection([t()]) :: t()
  def intersection(spans) when is_list(spans) do
    flat =
      spans
      |> Enum.flat_map(fn
        {:intersection, inner} -> inner
        other -> [other]
      end)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == universe()))

    cond do
      empty() in flat -> empty()
      flat == [] -> universe()
      match?([_], flat) -> hd(flat)
      true -> {:intersection, flat}
    end
  end

  @doc """
  Everything outside the given span.

      iex> not_may = Zocam.Span.complement(Zocam.Span.of(Zocam.Point.month(:may)))
      iex> Zocam.Span.member?(not_may, ~U[2026-05-15 12:00:00Z])
      false
      iex> Zocam.Span.member?(not_may, ~U[2026-06-15 12:00:00Z])
      true

  A double complement collapses back to the original span:

      iex> may = Zocam.Span.of(Zocam.Point.month(:may))
      iex> Zocam.Span.complement(Zocam.Span.complement(may)) == may
      true
  """
  @spec complement(t()) :: t()
  def complement(span) do
    case span do
      {:union, []} -> universe()
      {:intersection, []} -> empty()
      {:complement, inner} -> inner
      other -> {:complement, other}
    end
  end

  # [claude-code]
  @doc """
  Set difference: `a` without `b`.

  Defined as `intersection([a, complement(b)])`. One-versus-many and
  many-versus-one are not special cases: "many" is already a union
  value on either side. The linear kernel computes its own diff the
  same way, so the two layers agree by construction.

  Weekdays without Wednesdays — Jan 6 2026 is a Tuesday, Jan 7 a
  Wednesday:

      iex> weekdays = Zocam.Span.arc!(
      ...>   from: Zocam.Point.weekday(:monday),
      ...>   until: Zocam.Point.weekday(:friday)
      ...> )
      iex> no_wednesdays = Zocam.Span.diff(weekdays, Zocam.Span.of(Zocam.Point.weekday(:wednesday)))
      iex> Zocam.Span.member?(no_wednesdays, ~U[2026-01-06 12:00:00Z])
      true
      iex> Zocam.Span.member?(no_wednesdays, ~U[2026-01-07 12:00:00Z])
      false

  Subtracting nothing changes nothing — the empty span absorbs
  instead of erasing:

      iex> may = Zocam.Span.of(Zocam.Point.month(:may))
      iex> Zocam.Span.diff(may, Zocam.Span.empty()) == may
      true
  """
  @spec diff(t(), t()) :: t()
  def diff(a, b), do: intersection([a, complement(b)])

  # [claude-code]
  @doc """
  Ordinal selection: the `n`-th grain cell of `span` inside each
  instance of the `per` cycle. Negative `n` counts from the end.

  A missing ordinal skips the instance (no 5th Wednesday: nothing).
  Grounding widens to whole `per` instances before counting, then
  clips to the horizon, so a cut-off January never miscounts its
  last Friday.

  The inner span must be cyclic with day-sized grain cells: `nth`
  counts days, and an `{:absolute, _}` node or a `:time`-grain leaf
  has no day cells to count.

  ## Examples

  The last Friday of each month. January 2026 has Fridays on the
  2nd, 9th, 16th, 23rd, and 30th:

      iex> last_friday = Zocam.Span.nth(-1, Zocam.Span.of(Zocam.Point.weekday(:friday)), per: :month)
      iex> Zocam.Span.member?(last_friday, ~U[2026-01-30 12:00:00Z])
      true
      iex> Zocam.Span.member?(last_friday, ~U[2026-01-23 12:00:00Z])
      false

  The edge: a missing ordinal skips. February 2026 has four
  Wednesdays, so its "5th Wednesday" names nothing — it does not
  clamp onto the last one. April has five:

      iex> fifth_wed = Zocam.Span.nth(5, Zocam.Span.of(Zocam.Point.weekday(:wednesday)), per: :month)
      iex> Zocam.Span.member?(fifth_wed, ~U[2026-04-29 12:00:00Z])
      true
      iex> Zocam.Span.member?(fifth_wed, ~U[2026-02-25 12:00:00Z])
      false

  The pitfall: "the first 09:00 of the month" reads well, but a
  `:time`-grain span has no day cells to count. Select the day
  first, then intersect with the time window:

      iex> Zocam.Span.nth(1, Zocam.Span.of(Zocam.Point.time(~T[09:00:00])), per: :month)
      ** (ArgumentError) nth/3 counts day cells; a :time-grain span has none. Select the day first, then intersect with the time window.
  """
  @spec nth(n(), t(), per: Point.cycle()) :: t()
  def nth(n, span, opts) when is_integer(n) and n != 0 and is_list(opts) do
    per = Keyword.fetch!(opts, :per)

    unless per in @cycles do
      raise ArgumentError, "nth per: must be a cycle in #{inspect(@cycles)}, got #{inspect(per)}"
    end

    validate_nth_inner!(span)
    {:nth, n, span, per}
  end

  # ── Interpreters ───────────────────────────────────────────────────

  # [claude-code]
  @doc """
  Is the instant inside the set? Symbolic: no horizon, no
  enumeration. Reads the wall clock of the given DateTime and applies
  the same denotation as `ground/3`.

      iex> may = Zocam.Span.of(Zocam.Point.month(:may))
      iex> Zocam.Span.member?(may, ~U[2026-05-15 12:00:00Z])
      true

  Clamping is part of the shared denotation, so the two interpreters
  cannot disagree on it. February 2026 has 28 days; under the
  default `:clamp` the 31st fires on Feb 28, and under `:skip` it
  does not:

      iex> Zocam.Span.member?(Zocam.Span.of(Zocam.Point.day(31)), ~U[2026-02-28 12:00:00Z])
      true
      iex> literal_31st = Zocam.Point.new!(scope: :month, chain: [day: 31], overflow: :skip)
      iex> Zocam.Span.member?(Zocam.Span.of(literal_31st), ~U[2026-02-28 12:00:00Z])
      false
  """
  @spec member?(t(), DateTime.t()) :: boolean()
  def member?(span, %DateTime{} = at) do
    # [claude-code] Added 2026-08-05 (Linear YUR-57). member_at/2 turns
    # the instant into a wall date and reads its numbers as ISO.
    ISO.check!(at, "the member?/2 instant")
    member_at(span, at)
  end

  # [claude-code]
  @doc """
  Evaluate the span over a bounded horizon into the linear kernel.

  Enumerates every scope instance that intersects the horizon,
  grounds each fully (an instance may yield more than one kernel
  interval on DST fall-back days), then clips to the horizon and
  compresses. The horizon must be bounded on both sides: many spans
  are infinite, so an unbounded ground cannot terminate — use
  `stream/3` when there is no right bound.

  ## Examples

  The common call: one cyclic point, one bounded horizon, UTC.

      iex> may = Zocam.Span.of(Zocam.Point.month(:may))
      iex> horizon = %{
      ...>   from: ~U[2026-01-01 00:00:00Z],
      ...>   until: ~U[2027-01-01 00:00:00Z],
      ...>   left: :closed,
      ...>   right: :open
      ...> }
      iex> Zocam.Span.ground(may, horizon, "Etc/UTC").intervals
      [%{from: ~U[2026-05-01 00:00:00Z], until: ~U[2026-06-01 00:00:00Z], left: :closed, right: :open}]

  The DST fold: on 2026-11-01, America/New_York sets its clocks
  back, so the wall window 00:30..01:30 exists twice — once in EDT,
  and partly again in EST. One instance grounds to *two* intervals:

      iex> night = Zocam.Span.arc!(
      ...>   from: Zocam.Point.time(~T[00:30:00]),
      ...>   until: Zocam.Point.time(~T[01:30:00])
      ...> )
      iex> fall_back = %{
      ...>   from: ~U[2026-11-01 00:00:00Z],
      ...>   until: ~U[2026-11-02 00:00:00Z],
      ...>   left: :closed,
      ...>   right: :open
      ...> }
      iex> Zocam.Span.ground(night, fall_back, "America/New_York").intervals
      [
        %{from: ~U[2026-11-01 04:30:00Z], until: ~U[2026-11-01 05:30:00Z], left: :closed, right: :open},
        %{from: ~U[2026-11-01 06:00:00Z], until: ~U[2026-11-01 06:30:00Z], left: :closed, right: :open}
      ]

  The DST gap: on 2026-03-08 the wall time 02:30 never appears on a
  New York clock, so that instance grounds to nothing:

      iex> spring = %{
      ...>   from: ~U[2026-03-08 00:00:00Z],
      ...>   until: ~U[2026-03-09 00:00:00Z],
      ...>   left: :closed,
      ...>   right: :open
      ...> }
      iex> Zocam.Span.ground(Zocam.Span.of(Zocam.Point.time(~T[02:30:00])), spring, "America/New_York").intervals
      []
  """
  @spec ground(t(), horizon(), String.t()) :: Intervals.t()
  def ground(span, horizon, timezone) do
    horizon = check_horizon!(horizon)
    pieces = eval(span, horizon, timezone)
    # [claude-code] Changed (2026-08-05, decision D2): compress/1
    # answers with the struct itself now, so no wrapping remains.
    Intervals.compress(pieces)
  end

  # [claude-code]
  @doc """
  Does the span contain no instant inside the horizon?

  February 2026 has four Wednesdays, so its "5th Wednesday" is empty
  there — and not empty in April, which has five:

      iex> fifth_wed = Zocam.Span.of(Zocam.Point.day({:nth, 5, :wednesday}))
      iex> feb = %{from: ~U[2026-02-01 00:00:00Z], until: ~U[2026-03-01 00:00:00Z], left: :closed, right: :open}
      iex> Zocam.Span.empty?(fifth_wed, feb, "Etc/UTC")
      true
      iex> apr = %{from: ~U[2026-04-01 00:00:00Z], until: ~U[2026-05-01 00:00:00Z], left: :closed, right: :open}
      iex> Zocam.Span.empty?(fifth_wed, apr, "Etc/UTC")
      false
  """
  # [claude-code] Changed (2026-08-05, decision D1): the set is
  # enumerable, so the emptiness question goes through Enum.
  @spec empty?(t(), horizon(), String.t()) :: boolean()
  def empty?(span, horizon, timezone), do: Enum.empty?(ground(span, horizon, timezone))

  # [claude-code] The stream grounds one year at a time, with one
  # more year of lookahead. An interval that starts inside a chunk is
  # emitted whole. An interval longer than the lookahead is clipped;
  # this is a documented trade-off. Each later chunk grounds from one
  # second before its cursor. An interval that only continues across
  # the cursor starts before it, so the filter drops it. An interval
  # that starts exactly at the cursor survives.
  @chunk_seconds 366 * 86_400

  @doc """
  Lazily enumerate the span's intervals from an instant forward, in
  order. The stream grounds chunk by chunk (one year at a time, with
  a one-year lookahead), so it works without a right bound; take
  from it what you need.

  The first two Wednesdays of 2026 fall on Jan 7 and Jan 14:

      iex> weds = Zocam.Span.of(Zocam.Point.weekday(:wednesday))
      iex> Zocam.Span.stream(weds, ~U[2026-01-01 00:00:00Z], "Etc/UTC") |> Enum.take(2)
      [
        %{from: ~U[2026-01-07 00:00:00Z], until: ~U[2026-01-08 00:00:00Z], left: :closed, right: :open},
        %{from: ~U[2026-01-14 00:00:00Z], until: ~U[2026-01-15 00:00:00Z], left: :closed, right: :open}
      ]
  """
  @spec stream(t(), DateTime.t(), String.t()) :: Enumerable.t()
  def stream(span, %DateTime{} = from, timezone) do
    # [claude-code] Added 2026-08-05 (Linear YUR-57). The check sits
    # here, not inside the start function: Stream.resource/3 is lazy,
    # so a check in the start function would fire on the first take,
    # far away from the call that holds the mistake. Every later cursor
    # comes from DateTime.add/3 on this value, and that keeps the
    # calendar, so one check at the source covers the whole stream.
    ISO.check!(from, "the stream/3 start instant")

    Stream.resource(
      fn -> {from, true} end,
      fn {cursor, first?} ->
        next = DateTime.add(cursor, @chunk_seconds, :second)
        ground_from = if first?, do: cursor, else: DateTime.add(cursor, -1, :second)

        horizon = %{
          from: ground_from,
          until: DateTime.add(next, @chunk_seconds, :second),
          left: :closed,
          right: :open
        }

        # [claude-code] Changed (2026-08-05, decision D1): the set is
        # enumerable, so the filter walks it directly.
        emitted =
          ground(span, horizon, timezone)
          |> Enum.filter(fn i ->
            starts = i.from == nil or DateTime.compare(i.from, cursor) != :lt
            in_chunk = i.from == nil or DateTime.compare(i.from, next) == :lt
            (first? or starts) and in_chunk
          end)

        {emitted, {next, false}}
      end,
      fn _ -> :ok end
    )
  end

  # ── Shared denotation: membership ──────────────────────────────────

  # [claude-code] The wall-time interpreter. It accepts a DateTime
  # (public member?/2) or a NaiveDateTime (internal probes, e.g. nth
  # day counting); both are read as wall clocks. Only {:absolute, _}
  # nodes need a real instant - nth/3 validation keeps them out of
  # probe positions.
  @spec member_at(t(), DateTime.t() | NaiveDateTime.t()) :: boolean()
  defp member_at({:union, spans}, at), do: Enum.any?(spans, &member_at(&1, at))
  defp member_at({:intersection, spans}, at), do: Enum.all?(spans, &member_at(&1, at))
  defp member_at({:complement, span}, at), do: not member_at(span, at)

  defp member_at({:absolute, interval}, %DateTime{} = at) do
    lower =
      interval.from == nil or
        case DateTime.compare(at, interval.from) do
          :gt -> true
          :eq -> interval.left == :closed
          :lt -> false
        end

    upper =
      interval.until == nil or
        case DateTime.compare(at, interval.until) do
          :lt -> true
          :eq -> interval.right == :closed
          :gt -> false
        end

    lower and upper
  end

  defp member_at({:absolute, _interval}, %NaiveDateTime{}) do
    raise ArgumentError,
          "an absolute span compares instants, and a bare wall time is not an " <>
            "instant. This happens only when an {:absolute, _} node sits inside " <>
            "an nth/3 selection, which nth/3 rejects."
  end

  defp member_at({:arcs, scope, grain, arcs}, at) do
    wall = to_wall(at)

    case base_cycle(scope) do
      :absolute ->
        Enum.any?(arcs, fn arc ->
          arc
          |> arc_windows(grain, :absolute, :absolute)
          |> Enum.any?(&window_contains?(&1, wall))
        end)

      cycle ->
        date = NaiveDateTime.to_date(wall)
        idx = instance_index(cycle, date)

        # The probe's instance and its predecessor: a wrapping arc
        # materializes forward, so a block that started last instance
        # can still cover the probe.
        for i <- [idx - 1, idx], selected_instance?(scope, cycle, i), reduce: false do
          acc ->
            acc or
              Enum.any?(arcs, fn arc ->
                arc
                |> arc_windows(grain, container(cycle, i), container(cycle, i + 1))
                |> Enum.any?(&window_contains?(&1, wall))
              end)
        end
    end
  end

  defp member_at({:nth, n, inner, per}, at) do
    wall = to_wall(at)
    date = NaiveDateTime.to_date(wall)

    case nth_day(n, inner, per, instance_index(per, date)) do
      nil -> false
      day -> Date.compare(day, date) == :eq
    end
  end

  # ── Shared denotation: windows ─────────────────────────────────────

  # [claude-code] A wall window: a half-open or explicitly closed
  # interval of naive wall time. Discrete cells always render as
  # {start, next_start, :closed, :open}, which encodes whole-unit
  # closings exactly. Time-grain windows carry the user's closings
  # and may be degenerate ({t, t, :closed, :closed} is one instant).
  @typep wall_window ::
           {NaiveDateTime.t(), NaiveDateTime.t(), Intervals.closing(), Intervals.closing()}

  @spec window_contains?(wall_window(), NaiveDateTime.t()) :: boolean()
  defp window_contains?({from, until, left, right}, wall) do
    lower =
      case NaiveDateTime.compare(wall, from) do
        :gt -> true
        :eq -> left == :closed
        :lt -> false
      end

    upper =
      case NaiveDateTime.compare(wall, until) do
        :lt -> true
        :eq -> right == :closed
        :gt -> false
      end

    lower and upper
  end

  # [claude-code] All wall windows of one arc within one scope
  # instance (or on the :absolute pseudo-instance). This is the heart
  # of the shared denotation: member?/2 checks these windows against
  # a wall clock, ground/3 maps them into UTC. Wrapping bounds
  # resolve forward into the next instance (next_cont, computed by
  # the caller as container(cycle, idx + 1) so a real calendar month
  # follows a month), so the result may extend past the instance's
  # own end - by design.
  @spec arc_windows(Arc.t(), Point.grain_class(), instance_container(), instance_container()) ::
          [wall_window()]
  defp arc_windows(%Arc{} = arc, :time, cont, next_cont) do
    with {:ok, {f, _}} <- chain_window(arc.from, cont, arc.overflow),
         {:ok, {u, _}} <- chain_window(arc.until, cont, arc.overflow) do
      u =
        if NaiveDateTime.compare(u, f) == :lt do
          # Wrap: 22:00..06:00 continues into the next instance.
          {:ok, {u2, _}} = chain_window(arc.until, next_cont, arc.overflow)
          u2
        else
          u
        end

      case arc.step do
        nil ->
          if NaiveDateTime.compare(f, u) == :lt or
               (f == u and arc.left == :closed and arc.right == :closed) do
            [{f, u, arc.left, arc.right}]
          else
            []
          end

        {n, unit} ->
          seconds = time_unit_seconds(unit) * n
          time_samples(f, u, seconds, arc.left, arc.right)
      end
    else
      :skip -> []
    end
  end

  defp arc_windows(%Arc{} = arc, _grain, cont, next_cont) do
    with {:ok, {ffrom, funtil}} <- chain_window(arc.from, cont, arc.overflow),
         {:ok, {ufrom, uuntil}} <- chain_window(arc.until, cont, arc.overflow) do
      # Wrap is decided at the CHAIN level where the cells are fixed
      # (day 30 .. day 29 wraps in every month, even when February
      # clamps both to the 28th). Only bounds without a nominal order
      # (ordinal selectors, negative day indices) fall back to the
      # resolved dates, where per-instance order is the meaning.
      wrap? =
        case nominal_order(arc.until, arc.from) do
          :lt -> true
          :unknown -> NaiveDateTime.compare(ufrom, ffrom) == :lt
          _ -> false
        end

      {ufrom, uuntil} =
        if wrap? do
          case chain_window(arc.until, next_cont, arc.overflow) do
            {:ok, pair} -> pair
            :skip -> throw(:skip_arc)
          end
        else
          {ufrom, uuntil}
        end

      case arc.step do
        nil ->
          # Whole-unit closings move the block edges by whole cells.
          start = if arc.left == :closed, do: ffrom, else: funtil
          stop = if arc.right == :closed, do: uuntil, else: ufrom

          if NaiveDateTime.compare(start, stop) == :lt,
            do: [{start, stop, :closed, :open}],
            else: []

        {n, unit} ->
          discrete_samples(arc, cont, next_cont, n, unit, {ffrom, funtil}, ufrom)
      end
    else
      :skip -> []
    end
  catch
    :skip_arc -> []
  end

  # [claude-code] Sub-day sampling: instants f, f+s, f+2s, ... up to
  # the until instant. An :open left drops the first sample; an :open
  # right drops a sample that lands exactly on the until bound.
  @spec time_samples(
          NaiveDateTime.t(),
          NaiveDateTime.t(),
          pos_integer(),
          Intervals.closing(),
          Intervals.closing()
        ) :: [wall_window()]
  defp time_samples(f, u, seconds, left, right) do
    f
    |> Stream.iterate(&NaiveDateTime.add(&1, seconds, :second))
    |> Enum.reduce_while([], fn sample, acc ->
      case NaiveDateTime.compare(sample, u) do
        :gt -> {:halt, acc}
        :eq -> {:halt, if(right == :closed, do: [sample | acc], else: acc)}
        :lt -> {:cont, [sample | acc]}
      end
    end)
    |> Enum.reverse()
    |> then(fn samples -> if left == :open, do: tl(samples), else: samples end)
    |> Enum.map(&{&1, &1, :closed, :closed})
  end

  # [claude-code] Discrete sampling. Two supported step families:
  # a day-sized unit over day-sized cells (Fri..Mon step {2, :day} -
  # pure date arithmetic through the wrap seam), and a nominal
  # :month step over [month] or [month, day] chains ("the 31st,
  # monthly": the nominal day is kept and each landing clamps or
  # skips on its own). The month walk counts months from zero and
  # keeps walking past December into next_cont, so a wrapping arc
  # (Nov..Feb) samples through the year seam. Anything else raises
  # at arc!/1 time, not here.
  @spec discrete_samples(
          Arc.t(),
          instance_container(),
          instance_container(),
          pos_integer(),
          Point.unit() | time_unit(),
          {NaiveDateTime.t(), NaiveDateTime.t()},
          NaiveDateTime.t()
        ) :: [wall_window()]
  defp discrete_samples(arc, cont, next_cont, n, unit, {ffrom, _funtil}, ufrom) do
    limit = ufrom

    cells =
      cond do
        unit_class_of(unit) == :day ->
          NaiveDateTime.to_date(ffrom)
          |> Stream.iterate(&Date.add(&1, n))
          |> Stream.map(&{:ok, {naive(&1), naive(Date.add(&1, 1))}})

        unit == :month ->
          {m0, day_spec} = month_day_of!(arc.from)

          Stream.iterate(m0 - 1, &(&1 + n))
          |> Stream.take_while(&(&1 <= 23))
          |> Stream.map(fn month_index ->
            {cell_cont, m} =
              if month_index <= 11,
                do: {cont, month_index + 1},
                else: {next_cont, month_index - 11}

            chain =
              if day_spec == nil,
                do: [month: Point.month_atom(m)],
                else: [month: Point.month_atom(m), day: day_spec]

            chain_window(chain, cell_cont, arc.overflow)
          end)

        true ->
          raise ArgumentError, "unsupported step unit #{inspect(unit)}"
      end

    cells
    |> Enum.reduce_while([], fn
      :skip, acc ->
        {:cont, acc}

      {:ok, {start, stop}}, acc ->
        case NaiveDateTime.compare(start, limit) do
          :gt -> {:halt, acc}
          :eq -> {:halt, if(arc.right == :closed, do: [{start, stop} | acc], else: acc)}
          :lt -> {:cont, [{start, stop} | acc]}
        end
    end)
    |> Enum.reverse()
    |> then(fn samples ->
      # An :open left excludes the from cell wholly; the phase stays
      # anchored on it.
      if arc.left == :open, do: Enum.drop(samples, 1), else: samples
    end)
    |> Enum.map(fn {start, stop} -> {start, stop, :closed, :open} end)
  end

  @spec month_day_of!(Point.chain()) :: {1..12, Point.day_index() | Point.nth_weekday() | nil}
  defp month_day_of!(chain) do
    case chain do
      [month: m, day: d] ->
        {Point.month_number(m), d}

      [month: m] ->
        {Point.month_number(m), nil}

      other ->
        raise ArgumentError,
              "a :month step needs a [month] or [month, day] chain, got #{inspect(other)}"
    end
  end

  # ── Shared denotation: chains ──────────────────────────────────────

  # [claude-code] An instance container: the concrete date range of
  # one scope instance, half-open, or the :absolute pseudo-instance
  # (chains that start at :year carry their own container).
  @typep instance_container :: {Date.t(), Date.t()} | :absolute

  # [claude-code] The one chain resolver both interpreters use. It
  # walks the chain inside a concrete container and narrows it one
  # segment at a time; the empty chain names the whole container. It
  # returns the half-open wall window of what the chain names, or
  # :skip when the chain names nothing here (day 31 under :skip in
  # February, a missing 5th Wednesday, a year without week 53).
  # For a :time segment the window is degenerate: {instant, instant}.
  @spec chain_window(Point.chain() | [], instance_container(), Point.overflow()) ::
          {:ok, {NaiveDateTime.t(), NaiveDateTime.t()}} | :skip
  defp chain_window([], {first, next}, _overflow), do: {:ok, {naive(first), naive(next)}}

  defp chain_window([{:year, y} | rest], :absolute, overflow) do
    chain_window(rest, {Date.new!(y, 1, 1), Date.new!(y + 1, 1, 1)}, overflow)
  end

  defp chain_window([{:month, m} | rest], {first, _next}, overflow) do
    mn = Point.month_number(m)
    start = Date.new!(first.year, mn, 1)
    chain_window(rest, {start, month_after(start)}, overflow)
  end

  defp chain_window([{:week, w} | rest], {first, _next}, overflow) do
    # ISO week w of the year: week 1 contains Jan 4. A year has 52 or
    # 53 weeks; a missing week 53 skips.
    monday1 = Date.beginning_of_week(Date.new!(first.year, 1, 4))
    monday = Date.add(monday1, 7 * (w - 1))

    if :calendar.iso_week_number(Date.to_erl(monday)) == {first.year, w} do
      chain_window(rest, {monday, Date.add(monday, 7)}, overflow)
    else
      :skip
    end
  end

  defp chain_window([{:day, d} | rest], {first, _next}, overflow) when is_integer(d) do
    days = Date.days_in_month(first)

    resolved =
      cond do
        d > 0 and d <= days -> d
        d > 0 and overflow == :clamp -> days
        d > 0 -> :skip
        d < 0 and days + 1 + d >= 1 -> days + 1 + d
        d < 0 and overflow == :clamp -> 1
        true -> :skip
      end

    case resolved do
      :skip ->
        :skip

      day ->
        date = %{first | day: day}
        chain_window(rest, {date, Date.add(date, 1)}, overflow)
    end
  end

  defp chain_window([{:day, {:nth, n, wd}} | rest], {first, next}, overflow) do
    # An ordinal selects; a missing ordinal always skips, independent
    # of the overflow policy (that one is for measured day numbers).
    wdn = Point.weekday_number(wd)

    matches =
      Date.range(first, Date.add(next, -1))
      |> Enum.filter(&(Date.day_of_week(&1) == wdn))

    case nth_of(matches, n) do
      nil -> :skip
      date -> chain_window(rest, {date, Date.add(date, 1)}, overflow)
    end
  end

  defp chain_window([{:weekday, wd} | rest], {monday, _next}, overflow) do
    date = Date.add(monday, Point.weekday_number(wd) - 1)
    chain_window(rest, {date, Date.add(date, 1)}, overflow)
  end

  defp chain_window([{:time, t}], {date, _next}, _overflow) do
    instant = NaiveDateTime.new!(date, t)
    {:ok, {instant, instant}}
  end

  # ── Instances ──────────────────────────────────────────────────────

  # [claude-code] Cycle instances as integers, so that "every k-th
  # instance from an anchor" is modular arithmetic. The week index
  # must be BIJECTIVE with Mondays: container/2 reconstructs the
  # Monday from the index, so the division must not throw away the
  # weekday phase. We anchor it on a known Monday (2026-01-05); every
  # Monday's gregorian day count is congruent to it modulo 7, so the
  # division below is exact for Mondays.
  @monday_phase Integer.mod(:calendar.date_to_gregorian_days({2026, 1, 5}), 7)

  @spec instance_index(Point.cycle(), Date.t()) :: integer()
  defp instance_index(:year, date), do: date.year
  defp instance_index(:month, date), do: date.year * 12 + (date.month - 1)

  defp instance_index(:week, date) do
    gdays =
      date
      |> Date.beginning_of_week()
      |> Date.to_erl()
      |> :calendar.date_to_gregorian_days()

    Integer.floor_div(gdays - @monday_phase, 7)
  end

  defp instance_index(:day, date),
    do: date |> Date.to_erl() |> :calendar.date_to_gregorian_days()

  @spec container(Point.cycle(), integer()) :: instance_container()
  defp container(:year, idx), do: {Date.new!(idx, 1, 1), Date.new!(idx + 1, 1, 1)}

  defp container(:month, idx) do
    start = Date.new!(Integer.floor_div(idx, 12), Integer.mod(idx, 12) + 1, 1)
    {start, month_after(start)}
  end

  defp container(:week, idx) do
    monday = Date.from_erl!(:calendar.gregorian_days_to_date(idx * 7 + @monday_phase))
    {monday, Date.add(monday, 7)}
  end

  defp container(:day, idx) do
    date = Date.from_erl!(:calendar.gregorian_days_to_date(idx))
    {date, Date.add(date, 1)}
  end

  # [claude-code] The first day of the next month. Successor
  # containers are always computed as container(cycle, idx + 1) at
  # the call sites - never by shifting a container by its own length,
  # because months differ in length (a shifted January would make a
  # 31-day "February" and elect wrong ordinal weekdays in it).
  @spec month_after(Date.t()) :: Date.t()
  defp month_after(%Date{year: y, month: 12}), do: Date.new!(y + 1, 1, 1)
  defp month_after(%Date{year: y, month: m}), do: Date.new!(y, m + 1, 1)

  @spec base_cycle(Point.scope()) :: Point.cycle() | :absolute
  defp base_cycle(:absolute), do: :absolute
  defp base_cycle({:every, _k, cycle, %Date{}}), do: cycle
  defp base_cycle(cycle) when cycle in @cycles, do: cycle

  # [claude-code] The {:every, k, cycle, anchor} filter: an instance
  # is selected when it is a whole multiple of k away from the
  # instance that contains the anchor.
  @spec selected_instance?(Point.scope(), Point.cycle() | :absolute, integer()) :: boolean()
  defp selected_instance?({:every, k, cycle, anchor}, cycle, idx) do
    Integer.mod(idx - instance_index(cycle, anchor), k) == 0
  end

  defp selected_instance?(_scope, _cycle, _idx), do: true

  # ── Grounding ──────────────────────────────────────────────────────

  # [claude-code] The second interpreter: evaluate the tree into
  # kernel interval lists, all clipped to the horizon. Union maps to
  # kernel compression, intersection to kernel intersection (seeded
  # with the horizon itself: the universe within a horizon IS the
  # horizon), complement to kernel diff from the horizon.
  # Changed (2026-08-05, decision D2): the kernel operations answer
  # with the %Intervals{} struct now. eval/3 stays list-based
  # internally (its private contract), so the folds read .intervals
  # back - but the comprehension generators consume the struct
  # directly, through its Enumerable implementation (decision D1).
  @spec eval(t(), horizon(), String.t()) :: [Intervals.interval()]
  defp eval({:union, spans}, horizon, tz) do
    Intervals.compress(Enum.flat_map(spans, &eval(&1, horizon, tz))).intervals
  end

  defp eval({:intersection, spans}, horizon, tz) do
    Enum.reduce(spans, [horizon], fn span, acc ->
      case acc do
        [] -> []
        acc -> Intervals.intersect(acc, eval(span, horizon, tz)).intervals
      end
    end)
  end

  defp eval({:complement, span}, horizon, tz) do
    Intervals.diff([horizon], eval(span, horizon, tz)).intervals
  end

  defp eval({:absolute, interval}, horizon, _tz) do
    Intervals.intersect([interval], [horizon]).intervals
  end

  defp eval({:nth, n, inner, per}, horizon, tz) do
    from_idx = instance_index(per, wall_date(horizon.from, tz))
    until_idx = instance_index(per, wall_date(horizon.until, tz))

    for idx <- from_idx..until_idx,
        day = nth_day(n, inner, per, idx),
        day != nil,
        piece <- preimage({naive(day), naive(Date.add(day, 1)), :closed, :open}, tz),
        clipped <- Intervals.intersect([piece], [horizon]) do
      clipped
    end
  end

  defp eval({:arcs, scope, grain, arcs}, horizon, tz) do
    windows =
      case base_cycle(scope) do
        :absolute ->
          Enum.flat_map(arcs, &arc_windows(&1, grain, :absolute, :absolute))

        cycle ->
          from_idx = instance_index(cycle, wall_date(horizon.from, tz)) - 1
          until_idx = instance_index(cycle, wall_date(horizon.until, tz))

          for idx <- from_idx..until_idx,
              selected_instance?(scope, cycle, idx),
              arc <- arcs,
              window <- arc_windows(arc, grain, container(cycle, idx), container(cycle, idx + 1)) do
            window
          end
      end

    for window <- windows,
        piece <- preimage(window, tz),
        clipped <- Intervals.intersect([piece], [horizon]) do
      clipped
    end
  end

  # [claude-code] The n-th day cell of `inner` within one `per`
  # instance - the ONE ordinal counter member?/2 and ground/3 share.
  # It always counts over the whole instance; the horizon clips only
  # afterwards, so a cut-off month cannot elect a wrong "last".
  # Inner membership is probed at noon: nth counts day cells, and a
  # day-grain span either covers a whole day or none of it.
  @spec nth_day(n(), t(), Point.cycle(), integer()) :: Date.t() | nil
  defp nth_day(n, inner, per, idx) do
    {first, next} = container(per, idx)

    Date.range(first, Date.add(next, -1))
    |> Enum.filter(&member_at(inner, NaiveDateTime.new!(&1, ~T[12:00:00])))
    |> nth_of(n)
  end

  @spec nth_of([element], n()) :: element | nil when element: var
  defp nth_of(list, n) when n > 0, do: Enum.at(list, n - 1)
  defp nth_of(list, n), do: Enum.at(list, n)

  # ── Timezone resolution ────────────────────────────────────────────

  # [claude-code] The wall-to-UTC preimage of one wall window, via the
  # tzdata period table. Each timezone period that overlaps the wall
  # window contributes one UTC piece: the window clipped to the
  # period's wall range, shifted by the period's offset. A fall-back
  # window overlaps two periods (two pieces: the wall clock shows it
  # twice); a window inside a spring-forward gap overlaps none.
  # Changed (2026-08-05, Linear YUR-78): each period is paired with
  # its successor's wall start, because the closing of an edge that
  # sits ON a period boundary depends on what the wall clock does
  # there - see period_piece/3.
  @spec preimage(wall_window(), String.t()) :: [Intervals.interval()]
  defp preimage({from, until, left, right}, tz) do
    periods = overlapping_periods(tz, from, until)

    # The walk in overlapping_periods/3 steps period by period, so
    # consecutive list entries are adjacent on the timeline. Pair each
    # period with the wall start of the next one; the last period has
    # no fetched successor (its boundary lies past the window plus the
    # offset margin, so no clipped edge can sit on it).
    next_wall_starts = periods |> Enum.drop(1) |> Enum.map(& &1.from.wall)

    for {period, next_wall_start} <- Enum.zip(periods, next_wall_starts ++ [nil]),
        piece <- period_piece(period, next_wall_start, {from, until, left, right}),
        do: piece
  end

  # [claude-code] Every timezone period that can read a wall time
  # inside [from, until] - not only the periods at the two endpoints.
  # A long window (a whole year) crosses periods that touch neither
  # endpoint; skipping them would silently drop the whole summer of a
  # DST zone. The walk runs on the UTC axis, which has no gaps and no
  # folds: every UTC instant lies in exactly one period, and each
  # step jumps to the next period's start. The margin turns the wall
  # window into a UTC range that covers every reading of it (UTC
  # offsets stay inside -12h..+14h; 15 h is safely past both).
  @wall_offset_margin 15 * 3600

  @spec overlapping_periods(String.t(), NaiveDateTime.t(), NaiveDateTime.t()) ::
          [map()]
  defp overlapping_periods(tz, from, until) do
    stop = to_gs(until) + @wall_offset_margin
    walk_periods(tz, to_gs(from) - @wall_offset_margin, stop, [])
  end

  @spec walk_periods(String.t(), integer(), integer(), [map()]) :: [map()]
  defp walk_periods(tz, t, stop, acc) when t <= stop do
    case Tzdata.periods_for_time(tz, t, :utc) do
      [period | _] ->
        case period.until.utc do
          :max -> Enum.reverse([period | acc])
          next -> walk_periods(tz, next, stop, [period | acc])
        end

      [] ->
        Enum.reverse(acc)
    end
  end

  defp walk_periods(_tz, _t, _stop, acc), do: Enum.reverse(acc)

  @spec to_gs(NaiveDateTime.t()) :: integer()
  defp to_gs(naive), do: :calendar.datetime_to_gregorian_seconds(NaiveDateTime.to_erl(naive))

  # [claude-code] Changed (2026-08-05, Linear YUR-78): the upper-edge
  # closing is decided by upper_closing/4 now; see the rule there. The
  # old code forced :closed whenever the period boundary supplied the
  # upper edge, which was wrong at a spring-forward gap: the boundary
  # instant reads as a wall time PAST the gap, which the window can
  # exclude - ground/3 then covered an instant member?/2 refused.
  @spec period_piece(map(), integer() | nil, wall_window()) :: [Intervals.interval()]
  defp period_piece(period, next_wall_start, {from, until, left, right}) do
    offset = period.utc_off + period.std_off
    p_from = gs_to_naive(period.from.wall)
    p_until = gs_to_naive(period.until.wall)

    f = if p_from != nil and NaiveDateTime.compare(p_from, from) == :gt, do: p_from, else: from

    u =
      if p_until != nil and NaiveDateTime.compare(p_until, until) == :lt, do: p_until, else: until

    degenerate_ok? =
      from == until and f == from and u == until and
        (p_until == nil or NaiveDateTime.compare(from, p_until) == :lt)

    # [claude-code] Changed (2026-08-05, Linear YUR-78): a clip
    # remnant of one wall instant, exactly at THIS period's start, is
    # kept when the window's closing covers it. The rule exists
    # because upper_closing/4 marks the previous period's edge :open
    # at a DST seam and counts on this period to re-cover the
    # boundary instant B. B reads as this period's wall start:
    # - At a GAP, B reads as the post-jump wall time (02:00 ->
    #   03:00). A window that ENDS on that reading with a :closed
    #   edge covers B, and only this remnant can say so.
    # - At a FOLD, B is the SECOND reading of a repeated wall time
    #   (02:00 -> 01:00). A window that ends there :closed covers
    #   both readings; this remnant is the second one.
    # With a :open edge (or a window that ends before this period)
    # the remnant covers nothing and stays dropped - that is the
    # first YUR-78 fix, unchanged.
    seam_point_ok? =
      p_from != nil and
        NaiveDateTime.compare(f, u) == :eq and
        NaiveDateTime.compare(f, p_from) == :eq and
        (right == :closed or NaiveDateTime.compare(u, until) == :lt)

    if NaiveDateTime.compare(f, u) == :lt or degenerate_ok? or seam_point_ok? do
      [
        %{
          from: to_utc(f, offset),
          until: to_utc(u, offset),
          # A lower edge on the period start is always :closed: a
          # period owns its own start instant, so that instant reads
          # as exactly f - which is inside the window here.
          left: if(f == from, do: left, else: :closed),
          right: upper_closing(period, next_wall_start, u, {until, right})
        }
      ]
    else
      []
    end
  end

  # [claude-code] Added (2026-08-05, Linear YUR-78). The closing of a
  # piece's upper edge at wall time u. The UTC instant at that edge,
  # call it B, is what the closing includes or excludes.
  #
  # When u lies strictly inside the period, B reads as u on the wall
  # clock, so the nominal closing is honest: the user's own closing
  # (u is the window's until).
  #
  # When u sits ON the period boundary, B belongs to the NEXT period
  # (a period is half-open: [from, until) on the UTC axis), so B
  # reads as the next period's wall start. Three cases:
  #
  # - The wall clock jumps there (a DST seam). At a GAP the reading
  #   lands past the seam (02:00 -> 03:00); at a FOLD it lands back
  #   before it (02:00 -> 01:00). Either way THIS period cannot say
  #   whether the window covers that reading - the next period's own
  #   piece re-covers B exactly when it should (its lower edge starts
  #   at that reading, :closed). So this edge stays :open.
  # - No jump, and the boundary clipped the window (u is before the
  #   window's until): B reads as u, which is inside the window's
  #   interior, so the edge is :closed.
  # - No jump, and the window itself ends here (u is the window's
  #   until): B reads as u, so the user's closing is honest.
  @spec upper_closing(
          map(),
          integer() | nil,
          NaiveDateTime.t(),
          {NaiveDateTime.t(), Intervals.closing()}
        ) :: Intervals.closing()
  defp upper_closing(period, next_wall_start, u, {until, right}) do
    # Compare by instant, not by struct: a window until written with
    # microsecond precision still sits on the boundary.
    on_boundary? =
      period.until.wall != :max and
        NaiveDateTime.compare(gs_to_naive(period.until.wall), u) == :eq

    cond do
      not on_boundary? -> right
      next_wall_start != nil and next_wall_start != period.until.wall -> :open
      NaiveDateTime.compare(u, until) == :lt -> :closed
      true -> right
    end
  end

  # [claude-code] tzdata speaks gregorian seconds; :min/:max mark the
  # open ends of the first and last period and clip to nothing here.
  @spec gs_to_naive(integer() | :min | :max) :: NaiveDateTime.t() | nil
  defp gs_to_naive(:min), do: nil
  defp gs_to_naive(:max), do: nil

  defp gs_to_naive(gs) when is_integer(gs) do
    NaiveDateTime.from_erl!(:calendar.gregorian_seconds_to_datetime(gs))
  end

  @spec to_utc(NaiveDateTime.t(), integer()) :: DateTime.t()
  defp to_utc(naive, offset) do
    naive
    |> NaiveDateTime.add(-offset, :second)
    |> DateTime.from_naive!("Etc/UTC")
  end

  # [claude-code] The wall-clock date of a UTC instant in the target
  # timezone, used to pick which cycle instances the horizon touches.
  @spec wall_date(DateTime.t(), String.t()) :: Date.t()
  defp wall_date(%DateTime{} = at, tz) do
    case DateTime.shift_zone(at, tz, Tzdata.TimeZoneDatabase) do
      {:ok, local} ->
        DateTime.to_date(local)

      {:error, reason} ->
        raise ArgumentError, "cannot resolve timezone #{inspect(tz)}: #{inspect(reason)}"
    end
  end

  # ── Enumerable cells (decision D1, span half) ──────────────────────

  # [claude-code] Added (2026-08-05, decision D1). The symbolic cells
  # of ONE instance of an arc, in walking order. This list is what
  # the Enumerable implementation for Zocam.Span.Arc hands out (see
  # "Enumerate an arc" in the Arc moduledoc for the examples).
  #
  # The walk reuses ground/3's interpretation of "cell"; it does not
  # invent a second one:
  # - the wrap decision is nominal_order/2's rule: an until cell
  #   before the from cell resolves forward through the cycle seam,
  #   exactly as arc_windows/4 resolves it with the next container;
  # - whole-unit closings move the row's edges by whole cells, as the
  #   unstepped branch of arc_windows/4 moves the block edges;
  # - a step walks from the from cell; a landing exactly on the until
  #   cell is kept only when the right side is :closed, and an :open
  #   left drops the first sample without moving the phase - the
  #   rules of discrete_samples/7 and time_samples/5.
  #
  # The walk refuses, each with a lesson, every arc whose
  # one-instance cell row is NOT fixed: a continuous :time arc
  # without a step, a step whose unit is not the grain, a bound
  # without a fixed cell number (ordinals, negative day indices),
  # bounds that differ above the grain cell, and a wrap in a cycle
  # without a fixed length. ground/3 walks all of those on the real
  # calendar.
  @doc false
  @spec arc_cells!(Arc.t()) :: [term()]
  def arc_cells!(%Arc{} = arc) do
    {prefix_f, {unit_f, from_cell}} = split_last(arc.from)
    {prefix_u, {unit_u, until_cell}} = split_last(arc.until)

    if unit_f != unit_u do
      raise ArgumentError,
            "the bounds end in different units (#{inspect(unit_f)} and " <>
              "#{inspect(unit_u)}), so they name no common cell row. " <>
              "Walk the real thing with Zocam.Span.ground/3."
    end

    if unit_f == :time do
      time_cells!(arc, prefix_f, prefix_u, from_cell, until_cell)
    else
      discrete_cells!(arc, {prefix_f, prefix_u}, unit_f, from_cell, until_cell)
    end
  end

  @spec split_last(Point.chain()) :: {Point.chain() | [], {Point.unit(), term()}}
  defp split_last(chain) do
    {prefix, [last]} = Enum.split(chain, -1)
    {prefix, last}
  end

  # [claude-code] The :time row. Without a step the arc is
  # continuous - between any two instants sit infinitely many more -
  # so there is nothing honest to yield. With a step, the samples are
  # the cells: the window is resolved on a reference day exactly as
  # arc_windows/4 resolves it inside a real instance (a wrapping
  # until continues into the next day), and time_samples/5 does the
  # sampling, so Enum and ground/3 cannot disagree on the phase.
  @spec time_cells!(Arc.t(), Point.chain() | [], Point.chain() | [], Time.t(), Time.t()) ::
          [term()]
  defp time_cells!(arc, prefix_f, prefix_u, from_time, until_time) do
    case arc.step do
      # Continuity is the first lesson: it holds whatever the
      # prefixes are, so it must not hide behind the prefix check.
      nil ->
        raise ArgumentError,
              "a :time-grain arc without a step is continuous, so it has no " <>
                "cells to enumerate. Two ways out: give the arc a step (for " <>
                "example step: {15, :minute}), or ground the span with " <>
                "Zocam.Span.ground/3 and walk the concrete intervals."

      {n, unit} when unit in [:hour, :minute, :second] ->
        check_same_prefix!(arc, prefix_f, prefix_u)
        # Any date works as the reference: the samples only carry
        # their wall clock out.
        ref = ~D[2000-01-03]
        f = NaiveDateTime.new!(ref, from_time)
        u0 = NaiveDateTime.new!(ref, until_time)

        u =
          if NaiveDateTime.compare(u0, f) == :lt,
            do: NaiveDateTime.new!(Date.add(ref, 1), until_time),
            else: u0

        f
        |> time_samples(u, time_unit_seconds(unit) * n, arc.left, arc.right)
        |> Enum.map(fn {instant, _until, _l, _r} ->
          render_cell(prefix_f, :time, NaiveDateTime.to_time(instant))
        end)

      {_n, unit} ->
        raise ArgumentError,
              "at :time grain the step unit must be :hour, :minute or " <>
                ":second, got #{inspect(unit)}"
    end
  end

  # [claude-code] The discrete row: integer cell arithmetic over the
  # fixed cell numbering (months 1..12, weekdays 1..7, day and week
  # and year numbers as themselves), the same numbering the union
  # compaction uses via cell_number/2.
  @spec discrete_cells!(
          Arc.t(),
          {Point.chain() | [], Point.chain() | []},
          Point.unit(),
          term(),
          term()
        ) :: [term()]
  defp discrete_cells!(arc, {prefix_f, prefix_u}, unit, from_cell, until_cell) do
    grain = unit_class_of(unit)

    # The step check comes first, so the "31st, monthly" case gets
    # ITS lesson even when the bounds also differ above the grain.
    case arc.step do
      nil ->
        :ok

      {_n, step_unit} ->
        unless unit_class_of(step_unit) == grain do
          raise ArgumentError,
                "step #{inspect(arc.step)} does not walk this arc's " <>
                  "#{inspect(grain)} cells, so the samples are not inside one " <>
                  "instance: each landing resolves on the real calendar (the " <>
                  "\"31st, monthly\" case clamps or skips per month). Ground " <>
                  "the span with Zocam.Span.ground/3 to get the real dates."
        end
    end

    check_same_prefix!(arc, prefix_f, prefix_u)

    a = fixed_cell_number!(unit, from_cell)
    b = fixed_cell_number!(unit, until_cell)

    b =
      cond do
        b >= a ->
          b

        len = cycle_length(unit) ->
          # The wrap: resolve the until cell forward through the
          # seam, so Nov..Feb walks 11, 12, 13, 14 and renders the
          # numbers back into the cycle below.
          b + len

        true ->
          raise ArgumentError,
                "this arc wraps from #{inspect(from_cell)} back to " <>
                  "#{inspect(until_cell)}, and only :month and :weekday cells " <>
                  "sit in a cycle of fixed length (12 months, 7 weekdays). " <>
                  "#{inspect(unit)} cells do not, so one instance has no fixed " <>
                  "cell row. Ground the span with Zocam.Span.ground/3 instead."
      end

    numbers =
      case arc.step do
        nil ->
          # Whole-unit closings move the row edges by whole cells.
          first = if arc.left == :open, do: a + 1, else: a
          last = if arc.right == :open, do: b - 1, else: b
          if first > last, do: [], else: Enum.to_list(first..last)

        {n, _unit} ->
          a..b
          |> Enum.take_every(n)
          |> then(fn samples ->
            # A landing exactly on the until cell obeys the right
            # closing; earlier samples stay regardless.
            if arc.right == :open and List.last(samples) == b,
              do: Enum.drop(samples, -1),
              else: samples
          end)
          |> then(fn samples ->
            # An :open left drops the first sample; the phase stays
            # anchored on the from cell.
            if arc.left == :open, do: Enum.drop(samples, 1), else: samples
          end)
      end

    Enum.map(numbers, fn number ->
      wrapped =
        case cycle_length(unit) do
          nil -> number
          len -> Integer.mod(number - 1, len) + 1
        end

      render_cell(prefix_f, unit, cell_value(unit, wrapped))
    end)
  end

  # [claude-code] The simplest honest cell value: bare for a
  # single-segment bound, a chain in which only the grain cell varies
  # when the bounds carry a prefix (documented in the Arc moduledoc).
  @spec render_cell(Point.chain() | [], Point.unit(), term()) :: term()
  defp render_cell([], _unit, value), do: value
  defp render_cell(prefix, unit, value), do: prefix ++ [{unit, value}]

  @spec check_same_prefix!(Arc.t(), Point.chain() | [], Point.chain() | []) :: :ok
  defp check_same_prefix!(arc, prefix_f, prefix_u) do
    if prefix_f != prefix_u do
      raise ArgumentError,
            "the bounds differ above the grain cell (#{inspect(arc.from)} .. " <>
              "#{inspect(arc.until)}), so the cells between them cross a " <>
              "prefix boundary and resolve on the real calendar. Ground the " <>
              "span with Zocam.Span.ground/3 and walk the concrete intervals."
    end

    :ok
  end

  # [claude-code] The fixed cell number of one bound cell. :year
  # rides on its own: the year number IS the cell number, but
  # fixed_cell?/2 excludes it on purpose (the union compaction that
  # owns that helper never merges across the unbounded year axis).
  @spec fixed_cell_number!(Point.unit(), term()) :: integer()
  defp fixed_cell_number!(:year, value) when is_integer(value), do: value

  defp fixed_cell_number!(unit, value) do
    if fixed_cell?(unit, value) do
      cell_number(unit, value)
    else
      raise ArgumentError,
            "the bound cell #{inspect([{unit, value}])} has no fixed number " <>
              "inside one instance: an ordinal or a negative index resolves " <>
              "per instance (each month elects its own \"last Saturday\"). " <>
              "Ground the span with Zocam.Span.ground/3 and walk the real " <>
              "dates."
    end
  end

  # [claude-code] The cycle length behind a cell numbering, where one
  # exists. Only these two units wrap symbolically: a month row is
  # always 12 cells and a weekday row always 7, while day and week
  # rows change length per instance (28..31 days, 52 or 53 weeks) and
  # the year axis has no cycle at all.
  @spec cycle_length(Point.unit()) :: pos_integer() | nil
  defp cycle_length(:month), do: 12
  defp cycle_length(:weekday), do: 7
  defp cycle_length(_unit), do: nil

  # ── Validation and small helpers ───────────────────────────────────

  @spec to_wall(DateTime.t() | NaiveDateTime.t()) :: NaiveDateTime.t()
  defp to_wall(%DateTime{} = at), do: DateTime.to_naive(at)
  defp to_wall(%NaiveDateTime{} = at), do: at

  @spec naive(Date.t()) :: NaiveDateTime.t()
  defp naive(%Date{} = date), do: NaiveDateTime.new!(date, ~T[00:00:00])

  @spec fetch_point!(keyword(), :from | :until) :: Point.t()
  defp fetch_point!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, %Point{} = point} ->
        point

      {:ok, other} ->
        raise ArgumentError, "arc #{key}: must be a %Point{}, got #{inspect(other)}"

      :error ->
        raise ArgumentError,
              "arc!/1 needs both from: and until:. A cycle has no first or last " <>
                "unit to default to; unbounded sides belong to absolute!/1, where " <>
                "the timeline provides them."
    end
  end

  @spec fetch_closing!(keyword(), :left | :right, Intervals.closing()) :: Intervals.closing()
  defp fetch_closing!(opts, key, default) do
    case Keyword.get(opts, key, default) do
      closing when closing in [:open, :closed] ->
        closing

      other ->
        raise ArgumentError, "#{key}: must be :open or :closed, got #{inspect(other)}"
    end
  end

  # [claude-code] Step normalization: one canonical spelling per
  # meaning. A bare integer borrows the grain as its unit (illegal at
  # :time - Time.t has no unit cell); {1, grain} IS the unstepped
  # arc, so it becomes nil. The unit must be the grain itself, a
  # coarser unit already on the chain, or a sub-day unit at :time.
  @spec normalize_step!(term(), Point.grain_class(), Point.chain()) :: step() | nil
  defp normalize_step!(nil, _grain, _chain), do: nil

  defp normalize_step!(n, grain, chain) when is_integer(n) and n > 0 do
    if grain == :time do
      raise ArgumentError,
            "a bare integer step counts grain units, and :time has no unit " <>
              "cell. Give the unit explicitly: {#{n}, :minute}, {#{n}, :hour}, ..."
    end

    normalize_step!({n, grain}, grain, chain)
  end

  defp normalize_step!({n, unit}, grain, chain) when is_integer(n) and n > 0 do
    cond do
      grain == :time and unit in [:hour, :minute, :second] ->
        {n, unit}

      grain == :time ->
        raise ArgumentError,
              "at :time grain the step unit must be :hour, :minute or :second, " <>
                "got #{inspect(unit)}"

      unit_class_of(unit) == grain and n == 1 ->
        nil

      # The implemented sampling families, and nothing more: a step
      # that would crash discrete_samples/7 is rejected HERE, at
      # construction, with a teaching message.
      grain == :day and unit_class_of(unit) == :day ->
        {n, :day}

      unit == :month and (match?([month: _], chain) or match?([month: _, day: _], chain)) ->
        {n, :month}

      unit_class_of(unit) == grain or unit in Keyword.keys(chain) ->
        raise ArgumentError,
              "step {#{n}, #{inspect(unit)}} fits this arc's shape, but its " <>
                "sampling family is not implemented yet. Implemented: day-sized " <>
                "units over day-sized cells, and :month over [month] or " <>
                "[month, day] chains."

      true ->
        raise ArgumentError,
              "step unit #{inspect(unit)} is neither the arc's grain " <>
                "(#{inspect(grain)}) nor a coarser unit on its chain " <>
                "(#{inspect(Keyword.keys(chain))})"
    end
  end

  defp normalize_step!(other, _grain, _chain) do
    raise ArgumentError,
          "step: must be a positive integer or {n, unit}, got #{inspect(other)}"
  end

  @spec unit_class_of(Point.unit() | time_unit()) :: Point.grain_class() | :sub_day
  defp unit_class_of(:weekday), do: :day
  defp unit_class_of(unit) when unit in [:year, :month, :week, :day, :time], do: unit
  defp unit_class_of(unit) when unit in [:hour, :minute, :second], do: :sub_day

  # [claude-code] The nominal order of two chains: compare paired
  # segments cell by cell, before any clamping. This decides wrap
  # (day 30 .. day 29 wraps in EVERY month, even where both clamp to
  # the same date). Segments without a fixed cell number (ordinal
  # selectors, negative day indices) have no nominal order: :unknown,
  # and the caller falls back to resolved dates.
  @spec nominal_order(Point.chain(), Point.chain()) :: :lt | :eq | :gt | :unknown
  defp nominal_order([], []), do: :eq

  defp nominal_order([{unit, a} | rest_a], [{unit, b} | rest_b]) do
    case segment_order(unit, a, b) do
      :eq -> nominal_order(rest_a, rest_b)
      other -> other
    end
  end

  defp nominal_order(_a, _b), do: :unknown

  @spec segment_order(Point.unit(), term(), term()) :: :lt | :eq | :gt | :unknown
  defp segment_order(:time, %Time{} = a, %Time{} = b), do: Time.compare(a, b)

  defp segment_order(:year, a, b) when is_integer(a) and is_integer(b),
    do: integer_order(a, b)

  defp segment_order(unit, a, b) do
    if fixed_cell?(unit, a) and fixed_cell?(unit, b) do
      integer_order(cell_number(unit, a), cell_number(unit, b))
    else
      :unknown
    end
  end

  @spec integer_order(integer(), integer()) :: :lt | :eq | :gt
  defp integer_order(a, b) when a < b, do: :lt
  defp integer_order(a, b) when a > b, do: :gt
  defp integer_order(_a, _b), do: :eq

  @spec time_unit_seconds(time_unit()) :: pos_integer()
  defp time_unit_seconds(:hour), do: 3600
  defp time_unit_seconds(:minute), do: 60
  defp time_unit_seconds(:second), do: 1

  @spec backward_absolute?(Point.t(), Point.t()) :: boolean()
  defp backward_absolute?(from, until) do
    {:ok, {f, _}} = chain_window(from.chain, :absolute, from.overflow)
    {:ok, {u, _}} = chain_window(until.chain, :absolute, until.overflow)
    NaiveDateTime.compare(u, f) == :lt
  rescue
    # A skipping bound cannot be ordered; let the arc through and
    # denote nothing at evaluation time.
    _ -> false
  end

  # [claude-code] Changed (2026-08-05, Linear YUR-84 and YUR-88): the
  # closing rule and the order rule are the kernel's shared checks
  # now (Intervals.check_closings!/1 and Intervals.check_order!/1) -
  # lifted, not copied, so the two layers cannot drift apart. The
  # keyword path of absolute!/1 already runs them inside the kernel's
  # piece gate; running them here too closes the map path, which used
  # to bypass the gate and accept an inverted DateTime pair. Only the
  # endpoint-shape rule stays local, because this door is stricter
  # than the kernel: an absolute span meets the timeline as instants,
  # so a Time endpoint (legal in the kernel) is refused here.
  @spec check_absolute!(map()) :: t()
  defp check_absolute!(interval) do
    for {side, value} <- [from: interval.from, until: interval.until], value != nil do
      unless match?(%DateTime{}, value) do
        raise ArgumentError,
              "absolute!/1 #{side}: must be a DateTime or nil, got #{inspect(value)}. " <>
                "Wall values (Time, month atoms) belong to Point and arc!/1."
      end

      # [claude-code] Added 2026-08-05 (Linear YUR-57). The shape check
      # above lets any calendar through; ground/3 later reads the wall
      # numbers of this bound as ISO numbers.
      ISO.check!(value, "the absolute!/1 #{side} bound")
    end

    checked =
      %{from: interval.from, until: interval.until, left: interval.left, right: interval.right}
      |> Intervals.check_closings!()
      |> Intervals.check_order!()

    {:absolute, checked}
  end

  @spec check_horizon!(term()) :: horizon()
  defp check_horizon!(%{from: %DateTime{} = from, until: %DateTime{} = until} = horizon) do
    # [claude-code] Added 2026-08-05 (Linear YUR-57). eval/3 walks the
    # cycle instances between these two bounds by their wall-clock
    # dates, which it reads as ISO dates.
    ISO.check!(from, "the ground/3 horizon from bound")
    ISO.check!(until, "the ground/3 horizon until bound")
    horizon
  end

  defp check_horizon!(other) do
    raise ArgumentError,
          "ground/3 needs a horizon bounded on both sides (many spans are " <>
            "infinite, so an unbounded ground cannot terminate), got #{inspect(other)}"
  end

  # [claude-code] nth/3 counts day cells, so its inner span must be
  # cyclic day-grain everywhere. The walk rejects the two shapes that
  # have no day cells: absolute intervals and :time-grain leaves.
  @spec validate_nth_inner!(t()) :: :ok
  defp validate_nth_inner!({:arcs, _scope, grain, _arcs})
       when grain in [:day, :week, :month, :year],
       do: :ok

  defp validate_nth_inner!({:arcs, _scope, :time, _arcs}) do
    raise ArgumentError,
          "nth/3 counts day cells; a :time-grain span has none. Select the day " <>
            "first, then intersect with the time window."
  end

  defp validate_nth_inner!({:absolute, _}) do
    raise ArgumentError,
          "nth/3 counts day cells within a cycle; an absolute interval has no " <>
            "cycle. Clip with ground/3 or intersect instead."
  end

  defp validate_nth_inner!({:union, spans}), do: Enum.each(spans, &validate_nth_inner!/1)
  defp validate_nth_inner!({:intersection, spans}), do: Enum.each(spans, &validate_nth_inner!/1)
  defp validate_nth_inner!({:complement, span}), do: validate_nth_inner!(span)
  defp validate_nth_inner!({:nth, _n, _inner, _per} = span), do: raise_nested_nth!(span)

  @spec raise_nested_nth!(t()) :: no_return()
  defp raise_nested_nth!(_span) do
    raise ArgumentError, "nth/3 does not nest; select in one pass"
  end

  # ── Arc-node merging (union normalization) ─────────────────────────

  # [claude-code] Same-(scope, grain) arc nodes merge into one node,
  # and inside a node the plainly-mergeable arcs compact: single-
  # segment chains with fixed cell numbering (months, weekdays, weeks,
  # positive day numbers), no step, both closings :closed, same
  # overflow, no wrap. Cell compaction is integer math: [1..1] and
  # [2..2] touch, so Jan..Jan union Feb..Feb IS Jan..Feb - the "no
  # overlapping intervals" invariant within one cycle. Everything
  # else (wraps, steps, ordinals, open closings) rides along
  # unmerged; the form stays quasi-canonical, not minimal.
  @spec merge_arc_nodes([t()]) :: [t()]
  defp merge_arc_nodes(spans) do
    {arc_nodes, others} = Enum.split_with(spans, &match?({:arcs, _, _, _}, &1))

    merged =
      arc_nodes
      |> Enum.group_by(fn {:arcs, scope, grain, _} -> {scope, grain} end)
      |> Enum.map(fn {{scope, grain}, nodes} ->
        arcs = Enum.flat_map(nodes, fn {:arcs, _, _, list} -> list end)
        {:arcs, scope, grain, compact_arcs(arcs)}
      end)

    # Keep the caller's ordering stable: merged arc nodes first (they
    # sort by scope/grain), then the symbolic rest in given order.
    Enum.sort(merged) ++ others
  end

  @spec compact_arcs([Arc.t()]) :: [Arc.t()]
  defp compact_arcs(arcs) do
    {mergeable, rest} = Enum.split_with(arcs, &mergeable_arc?/1)

    ranges =
      mergeable
      |> Enum.map(fn arc ->
        {unit, a} = hd(arc.from)
        {_unit, b} = hd(arc.until)
        {unit, cell_number(unit, a), cell_number(unit, b), arc.overflow}
      end)
      |> Enum.sort_by(fn {_u, a, _b, _o} -> a end)
      |> Enum.reduce([], fn
        {u, a, b, o}, [{u, a2, b2, o} | acc] when a <= b2 + 1 ->
          [{u, a2, max(b, b2), o} | acc]

        range, acc ->
          [range | acc]
      end)
      |> Enum.reverse()
      |> Enum.map(fn {unit, a, b, overflow} ->
        %Arc{
          from: [{unit, cell_value(unit, a)}],
          until: [{unit, cell_value(unit, b)}],
          left: :closed,
          right: :closed,
          step: nil,
          overflow: overflow
        }
      end)

    ranges ++ rest
  end

  @spec mergeable_arc?(Arc.t()) :: boolean()
  defp mergeable_arc?(%Arc{} = arc) do
    with true <- arc.step == nil and arc.left == :closed and arc.right == :closed,
         [{unit, a}] <- arc.from,
         [{^unit, b}] <- arc.until,
         true <- fixed_cell?(unit, a) and fixed_cell?(unit, b) do
      # No wrap: wrapping arcs have no single integer range.
      cell_number(unit, a) <= cell_number(unit, b)
    else
      _ -> false
    end
  end

  @spec fixed_cell?(Point.unit(), term()) :: boolean()
  defp fixed_cell?(:month, m) when is_atom(m), do: true
  defp fixed_cell?(:weekday, wd) when is_atom(wd), do: true
  defp fixed_cell?(:week, w) when is_integer(w), do: true
  defp fixed_cell?(:day, d) when is_integer(d) and d > 0, do: true
  defp fixed_cell?(_unit, _value), do: false

  @spec cell_number(Point.unit(), term()) :: integer()
  defp cell_number(:month, m), do: Point.month_number(m)
  defp cell_number(:weekday, wd), do: Point.weekday_number(wd)
  defp cell_number(_unit, n) when is_integer(n), do: n

  @spec cell_value(Point.unit(), integer()) :: term()
  defp cell_value(:month, n), do: Point.month_atom(n)
  defp cell_value(:weekday, n), do: Point.weekday_atom(n)
  defp cell_value(_unit, n), do: n
end

# [claude-code] Added (2026-08-05, decision D1, span half): one
# instance of an arc is a row of grain cells, and Enum walks that
# row. The list itself comes from Zocam.Span.arc_cells!/1, which
# reuses ground/3's interpretation of "cell" - see "Enumerate an arc"
# in the Arc moduledoc for the examples and the refusals. count/1 is
# the row's length. member?/2 and slice/1 fall back to the
# reduce-based walk: a cell row is short, and the fallback keeps the
# taught errors (a continuous :time arc, a cross-instance step) in
# exactly one place. Note the same pitfall as on Zocam.Intervals:
# Enum.member?/2 asks "is this value one of the cells?", not "is this
# instant covered?" - coverage questions belong to Zocam.Span.member?/2.
defimpl Enumerable, for: Zocam.Span.Arc do
  @impl true
  def count(arc), do: {:ok, length(Zocam.Span.arc_cells!(arc))}

  @impl true
  def member?(_arc, _value), do: {:error, __MODULE__}

  @impl true
  def slice(_arc), do: {:error, __MODULE__}

  @impl true
  def reduce(arc, acc, fun), do: Enumerable.List.reduce(Zocam.Span.arc_cells!(arc), acc, fun)
end
