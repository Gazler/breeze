defmodule Breeze.Storybook.Registry do
  @moduledoc false

  def story_modules(directory \\ default_directory(), opts \\ []) do
    directory
    |> story_entries(opts)
    |> Enum.map(& &1.module)
  end

  def stories(directory \\ default_directory(), opts \\ []) do
    directory
    |> story_entries(opts)
    |> Enum.map(fn %{module: module, file: file} -> normalize_story(module, file) end)
    |> Enum.sort_by(&{&1.group, &1.title})
  end

  def story(id, directory \\ default_directory(), opts \\ []) when is_binary(id) do
    Enum.find(stories(directory, opts), &(&1.id == id))
  end

  def first_story(directory \\ default_directory(), opts \\ []) do
    List.first(stories(directory, opts))
  end

  defp default_directory do
    Path.expand("../../storybook", __DIR__)
  end

  defp story_entries(directory, opts) do
    directory
    |> story_files(opts)
    |> Enum.flat_map(&load_story_entry/1)
  end

  defp story_files(directory, opts) do
    case Keyword.get(opts, :file) do
      nil ->
        directory
        |> expand_directory()
        |> Path.join("*.story.exs")
        |> Path.wildcard()
        |> Enum.sort()

      file ->
        [expand_story_file(directory, file)]
    end
  end

  defp load_story_entry(file) do
    modules = file_modules(file)
    Code.require_file(file)

    modules
    |> Enum.filter(&story_module?/1)
    |> Enum.map(fn module -> %{file: file, module: module} end)
  end

  defp expand_directory(directory) do
    case Path.type(directory) do
      :absolute -> directory
      _ -> Path.expand("../../#{directory}", __DIR__)
    end
  end

  defp expand_story_file(directory, file) do
    case Path.type(file) do
      :absolute ->
        file

      _ ->
        expanded_directory = expand_directory(directory)
        candidate = Path.expand(file, expanded_directory)

        if File.exists?(candidate) do
          candidate
        else
          Path.expand(file)
        end
    end
  end

  defp file_modules(file) do
    with {:ok, contents} <- File.read(file),
         {:ok, ast} <- Code.string_to_quoted(contents, file: file) do
      ast
      |> collect_module_names([])
      |> Enum.reverse()
      |> Enum.map(&Module.concat/1)
    else
      _ -> []
    end
  end

  defp collect_module_names({:defmodule, _, [module_ast, [do: body]]}, acc) do
    module_name = module_ast_to_list(module_ast)
    collect_module_names(body, [module_name | acc])
  end

  defp collect_module_names({:__block__, _, expressions}, acc) when is_list(expressions) do
    Enum.reduce(expressions, acc, &collect_module_names/2)
  end

  defp collect_module_names(tuple, acc) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.reduce(acc, &collect_module_names/2)
  end

  defp collect_module_names(list, acc) when is_list(list) do
    Enum.reduce(list, acc, &collect_module_names/2)
  end

  defp collect_module_names(_, acc), do: acc

  defp module_ast_to_list({:__aliases__, _, parts}), do: parts
  defp module_ast_to_list(atom) when is_atom(atom), do: Module.split(atom)

  defp story_module?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :story, 0) and
      function_exported?(module, :render, 1)
  end

  defp normalize_story(module, file) do
    story =
      module.story()
      |> Map.new()
      |> Map.put(:module, module)
      |> Map.put_new(:file, file)
      |> Map.put_new(:directory, Path.dirname(file))

    Map.merge(
      %{
        id: module |> Module.split() |> List.last() |> Macro.underscore(),
        title: module |> Module.split() |> List.last() |> String.replace_suffix("Story", ""),
        group: "Blocks",
        description: "",
        notes: [],
        variants: [],
        source: nil,
        file: file,
        directory: Path.dirname(file)
      },
      story
    )
  end
end
