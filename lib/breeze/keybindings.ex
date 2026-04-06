defmodule Breeze.Keybindings do
  @moduledoc false

  @type binding :: %{
          key: String.t(),
          label: String.t() | nil,
          handler: (map(), map() -> term()) | nil
        }

  def normalize_list(bindings) when is_list(bindings) do
    Enum.map(bindings, &normalize/1)
  end

  def normalize_list(_bindings), do: []

  def normalize({key, handler}) when is_function(handler, 2) do
    %{key: to_string(key), label: nil, handler: handler}
  end

  def normalize({key, label}) when is_binary(label) do
    %{key: to_string(key), label: label, handler: nil}
  end

  def normalize({key, label, handler}) when is_binary(label) and is_function(handler, 2) do
    %{key: to_string(key), label: label, handler: handler}
  end

  def normalize(%{key: key} = binding) do
    %{
      key: to_string(key),
      label: Map.get(binding, :label) || Map.get(binding, "label"),
      handler: Map.get(binding, :handler) || Map.get(binding, "handler")
    }
  end

  def visible(bindings) do
    bindings
    |> normalize_list()
    |> Enum.map(fn binding -> %{key: binding.key, label: binding.label} end)
  end

  def merge_visible(binding_sets) when is_list(binding_sets) do
    binding_sets
    |> List.flatten()
    |> Enum.reduce({MapSet.new(), []}, fn %{key: key} = binding, {seen, acc} ->
      if MapSet.member?(seen, key) do
        {seen, acc}
      else
        {MapSet.put(seen, key), [binding | acc]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  def dispatch(event, bindings, term) do
    normalized = normalize_list(bindings)

    case Enum.find(normalized, fn binding ->
           binding.key == event["key"] and is_function(binding.handler, 2)
         end) do
      nil ->
        :continue

      %{handler: handler} ->
        handler.(event, term)
    end
  end
end
