defmodule Cite.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mdepolli/cite"

  def project do
    [
      app: :cite,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      test_elixirc_options: [debug_info: true],
      deps: deps(),
      name: "Cite",
      description: description(),
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    []
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:req, "~> 0.6"},
      {:spark, "~> 2.7"},
      {:sourceror, "~> 1.2", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    Citations copied from the source, never written by a model. Your code lists
    the candidates, a decision model judges which ones hold up, and Cite returns
    those exact bytes.
    """
  end

  defp package do
    [
      files: ~w(
        lib/cite
        lib/cite.ex
        .formatter.exs
        mix.exs
        README.md
        LICENSE
        CHANGELOG.md
      ),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Marcelo De Polli"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "guides/select-and-judge.md",
        "guides/writing-questions.md",
        "CHANGELOG.md"
      ],
      # Groups mirror the stability tiers (see README "Stability"): Core API
      # is the SemVer contract; Providers is implementable but best-effort;
      # Internal carries no guarantees — published because it explains how
      # the library works.
      groups_for_modules: [
        "Core API": [
          Cite,
          Cite.Candidate,
          Cite.Question,
          Cite.Cluster,
          Cite.Result,
          Cite.Span,
          Cite.Error
        ],
        Providers: [Cite.Provider, Cite.Provider.TypeSafe],
        Internal: [
          Cite.Select,
          Cite.Scan,
          Cite.Compare,
          Cite.Emit,
          Cite.Wire,
          Cite.Wire.Object,
          Cite.Answer
        ]
      ],
      # Renders ```mermaid``` fences in extras (README + guides) on HexDocs.
      # GitHub renders them natively; ExDoc needs the CDN + init hook.
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  # Copied verbatim from ex_doc's README (0.40.x), mermaid pin included.
  # To upgrade, adopt the recipe of whatever ExDoc version we're on —
  # don't bump mermaid independently.
  defp before_closing_body_tag(:html) do
    """
    <script defer src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
    <script>
      let initialized = false;

      window.addEventListener("exdoc:loaded", () => {
        if (!initialized) {
          mermaid.initialize({
            startOnLoad: false,
            theme: document.body.className.includes("dark") ? "dark" : "default"
          });
          initialized = true;
        }

        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphDefinition = codeEl.textContent;
          const graphEl = document.createElement("div");
          const graphId = "mermaid-graph-" + id++;
          mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
            graphEl.innerHTML = svg;
            bindFunctions?.(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  defp before_closing_body_tag(_), do: ""
end
