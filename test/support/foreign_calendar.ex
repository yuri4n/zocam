# [claude-code] A test-only calendar that is not `Calendar.ISO`.
# Written 2026-08-05 for the ISO checks (Linear YUR-57). This module is
# a black box: read the comment, do not read the delegations.
#
# It delegates every callback to `Calendar.ISO`, so a `%Date{}` or a
# `%Time{}` that carries it holds the same numbers that ISO holds. That
# is the point of the fixture, and it makes the tests sharp:
#
#   `Zocam.ISO` refuses this calendar even though it agrees with ISO
#   number for number, because the check is *identity* of the module.
#
# Identity is the honest check. A calendar can be "compatible" with ISO
# in the stdlib sense (`Calendar.compatible_calendars?/2`, same day and
# time structure) and still number the years, the months, or the
# weekdays differently — the Holocene calendar in Elixir's own test
# suite shifts every year by 10000. zocam reads those numbers as ISO
# numbers, so nothing weaker than identity is safe. The price is this
# fixture: a calendar that would have been safe is refused too. Nothing
# in the tree constructs one, so the price is zero.
#
# The list of callbacks is deliberately partial: only the ones the test
# suite can reach. There is no `@behaviour Calendar`, because that would
# demand all 27 of them for no gain in a fixture.
defmodule Zocam.ForeignCalendar do
  @moduledoc false

  defdelegate valid_date?(year, month, day), to: Calendar.ISO
  defdelegate valid_time?(hour, minute, second, microsecond), to: Calendar.ISO
  defdelegate day_of_week(year, month, day, starting_on), to: Calendar.ISO
  defdelegate days_in_month(year, month), to: Calendar.ISO
  defdelegate date_to_string(year, month, day), to: Calendar.ISO
  defdelegate time_to_string(hour, minute, second, microsecond), to: Calendar.ISO

  defdelegate naive_datetime_to_string(
                year,
                month,
                day,
                hour,
                minute,
                second,
                microsecond
              ),
              to: Calendar.ISO

  defdelegate datetime_to_string(
                year,
                month,
                day,
                hour,
                minute,
                second,
                microsecond,
                time_zone,
                zone_abbr,
                utc_offset,
                std_offset
              ),
              to: Calendar.ISO
end
