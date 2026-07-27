defmodule Mix.Tasks.Breeze.Storybook do
  @moduledoc """
  Starts the Breeze Storybook for the current project.

  Story files are loaded from the `storybook` directory by default:

      mix breeze.storybook

  A different directory or a single story file can be selected with options:

      mix breeze.storybook --directory ui/stories
      mix breeze.storybook --file button.story.exs

  The task inherits `:reload`, `:inspector`, `:logger`, `:render_errors`, and
  `:storybook_theme` from the current project's application configuration.
  Command-line theme, reload, and inspector options take precedence.
  """

  use Mix.Task

  @shortdoc "Starts the Breeze Storybook"
  @switches [
    directory: :string,
    file: :string,
    theme: :string,
    reload: :boolean,
    inspector: :boolean
  ]
  @aliases [d: :directory, f: :file]

  @impl true
  def run(args) do
    Mix.Task.run("compile")

    options =
      case parse_options(args) do
        {:ok, options} -> options
        {:error, message} -> Mix.raise(message)
      end

    {:ok, _started} = Application.ensure_all_started(:breeze)

    Mix.shell().info("Starting Breeze Storybook from #{options.directory}")

    case Breeze.Server.run(run_opts(options)) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("Breeze Storybook failed to start: #{inspect(reason)}")
    end
  end

  @doc false
  def parse_options(args, cwd \\ File.cwd!()) do
    case OptionParser.parse(args, strict: @switches, aliases: @aliases) do
      {options, positional, []} -> normalize_options(options, positional, cwd)
      {_options, _positional, invalid} -> {:error, invalid_options(invalid)}
    end
  end

  @doc false
  def run_opts(options) do
    start_opts =
      [directory: options.directory]
      |> maybe_put(:file, options.file)

    [
      view: Breeze.Storybook,
      start_opts: start_opts,
      theme: resolve_theme(options.theme),
      mouse: true,
      hide_cursor: true,
      reload: options.reload,
      inspector: options.inspector,
      logger: options.logger,
      render_errors: options.render_errors
    ]
  end

  defp normalize_options(options, positional, cwd) do
    with {:ok, positional_file} <- positional_file(positional),
         directory <- options |> Keyword.get(:directory, "storybook") |> Path.expand(cwd),
         file_option <- Keyword.get(options, :file, positional_file),
         {:ok, file} <- story_file(file_option, directory, cwd),
         :ok <- validate_story_source(directory, file),
         {:ok, theme} <-
           normalize_theme(
             Keyword.get(options, :theme, project_setting(:storybook_theme, :system))
           ) do
      {:ok,
       %{
         directory: directory,
         file: file,
         theme: theme,
         reload: Keyword.get(options, :reload, project_setting(:reload, watcher_available?())),
         inspector: Keyword.get(options, :inspector, project_setting(:inspector, true)),
         logger: project_setting(:logger, :replace),
         render_errors: project_setting(:render_errors, view: Breeze.ErrorView)
       }}
    end
  end

  defp positional_file([]), do: {:ok, nil}
  defp positional_file([file]), do: {:ok, file}
  defp positional_file(_files), do: {:error, "expected at most one story file"}

  defp story_file(nil, _directory, _cwd), do: {:ok, nil}

  defp story_file(file, directory, cwd) do
    from_directory = Path.expand(file, directory)
    from_cwd = Path.expand(file, cwd)

    cond do
      Path.type(file) == :absolute -> {:ok, file}
      File.regular?(from_directory) -> {:ok, from_directory}
      true -> {:ok, from_cwd}
    end
  end

  defp validate_story_source(_directory, file) when is_binary(file) do
    if File.regular?(file) do
      :ok
    else
      {:error, "story file does not exist: #{file}"}
    end
  end

  defp validate_story_source(directory, nil) do
    cond do
      not File.dir?(directory) ->
        {:error, "storybook directory does not exist: #{directory}"}

      Path.wildcard(Path.join(directory, "*.story.exs")) == [] ->
        {:error, "storybook directory contains no *.story.exs files: #{directory}"}

      true ->
        :ok
    end
  end

  defp normalize_theme(theme) when theme in [:system, :system16], do: {:ok, theme}
  defp normalize_theme(%Breeze.Theme{} = theme), do: {:ok, theme}

  defp normalize_theme(theme) when is_atom(theme) do
    if theme in Breeze.Theme.default_cycle() do
      {:ok, theme}
    else
      {:error, unknown_theme(theme)}
    end
  end

  defp normalize_theme(theme) when is_binary(theme) do
    case Enum.find(Breeze.Theme.default_cycle(), &(Atom.to_string(&1) == theme)) do
      nil -> {:error, unknown_theme(theme)}
      name -> {:ok, name}
    end
  end

  defp normalize_theme(theme), do: {:error, unknown_theme(theme)}

  defp resolve_theme(theme) when theme in [:system, :system16], do: theme
  defp resolve_theme(%Breeze.Theme{} = theme), do: theme
  defp resolve_theme(theme), do: Breeze.Theme.builtin(theme)

  defp unknown_theme(theme) do
    choices = Enum.map_join(Breeze.Theme.default_cycle(), ", ", &Atom.to_string/1)
    "unknown Storybook theme #{inspect(theme)}; expected one of: #{choices}"
  end

  defp project_setting(key, default) do
    case Mix.Project.config()[:app] do
      app when is_atom(app) -> Application.get_env(app, key, default)
      _app -> default
    end
  end

  defp watcher_available?, do: Code.ensure_loaded?(FileSystem)

  defp maybe_put(options, _key, nil), do: options
  defp maybe_put(options, key, value), do: options ++ [{key, value}]

  defp invalid_options(invalid) do
    invalid
    |> Enum.map_join(", ", fn {option, value} ->
      if is_nil(value), do: option, else: "#{option}=#{value}"
    end)
    |> then(&"unknown or invalid option(s): #{&1}")
  end
end
