defmodule Breeze.Implicit.Checkbox do
  @moduledoc false

  @behaviour Breeze.Implicit

  def init(_children, root_attrs, last_state) do
    checked =
      case Map.get(root_attrs, :"checkbox-checked") do
        nil -> Map.get(last_state, :checked, false)
        value -> normalize_boolean(value, false)
      end

    disabled =
      root_attrs
      |> Map.get(:"checkbox-disabled")
      |> normalize_boolean(false)

    {:ok, %{checked: checked, disabled: disabled}}
  end

  def handle_event(_, _, %{disabled: true} = state), do: {:noreply, state}

  def handle_event(_, %{"key" => key}, state) when key in ["Enter", " "], do: toggle(state)

  def handle_event(_, %{"mouse" => %{"button" => "left", "action" => "press"}}, state),
    do: toggle(state)

  def handle_event(_, _, state), do: {:noreply, state}

  def handle_modifiers(:root, _flags, state) do
    state
    |> selected_modifiers()
    |> maybe_add_disabled_style(state)
  end

  def handle_modifiers(:child, flags, state) do
    flags
    |> indicator_modifiers(state)
    |> maybe_add_disabled_style(state)
  end

  defp toggle(state) do
    checked = !state.checked
    {{:change, %{value: checked}}, %{state | checked: checked}}
  end

  defp selected_modifiers(%{checked: true}), do: [selected: true]
  defp selected_modifiers(_state), do: []

  defp indicator_modifiers(flags, state) do
    case Keyword.get(flags, :"checkbox-state") do
      "checked" when state.checked -> [selected: true]
      "unchecked" when not state.checked -> [selected: true]
      _ -> []
    end
  end

  defp maybe_add_disabled_style(modifiers, %{disabled: true}) do
    modifiers ++ [style: "text-muted"]
  end

  defp maybe_add_disabled_style(modifiers, _state), do: modifiers

  defp normalize_boolean(value, _default) when value in [true, "true", "1", ""], do: true
  defp normalize_boolean(value, _default) when value in [false, "false", "0"], do: false
  defp normalize_boolean(_value, default), do: default
end
