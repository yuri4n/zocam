# [claude-code] Standalone mix project for the zocam time library,
# extracted from the s7r app on 2026-08-04. The app consumes it
# as a path dependency ({:zocam, path: "zocam"}).
defmodule Zocam.MixProject do
  use Mix.Project

  def project do
    [
      app: :zocam,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # ExDoc settings: `mix docs` builds the library reference with
      # the ADRs as extra pages.
      name: "Zocam",
      docs: [
        main: "Zocam",
        extras: [
          "README.md",
          "docs/adr-001-refinement-chain.md",
          "docs/adr-002-set-primary-spans.md",
          "docs/adr-003-overflow-policy.md",
          "docs/adr-004-fortnight-scopes.md",
          "docs/adr-005-shared-denotation.md",
          "docs/adr-006-library-extraction.md"
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:timex, "~> 3.7"},
      # tzdata also arrives through timex; the explicit entry is here
      # because Zocam.Span reads the period table directly.
      {:tzdata, "~> 1.1"},
      {:typed_struct, "~> 0.3"},
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false}
    ]
  end
end
