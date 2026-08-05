# [claude-code] Tests for the one calendar assumption (Linear YUR-57,
# 2026-08-05). Written before Zocam.ISO existed.
defmodule Zocam.ISOTest do
  use ExUnit.Case, async: true

  doctest Zocam.ISO

  alias Zocam.ForeignCalendar
  alias Zocam.ISO

  # [claude-code] The four stdlib values that carry a `:calendar`
  # field, each moved onto a calendar that is not `Calendar.ISO`. The
  # update syntax keeps every other field, so the only difference from
  # the sigil above it is the calendar itself.
  @date %{~D[2026-05-15] | calendar: ForeignCalendar}
  @time %{~T[09:00:00] | calendar: ForeignCalendar}
  @naive %{~N[2026-05-15 09:00:00] | calendar: ForeignCalendar}
  @datetime %{~U[2026-05-15 09:00:00Z] | calendar: ForeignCalendar}

  describe "check!/2" do
    test "an ISO value passes and answers :ok" do
      assert ISO.check!(~D[2026-05-15], "the anchor") == :ok
      assert ISO.check!(~T[09:00:00], "the :time segment") == :ok
      assert ISO.check!(~N[2026-05-15 09:00:00], "the bound") == :ok
      assert ISO.check!(~U[2026-05-15 09:00:00Z], "the horizon") == :ok
    end

    test "any other calendar raises, even one that agrees with ISO" do
      # ForeignCalendar delegates to Calendar.ISO, so this value holds
      # exactly the ISO numbers. It is still refused: the check is
      # identity of the module, because no cheaper test can tell a
      # calendar that agrees from one that only looks similar.
      assert_raise ArgumentError, fn -> ISO.check!(@date, "the anchor") end
      assert_raise ArgumentError, fn -> ISO.check!(@time, "the :time segment") end
      assert_raise ArgumentError, fn -> ISO.check!(@naive, "the bound") end
      assert_raise ArgumentError, fn -> ISO.check!(@datetime, "the horizon") end
    end

    test "the message names the place, the calendar, and the repair" do
      error = assert_raise ArgumentError, fn -> ISO.check!(@date, "the every/3 anchor") end

      assert error.message =~ "the every/3 anchor"
      assert error.message =~ "Zocam.ForeignCalendar"
      assert error.message =~ "Date.convert!"
    end

    test "the repair names the converter of the value's own type" do
      for {value, converter} <- [
            {@date, "Date.convert!"},
            {@time, "Time.convert!"},
            {@naive, "NaiveDateTime.convert!"},
            {@datetime, "DateTime.convert!"}
          ] do
        assert_raise ArgumentError, ~r/#{Regex.escape(converter)}/, fn ->
          ISO.check!(value, "the bound")
        end
      end
    end
  end
end
