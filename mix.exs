defmodule Breeze.MixProject do
  use Mix.Project

  def project do
    [
      app: :breeze,
      version: "0.1.0",
      description: "Library for writing terminal applications",
      package: package(),
      elixir: "~> 1.17-rc",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      links: %{}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nimble_parsec, "~> 1.4"},
      {:back_breeze, git: "git@github.com:gazler/back_breeze.git"},
      {:phoenix_live_view, "~> 1.0.0-rc.3"}
    ]
  end
end
