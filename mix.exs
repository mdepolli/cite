defmodule Cite.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/mdepolli/cite"

  def project do
    [
      app: :cite,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      test_elixirc_options: [debug_info: true],
      test_coverage: [ignore_modules: [~r/^Cite\.Policy\.Dsl\.Policy(\.|$)/, ~r/^Cite\.Test/]],
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
      {:req, "~> 0.7"},
      {:spark, "~> 2.7"},
      {:sourceror, "~> 1.2", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Finds what you describe in a document, such as failures in a log or hallucinations in a RAG answer. Every finding is grounded in the exact passages it cites. Judges with a decision model, not a generative LLM."
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
        assets/logo.svg
      ),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => "https://hexdocs.pm/cite",
        "Changelog" => "https://hexdocs.pm/cite/changelog.html"
      },
      maintainers: ["Marcelo De Polli"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      logo: "assets/logo.svg",
      favicon: "assets/logo.svg",
      # Copied as is, so the README's relative path to the logo resolves on
      # HexDocs as it does on GitHub.
      assets: %{"assets" => "assets"},
      extras: [
        "README.md",
        "guides/writing-policies.md",
        "guides/how-judging-works.md",
        "guides/tutorials/checking-rag-answers.md",
        "guides/tutorials/filtering-rag-results.md",
        "guides/tutorials/triaging-logs.md",
        "guides/tutorials/checking-support-calls.md",
        "guides/tutorials/finding-sponsor-segments.md",
        "guides/tutorials/labelling-allergens.md",
        "CHANGELOG.md"
      ],
      # The language and the rounds first; then tutorials, each building a
      # policy from scratch for one kind of data.
      groups_for_extras: [
        Guides: ["guides/writing-policies.md", "guides/how-judging-works.md"],
        Tutorials: ~r"guides/tutorials/"
      ],
      # Groups mirror the stability tiers (see README "Stability"): Core API
      # is the SemVer contract; Providers is implementable but best-effort;
      # Internal carries no guarantees — published because it explains how
      # the library works.
      groups_for_modules: [
        "Core API": [
          Cite,
          Cite.Policy,
          Cite.Source,
          Cite.Passage,
          Cite.Report,
          Cite.Finding,
          Cite.Citation,
          Cite.Error
        ],
        Providers: [Cite.Provider, Cite.Provider.TypeSafe, Cite.Wire.Object],
        Internal: [
          Cite.Run,
          Cite.Round,
          Cite.Screen,
          Cite.Gather,
          Cite.Gathered,
          Cite.Judge,
          Cite.Placeholder,
          Cite.Wire,
          Cite.Answer,
          Cite.Policy.Dsl,
          Cite.Policy.Checks,
          Cite.Policy.Build,
          Cite.Policy.Terms,
          Cite.Policy.Question,
          Cite.Policy.Concern,
          Cite.Policy.Role,
          Cite.Policy.Check
        ]
      ],
      # Renders ```mermaid``` fences in extras (README + guides) on HexDocs.
      # GitHub renders them natively; ExDoc needs the CDN + init hook.
      before_closing_head_tag: &before_closing_head_tag/1,
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  # Spark marks a required option in the `Cite.Policy` DSL reference with
  # this class alone; the rule is the one its cheat sheets carry.
  defp before_closing_head_tag(:html) do
    ~s(<style>.spark-required::after { content: "*"; color: red !important; }</style>)
  end

  defp before_closing_head_tag(_), do: ""

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
