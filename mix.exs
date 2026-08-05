# [claude-code] Standalone mix project for the zocam time library,
# extracted from the s7r app on 2026-08-04. The app consumes it from
# Hex ({:zocam, "~> 0.1"}), or from disk when ZOCAM_PATH is set.
defmodule Zocam.MixProject do
  use Mix.Project

  # agent: claude — the version has one source of truth: this attribute.
  # The release workflow refuses a git tag that does not match it.
  @version "0.1.0"

  def project do
    [
      app: :zocam,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # agent: claude — Hex package metadata. `mix hex.publish` reads
      # these fields; Hex shows them on the package page.
      description: "A time library: points, spans, and interval algebra.",
      package: [
        licenses: ["MIT"],
        links: %{
          "GitHub" => "https://github.com/yuri4n/zocam",
          "Website" => "https://zocam.dev"
        }
      ],
      # agent: claude — ExDoc uses these URLs for the "view source" links
      # and for the header of the generated docs.
      source_url: "https://github.com/yuri4n/zocam",
      homepage_url: "https://zocam.dev",
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
