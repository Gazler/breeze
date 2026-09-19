defmodule Breeze.Charts.Data do
  @moduledoc false

  @colors {6, 5, 2, 3, 4, 1}

  def prepare(data, series) do
    unless is_list(data) and is_list(series) do
      raise ArgumentError, "chart data and series must be lists"
    end

    xs =
      Enum.map(data, fn
        %{x: x, values: values} when is_map(values) -> x
        _ -> raise ArgumentError, "chart data rows need :x and a :values map"
      end)

    unless Enum.all?(xs, &is_number/1) or Enum.all?(xs, &label?/1) do
      raise ArgumentError, "chart x values must be all numbers or all single-line strings"
    end

    normalized =
      series
      |> Enum.with_index()
      |> Enum.map(fn
        {%{key: key, name: name} = item, index} when is_atom(key) or is_binary(key) ->
          unless label?(name) do
            raise ArgumentError, "chart series names must be single-line strings"
          end

          values =
            Enum.map(data, fn row ->
              case Map.fetch(row.values, key) do
                {:ok, value} when is_number(value) ->
                  value

                {:ok, _value} ->
                  raise ArgumentError, "chart values for #{inspect(key)} must be numbers"

                :error ->
                  raise ArgumentError, "chart data row is missing series key #{inspect(key)}"
              end
            end)

          %{
            key: key,
            name: name,
            color: Map.get(item, :color, elem(@colors, rem(index, 6))),
            values: values
          }

        _ ->
          raise ArgumentError, "chart series need an atom or string :key and a :name"
      end)

    keys = Enum.map(normalized, & &1.key)

    unless length(keys) == length(Enum.uniq(keys)) do
      raise ArgumentError, "chart series keys must be unique"
    end

    {xs, normalized}
  end

  defp label?(text), do: is_binary(text) and not Regex.match?(~r/[\x00-\x1f\x7f]/u, text)
end
