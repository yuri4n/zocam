# [claude-code] Standalone mix project for the zocam time library,
# extracted from the s7r app on 2026-08-04. The app consumes it from
# Hex ({:zocam, "~> 0.1"}), or from disk when ZOCAM_PATH is set.
defmodule Zocam.MixProject do
  use Mix.Project

  # agent: claude — the version has one source of truth: this attribute.
  # The release workflow refuses a git tag that does not match it.
  # [cursor-agent] 0.1.0 → 0.2.0 on 2026-08-06: the one-value-set
  # decision (ADR-007) changed the kernel's answers, a breaking
  # change, and the door guards (YUR-81/84/85/86/87/88) now reject
  # input that 0.1.0 accepted.
  @version "0.2.0"

  def project do
    [
      app: :zocam,
      version: @version,
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
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
      # agent: claude — ExDoc settings. `mix docs` builds the API reference
      # only. The design records (ADRs) are NOT extras: they live as website
      # sources in docs/content/2.design/adrs/ and carry frontmatter plus MDC
      # syntax, which ExDoc would print as raw text on hexdocs. Read them at
      # https://zocam.dev/design/adrs.
      name: "Zocam",
      docs: [
        main: "Zocam",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # agent: claude — added 2026-08-05 (Linear YUR-57). test/support holds
  # fixtures that must be real compiled modules, not code inside one test
  # file: Zocam.ForeignCalendar is used by two test files, and a module
  # defined twice at the top level warns. Only the test environment
  # compiles the directory, and `mix hex.publish` ships lib/ and priv/
  # only, so the fixture never reaches the package.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:timex, "~> 3.7"},
      # tzdata also arrives through timex; the explicit entry is here
      # because Zocam.Span reads the period table directly.
      #
      # [claude-code] `mix hex.audit` reports four advisories against
      # hackney 1.25.0, which arrives only through tzdata (tzdata caps
      # it at ~> 1.17 while upstream hackney is at 4.x, so no version
      # bump can clear them). Reachability, checked 2026-08-05: the
      # only code in the tree that calls hackney is
      # Tzdata.HTTPClient.Hackney, and it fetches ONE hard-coded URL,
      # https://data.iana.org/time-zones/tzdata-latest.tar.gz. All four
      # advisories need an attacker to influence the request (CRLF in a
      # query parameter or a cookie option, an SSRF allowlist bypass
      # via a percent-encoded host, a SOCKS5 proxy timeout). No input
      # of this library reaches that URL, those options, or a proxy, so
      # none of the four is reachable here.
      #
      # Two ways to remove the dependency instead of reasoning about
      # it, both tracked in Linear, neither free: swap tzdata's
      # pluggable :http_client for an :httpc-based one (leaves hackney
      # in the tree, so the audit still reports it), or drop
      # timex/tzdata for the dependency-free `tz` package (Zocam.Span
      # calls Tzdata.periods_for_time/3 directly, so this rewrites the
      # DST core).
      {:tzdata, "~> 1.1"},
      {:typed_struct, "~> 0.3"},
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false},
      # [cursor-agent] Added 2026-08-06 (Linear YUR-83): the property
      # test for the member?/ground law generates its inputs with
      # StreamData. Test-only, so the runtime dependency list of the
      # published library stays clean.
      {:stream_data, "~> 1.1", only: :test}
    ]
  end
end
