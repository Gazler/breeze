defmodule Breeze.GlobalKeybindings do
  @moduledoc false

  def dispatch(event, state) do
    case Enum.find(keybindings(state), fn {key, _fun} -> key == event["key"] end) do
      nil ->
        :continue

      {_key, fun} when is_function(fun, 2) ->
        case fun.(event, state) do
          :continue -> :continue
          {:stop, state} -> {:stop, state}
          {:noreply, state} -> {:noreply, state}
        end
    end
  end

  def stop_action?(event, state) do
    match?({:stop, _}, dispatch(event, state))
  rescue
    _ -> false
  end

  defp keybindings(%{global_keybindings: keybindings}) when is_list(keybindings), do: keybindings
  defp keybindings(_state), do: []
end
