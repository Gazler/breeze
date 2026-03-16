defmodule Breeze.MixProject do
  use Mix.Project

  @version "0.2.1"

  def project do
    [
      app: :breeze,
      version: @version,
      description: "LiveView inspired TUI library for writing terminal applications",
      package: package(),
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Breeze",
      source_url: "https://github.com/Gazler/breeze",
      docs: [
        source_ref: "v#{@version}"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package() do
    [
      files: ~w(lib .formatter.exs mix.exs README.md LICENCE.md),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/Gazler/breeze"}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:termite, github: "Gazler/termite", override: true},
      {:back_breeze, github: "Gazler/back_breeze", branch: "feat/profiling"},
      {:telemetry, "~> 1.0"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
