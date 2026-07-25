Application.put_env(:breeze, :example_mode, :load_only)
Application.put_env(:breeze, :example_user_host, "gazler@gazler-arch")

example_files =
  Enum.map(
    ~w(animated_progress.exs counter.exs docs.exs modal.exs posting.exs responsive.exs snake.exs tabs.exs),
    &Path.expand("../examples/#{&1}", __DIR__)
  )

story_files =
  Path.expand("../storybook/*.story.exs", __DIR__)
  |> Path.wildcard()

{:ok, _modules, _warnings} =
  Kernel.ParallelCompiler.require(example_files ++ story_files, return_diagnostics: true)

Breeze.Storybook.Registry.stories("storybook")
ExUnit.start()
