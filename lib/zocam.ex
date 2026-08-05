# [claude-code] Library overview module: the ExDoc landing page and
# the place that names the layer architecture. It holds no logic on
# purpose - each layer is complete on its own.
defmodule Zocam do
  @moduledoc """
  A three-layer library for time: calendar things, sets of them, and
  concrete intervals.

  ## The layers

      Zocam.Point ──▶ Zocam.Span ──▶ Zocam.Intervals
      (calendar        (sets: arcs,     (linear kernel:
       things:          unions,          concrete interval
       "May",           steps,           sets on the real
       "the 23rd",      nth, ...)        timeline)
       "15:00")

  - `Zocam.Point` models one "thing about time": concrete
    (`"May 2026"`) or abstract (`"May"`). Points compose:
    `"Jan"` + `"the 23rd"` = `"Jan 23, yearly"`.
  - `Zocam.Span` models *sets* of instants built from points: arcs
    with closings and steps (`"Fri..Mon"`, `"every 15 minutes"`),
    unions, intersections, complements, and ordinal selection
    (`"last working day of the month"`). Its two interpreters are
    `Zocam.Span.member?/2` and `Zocam.Span.ground/3`.
  - `Zocam.Intervals` is the linear kernel: concrete interval sets
    with union, intersection, complement, and difference. Everything
    a span grounds to lands here.

  The calendar meets the real timeline in exactly one place:
  `Zocam.Span.ground/3` resolves wall times in a timezone, which is
  where DST folds (a wall hour that exists twice) and gaps (a wall
  hour that never exists) are handled.

  The design records live in the ADR pages shipped with this
  documentation (ADR-001 to ADR-006).
  """
end
