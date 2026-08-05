# [claude-code] Added (2026-08-05): runs the doctests in the Zocam
# landing moduledoc ("The four names" section). The doctests ARE the
# tests here - the moduledoc states the semantics, and this file
# makes the suite prove them.
defmodule ZocamTest do
  use ExUnit.Case, async: true
  doctest Zocam
end
