defmodule Breeze.RemoteInspector.Pages do
  @moduledoc false

  @reserved_ids ~w(logs tree overview layout theme implicit)
  @page_keys [:label, :assigns]

  def reserved_ids, do: @reserved_ids

  def build(pages) when is_list(pages) do
    pages
    |> Enum.map(&build_page/1)
    |> Enum.uniq_by(& &1.module)
  end

  def build(other) do
    raise ArgumentError,
          "expected :pages to be a list of page modules, got: #{inspect(other)}"
  end

  def validate_discovered(descriptors) when is_list(descriptors) do
    descriptors
    |> Enum.flat_map(&validate_descriptor/1)
    |> Enum.uniq_by(& &1.module)
  end

  def validate_discovered(_descriptors), do: []

  defp build_page(other) when not is_atom(other) do
    raise ArgumentError, "expected a page module, got: #{inspect(other)}"
  end

  defp build_page(module) do
    unless Code.ensure_loaded?(module) and function_exported?(module, :render, 1) do
      raise ArgumentError, "expected #{inspect(module)} to define render/1"
    end

    unless function_exported?(module, :page, 0) do
      raise ArgumentError, "expected #{inspect(module)} to define page/0"
    end

    page = module |> apply(:page, []) |> page!(module)

    %{
      id: page_id(module),
      label: page_label!(page, module),
      module: module,
      assigns: assigns!(page, module)
    }
  end

  defp page!(page, module) when is_list(page) do
    if Keyword.keyword?(page) do
      page |> Map.new() |> page!(module)
    else
      page_error!(module)
    end
  end

  defp page!(page, module) when is_map(page) do
    case Map.keys(page) -- @page_keys do
      [] ->
        page

      unknown ->
        raise ArgumentError,
              "unknown #{inspect(module)}.page/0 keys: #{inspect(Enum.sort(unknown))}"
    end
  end

  defp page!(_page, module), do: page_error!(module)

  defp page_error!(module) do
    raise ArgumentError, "expected #{inspect(module)}.page/0 to return a keyword list or map"
  end

  defp page_label!(page, module) do
    case Map.fetch(page, :label) do
      {:ok, label} when is_binary(label) ->
        case String.trim(label) do
          "" -> label_error!(module)
          label -> label
        end

      _label ->
        label_error!(module)
    end
  end

  defp label_error!(module) do
    raise ArgumentError, "expected #{inspect(module)}.page/0 to define a non-empty :label"
  end

  defp assigns!(page, module) do
    case Map.get(page, :assigns, %{}) do
      value when is_map(value) ->
        value

      value when is_list(value) ->
        if Keyword.keyword?(value), do: Map.new(value), else: assigns_error!(module)

      _value ->
        assigns_error!(module)
    end
  end

  defp assigns_error!(module) do
    raise ArgumentError, "expected :assigns for #{inspect(module)} to be a keyword list or map"
  end

  defp validate_descriptor(%{label: label, module: module} = descriptor)
       when is_atom(module) and is_binary(label) do
    if String.trim(label) != "" do
      [
        %{
          id: page_id(module),
          label: String.trim(label),
          module: module,
          assigns: discovered_assigns(descriptor)
        }
      ]
    else
      []
    end
  end

  defp validate_descriptor(_descriptor), do: []

  defp discovered_assigns(descriptor) do
    case Map.get(descriptor, :assigns, %{}) do
      value when is_map(value) -> value
      _value -> %{}
    end
  end

  defp page_id(module), do: "page:#{module}"
end
