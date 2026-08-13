defmodule Breeze.MixProject do
  use Mix.Project

  @version "0.6.0"

  def project do
    [
      app: :breeze,
      version: @version,
      description: "LiveView inspired TUI library for writing terminal applications",
      package: package(),
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "Breeze",
      source_url: "https://github.com/Gazler/breeze",
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

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
      {:termite, "~> 0.4 or ~> 0.5"},
      {:back_breeze, "~> 0.4.2"},
      {:file_system, "~> 1.1", optional: true, runtime: Mix.env() == :dev},
      {:telemetry, "~> 1.0"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:makeup_eex, "~> 2.0", only: :dev, runtime: false},
      {:makeup_html, "~> 0.2.0", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      docs: [&generate_docs/1]
    ]
  end

  defp docs do
    [
      main: "readme",
      assets: %{"doc_src/assets" => "assets"},
      extras: [
        "README.md",
        "CHANGELOG.md",
        "doc_src/guides/simple_app.md",
        "doc_src/guides/debugging.md",
        "doc_src/guides/persistent_multi_instance.md",
        "doc_src/guides/ssh.md",
        "doc_src/guides/fly_io.md",
        "doc_src/generated/blocks.md"
      ],
      source_ref: "v#{@version}",
      before_closing_head_tag: &before_closing_head_tag/1,
      before_closing_body_tag: &before_closing_body_tag/1,
      groups_for_modules: [
        "Applications and views": [
          Breeze.Server,
          Breeze.View,
          Breeze.Term
        ],
        "Components and styling": [
          Breeze.Component,
          Breeze.Blocks,
          Breeze.Implicit,
          Breeze.Theme,
          Breeze.Viewport
        ],
        "Development tools": [
          Breeze.IO,
          Breeze.Inspector,
          Breeze.RemoteInspector.Page,
          Breeze.Runtime,
          Breeze.Runtime.Context,
          Breeze.Runtime.Hook,
          Breeze.Runtime.State,
          Breeze.Server.Diagnostics,
          Breeze.Logger,
          Breeze.Logger.Collector,
          Breeze.Test
        ],
        Storybook: [
          Breeze.Storybook.Story,
          Breeze.Storybook
        ],
        Tooling: [Breeze.HTMLFormatter]
      ],
      groups_for_extras: [
        "Release notes": ["CHANGELOG.md"],
        Guides: [
          "README.md",
          "doc_src/guides/simple_app.md",
          "doc_src/guides/debugging.md",
          "doc_src/guides/persistent_multi_instance.md",
          "doc_src/guides/ssh.md",
          "doc_src/guides/fly_io.md"
        ],
        Components: ["doc_src/generated/blocks.md"]
      ]
    ]
  end

  defp before_closing_head_tag(:html) do
    Breeze.Docs.Assets.head_html()
  end

  defp before_closing_head_tag(_), do: ""

  defp before_closing_body_tag(:html) do
    Breeze.Docs.Assets.body_html()
  end

  defp before_closing_body_tag(_), do: ""

  defp generate_docs(args) do
    Mix.Task.run("compile")
    register_heex_highlighter()

    assets_path = Path.expand("doc_support/docs_assets.ex", __DIR__)
    generator_path = Path.expand("doc_support/block_previews.ex", __DIR__)
    Code.require_file(assets_path)
    Code.require_file(generator_path)

    generator = Module.concat([Breeze, Docs, BlockPreviews])
    apply(generator, :write_markdown!, [])

    Mix.shell().info("Generated #{Path.relative_to_cwd(apply(generator, :output_path, []))}")

    Mix.Tasks.Docs.run(args, Mix.Project.config(), &ExDoc.generate/4)
  end

  defp register_heex_highlighter do
    Application.ensure_all_started(:makeup_html)
    Application.ensure_all_started(:makeup_eex)
    Makeup.Lexers.ElixirLexer.register_sigil_lexer("H", Makeup.Lexers.HEExLexer)
  end
end
