defmodule Mix.Tasks.BreezeStorybookTaskTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Breeze.Storybook

  test "resolves the host project's storybook and builds server options" do
    cwd = tmp_directory("options")
    storybook = Path.join(cwd, "storybook")
    File.mkdir_p!(storybook)
    File.write!(Path.join(storybook, "metric.story.exs"), "defmodule MetricStory do\nend\n")
    on_exit(fn -> File.rm_rf!(cwd) end)

    assert {:ok, options} =
             Storybook.parse_options(
               ["--theme", "nord", "--no-reload", "--no-inspector"],
               cwd
             )

    assert options.directory == storybook
    assert options.file == nil
    refute options.reload
    refute options.inspector

    assert [
             view: Breeze.Storybook,
             start_opts: [directory: ^storybook],
             theme: %Breeze.Theme{name: "nord"},
             mouse: true,
             hide_cursor: true,
             reload: false,
             inspector: false,
             logger: _logger,
             render_errors: _render_errors
           ] = Storybook.run_opts(options)
  end

  test "accepts a single story file relative to the storybook directory" do
    cwd = tmp_directory("file")
    storybook = Path.join(cwd, "stories")
    story = Path.join(storybook, "button.story.exs")
    File.mkdir_p!(storybook)
    File.write!(story, "defmodule ButtonStory do\nend\n")
    on_exit(fn -> File.rm_rf!(cwd) end)

    assert {:ok, options} =
             Storybook.parse_options(
               ["--directory", "stories", "--file", "button.story.exs"],
               cwd
             )

    assert options.directory == storybook
    assert options.file == story
    assert Storybook.run_opts(options)[:start_opts] == [directory: storybook, file: story]
  end

  test "reports missing and empty storybook directories" do
    cwd = tmp_directory("missing")
    on_exit(fn -> File.rm_rf!(cwd) end)

    assert {:error, message} = Storybook.parse_options([], cwd)
    assert message == "storybook directory does not exist: #{Path.join(cwd, "storybook")}"

    File.mkdir_p!(Path.join(cwd, "storybook"))

    assert {:error, message} = Storybook.parse_options([], cwd)
    assert message =~ "contains no *.story.exs files"
  end

  test "reports invalid options, themes, and extra positional files" do
    cwd = tmp_directory("invalid")
    storybook = Path.join(cwd, "storybook")
    File.mkdir_p!(storybook)
    File.write!(Path.join(storybook, "valid.story.exs"), "defmodule ValidStory do\nend\n")
    on_exit(fn -> File.rm_rf!(cwd) end)

    assert {:error, message} = Storybook.parse_options(["--wat"], cwd)
    assert message =~ "unknown or invalid option"

    assert {:error, message} = Storybook.parse_options(["--theme", "nope"], cwd)
    assert message =~ "unknown Storybook theme"

    assert {:error, "expected at most one story file"} =
             Storybook.parse_options(["one.story.exs", "two.story.exs"], cwd)
  end

  defp tmp_directory(name) do
    Path.join(
      System.tmp_dir!(),
      "breeze_storybook_task_#{name}_#{System.unique_integer([:positive])}"
    )
  end
end
