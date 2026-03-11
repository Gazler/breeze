defmodule Breeze.RenderState do
  @moduledoc false

  alias Breeze.Viewport

  def build(term, acc) do
    {implicits, _current, _mod, _last_id, _root_attrs} =
      acc.elements
      |> Enum.sort()
      |> Enum.reduce(initial_implicit_build_state(), fn item, state ->
        reduce_implicit_item(item, state, term, map_size(acc.elements))
      end)

    events =
      acc.elements
      |> Enum.sort()
      |> Enum.reduce(%{}, fn {_idx, elem}, events ->
        id = Keyword.get(elem, :id)
        change = Keyword.get(elem, :"br-change")
        if change, do: Map.put(events, id, %{change: change}), else: events
      end)

    elements = build_dimensions(acc)

    %{
      term
      | elements: elements,
        focusables: acc.focusables,
        implicit_state: implicits,
        events: events
    }
  end

  def build_dimensions(acc) do
    Enum.zip(Enum.sort(acc.elements), acc.dimensions)
    |> Enum.reduce(%{}, fn {{_idx, flags}, dims}, elements ->
      case Keyword.get(flags, :id) do
        nil -> elements
        id -> Map.put(elements, id, Viewport.from_dimensions(dims))
      end
    end)
  end

  def dispatch_implicit_event(term, id, payload, route_change_fun, visited \\ MapSet.new()) do
    do_dispatch_implicit_event(term, id, payload, route_change_fun, visited)
  end

  def put_implicit_state(term, id, mod, implicit) do
    %{term | implicit_state: Map.put(term.implicit_state, id, {mod, implicit})}
  end

  def reconcile_implicits(implicit_state, dimensions) do
    Enum.reduce(implicit_state, %{}, fn
      {id, {mod, state}}, acc ->
        next_state =
          case {Map.get(dimensions, id), function_exported?(mod, :reconcile, 2)} do
            {element, true} when not is_nil(element) -> mod.reconcile(element, state)
            _ -> state
          end

        Map.put(acc, id, {mod, next_state})

      {id, value}, acc ->
        Map.put(acc, id, value)
    end)
  end

  defp initial_implicit_build_state, do: {%{}, [], nil, nil, %{}}

  defp reduce_implicit_item({idx, elem}, state, term, total) do
    {implicit_acc, current, mod, last_id, root_attrs} = state
    {implicit, id, implicit_owner, elem} = normalize_implicit_element(elem)

    cond do
      total == 1 && implicit && id ->
        {add_implicit_item(implicit_acc, term, id, implicit, [], elem), [], implicit, id, elem}

      mod && (implicit || idx == total - 1) ->
        flush_open_implicit(state, implicit, id, implicit_owner, elem, term)

      !mod && implicit ->
        {implicit_acc, current, implicit, id, elem}

      implicit_owner ->
        {implicit_acc, [elem | current], mod, last_id, root_attrs}

      true ->
        state
    end
  end

  defp normalize_implicit_element(elem) do
    elem = Map.new(elem) |> Map.delete(:focusable)
    {implicit, elem} = Map.pop(elem, :implicit)
    {id, elem} = Map.pop(elem, :id)
    {implicit_owner, elem} = Map.pop(elem, :implicit_owner)
    {implicit, id, implicit_owner, elem}
  end

  defp flush_open_implicit(state, implicit, id, implicit_owner, elem, term) do
    {implicit_acc, current, mod, last_id, root_attrs} = state

    current = if implicit_owner, do: [elem | current], else: current
    items = Enum.reverse(current)
    implicit_acc = add_implicit_item(implicit_acc, term, last_id, mod, items, root_attrs)

    implicit_acc =
      if implicit && id do
        add_implicit_item(implicit_acc, term, id, implicit, [], elem)
      else
        implicit_acc
      end

    {implicit_acc, [], implicit, id, elem}
  end

  defp do_dispatch_implicit_event(term, id, payload, route_change_fun, visited) do
    cond do
      MapSet.member?(visited, id) ->
        {:noreply, false, term}

      true ->
        case Map.get(term.implicit_state, id) do
          {mod, implicit} ->
            payload = Map.put(payload, "element", Map.get(term.elements, id))

            case mod.handle_event(:ignore_me, payload, implicit) do
              {{:change, event}, val} ->
                term = put_implicit_state(term, id, mod, val)

                {view_state, term} =
                  case get_in(term.events, [id, :change]) do
                    nil -> {:noreply, term}
                    change -> route_change_fun.(term, id, change, event)
                  end

                {view_state, true, term}

              {{:delegate, target_id}, val} ->
                term = put_implicit_state(term, id, mod, val)

                do_dispatch_implicit_event(
                  term,
                  target_id,
                  payload,
                  route_change_fun,
                  MapSet.put(visited, id)
                )

              {:noreply, val} ->
                term = put_implicit_state(term, id, mod, val)
                {:noreply, val != implicit, term}
            end

          nil ->
            {:noreply, false, term}
        end
    end
  end

  defp add_implicit_item(acc, term, id, mod, items, root_attrs) do
    screen_width = if term.terminal, do: term.terminal.size.width, else: 0
    screen_height = if term.terminal, do: term.terminal.size.height, else: 0

    root_attrs =
      root_attrs
      |> Map.put(:"screen-width", screen_width)
      |> Map.put(:"screen-height", screen_height)

    last_state =
      case term.implicit_state[id] do
        {_mod, last_state} -> last_state
        _ -> %{}
      end

    last_state =
      case Map.get(term.elements, id) do
        nil -> last_state
        element -> Map.put(last_state, :__element__, element)
      end

    implicit_state =
      case Code.ensure_loaded(mod) do
        {:module, _module} ->
          cond do
            function_exported?(mod, :init, 3) ->
              mod.init(items, root_attrs, last_state)

            function_exported?(mod, :init, 2) ->
              mod.init(items, last_state)

            true ->
              raise ArgumentError, "implicit #{inspect(mod)} must implement init/2 or init/3"
          end

        {:error, reason} ->
          raise ArgumentError,
                "implicit #{inspect(mod)} could not be loaded (#{inspect(reason)})"
      end

    Map.put(acc, id, {mod, implicit_state})
  end
end
