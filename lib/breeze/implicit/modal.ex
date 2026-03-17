defmodule Breeze.Implicit.Modal do
  @moduledoc false

  def init(_items, last_state), do: last_state

  def init(_items, _root_attrs, last_state), do: last_state

  def handle_event(_, %{"key" => "Escape"}, state) do
    {{:change, %{action: :close}}, state}
  end

  def handle_event(_, _, state), do: {:noreply, state}

  def handle_modifiers(:root, _flags, _state), do: []

  def handle_modifiers(:child, _flags, _state) do
    []
  end
end
