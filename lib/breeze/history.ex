defmodule Breeze.History do
  @moduledoc """
  Append-only history data for inline terminal views.
  """

  defstruct entries: []

  defmodule Entry do
    @moduledoc false
    defstruct [:id, :value]
  end

  def new(entries \\ []) do
    Enum.reduce(entries, %__MODULE__{}, fn
      {%{} = entry, id}, history -> append(history, id, entry)
      {id, entry}, history -> append(history, id, entry)
      entry, history -> append(history, entry)
    end)
  end

  def append(%__MODULE__{entries: entries} = history, id, value) do
    %{history | entries: entries ++ [%Entry{id: id, value: value}]}
  end

  def append(%__MODULE__{} = history, value) do
    append(history, System.unique_integer([:positive, :monotonic]), value)
  end

  def entries(%__MODULE__{entries: entries}), do: entries
  def entries(entries) when is_list(entries), do: Enum.map(entries, &entry/1)
  def entries(_), do: []

  defp entry(%Entry{} = entry), do: entry
  defp entry({id, value}), do: %Entry{id: id, value: value}
  defp entry(value), do: %Entry{id: nil, value: value}
end
