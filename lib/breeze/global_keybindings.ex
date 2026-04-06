defmodule Breeze.GlobalKeybindings do
  @moduledoc false

  def dispatch(event, state) do
    case Breeze.Keybindings.dispatch(event, keybindings(state), state) do
      :continue ->
        :continue

      {:stop, state} ->
        {:stop, state}

      {:noreply, state} ->
        {:noreply, state}
    end
  end

  def stop_action?(event, state) do
    match?({:stop, _}, dispatch(event, state))
  rescue
    _ -> false
  end

  def visible(state) do
    state
    |> keybindings()
    |> Breeze.Keybindings.visible()
  end

  defp keybindings(%{global_keybindings: keybindings}) when is_list(keybindings), do: keybindings
  defp keybindings(_state), do: []
end
