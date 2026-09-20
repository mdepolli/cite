defmodule Cite.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mdepolli/cite"

  def project do
    [
      app: :cite,
      version: @version,
      elixir: ">= 1.20.0",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      name: "Cite",
      description: description(),
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    Candidates in, grounded citations out. Uses Arbiter (System One) to judge;
    Cite windows, selects, and copies evidence byte-exact.
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
        "CHANGELOG.md"
      ]
    ]
  end
end
