defmodule Breeze.RenderState do
  @moduledoc false

  alias Breeze.Viewport

  def build(term, acc) do
    sorted_elements = Enum.sort(acc.elements)
    total = length(sorted_elements)

    {implicit_build_state, events} =
      Enum.reduce(sorted_elements, {initial_implicit_build_state(), %{}}, fn {_idx, elem} = item,
                                                                             {implicit_state,
                                                                              events} ->
        next_implicit_state =
          reduce_implicit_item(item, implicit_state, term, total)

        id = Keyword.get(elem, :id)
        change = Keyword.get(elem, :"br-change")

        next_events =
          if change, do: Map.put(events, id, %{change: change}), else: events

        {next_implicit_state, next_events}
      end)

    {implicits, implicit_meta, _current, _mod, _last_id, _root_attrs} = implicit_build_state

    raw_dimensions = build_dimensions(sorted_elements, acc.dimensions)
    {elements, mouse_targets} = build_layout_maps(raw_dimensions)

    %{
      term
      | elements: elements,
        mouse_targets: mouse_targets,
        focusables: acc.focusables,
        implicit_state: implicits,
        implicit_meta: implicit_meta,
        rendered_boxes: Map.get(acc, :boxes, %{}),
        events: events
    }
  end

  def build_dimensions(acc) do
    build_dimensions(Enum.sort(acc.elements), acc.dimensions)
  end

  defp build_dimensions(sorted_elements, dimensions) do
    Enum.zip(sorted_elements, dimensions)
    |> Enum.reduce(%{}, fn {{_idx, flags}, dims}, elements ->
      case Keyword.get(flags, :id) do
        nil -> elements
        id -> Map.put(elements, id, dims)
      end
    end)
  end

  defp build_layout_maps(raw_dimensions) do
    Enum.reduce(raw_dimensions, {%{}, %{}}, fn {id, dims}, {elements, mouse_targets} ->
      width = resolved_dimension(dims, :width, :viewport_width)
      height = resolved_dimension(dims, :height, :viewport_height)
      left = Map.get(dims, :left, 0)
      top = Map.get(dims, :top, 0)

      normalized_dims =
        dims
        |> Map.put(:width, width)
        |> Map.put(:height, height)
        |> Map.put(:viewport_width, integer_dimension(Map.get(dims, :viewport_width), width))
        |> Map.put(:viewport_height, integer_dimension(Map.get(dims, :viewport_height), height))

      target =
        normalized_dims
        |> Map.put(:left, left)
        |> Map.put(:top, top)
        |> Map.put(:right, left + max(width - 1, 0))
        |> Map.put(:bottom, top + max(height - 1, 0))

      {
        Map.put(elements, id, Viewport.from_dimensions(normalized_dims)),
        Map.put(mouse_targets, id, target)
      }
    end)
  end

  defp resolved_dimension(dims, primary_key, fallback_key) do
    dims
    |> Map.get(primary_key)
    |> integer_dimension(Map.get(dims, fallback_key, 0))
  end

  defp integer_dimension(value, _fallback) when is_integer(value), do: value
  defp integer_dimension(_value, fallback) when is_integer(fallback), do: fallback
  defp integer_dimension(_value, _fallback), do: 0

  def dispatch_implicit_event(term, id, payload, route_change_fun, visited \\ MapSet.new()) do
    do_dispatch_implicit_event(term, id, payload, route_change_fun, visited)
  end

  def put_implicit_state(term, id, mod, implicit) do
    %{term | implicit_state: Map.put(term.implicit_state, id, {mod, implicit})}
  end

  defp initial_implicit_build_state, do: {%{}, %{}, [], nil, nil, %{}}

  defp reduce_implicit_item({idx, elem}, state, term, total) do
    {implicit_acc, implicit_meta, current, mod, last_id, root_attrs} = state
    {implicit, id, implicit_owner, elem} = normalize_implicit_element(elem)

    cond do
      total == 1 && implicit && id ->
        {implicit_acc, implicit_meta} =
          add_implicit_item(implicit_acc, implicit_meta, term, id, implicit, [], elem)

        {implicit_acc, implicit_meta, [], implicit, id, elem}

      mod && (implicit || idx == total - 1) ->
        flush_open_implicit(state, implicit, id, implicit_owner, elem, term)

      !mod && implicit ->
        {implicit_acc, implicit_meta, current, implicit, id, elem}

      implicit_owner ->
        {implicit_acc, implicit_meta, [elem | current], mod, last_id, root_attrs}

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
    {implicit_acc, implicit_meta, current, mod, last_id, root_attrs} = state

    current = if implicit_owner, do: [elem | current], else: current
    items = Enum.reverse(current)

    {implicit_acc, implicit_meta} =
      add_implicit_item(implicit_acc, implicit_meta, term, last_id, mod, items, root_attrs)

    {implicit_acc, implicit_meta} =
      if implicit && id do
        add_implicit_item(implicit_acc, implicit_meta, term, id, implicit, [], elem)
      else
        {implicit_acc, implicit_meta}
      end

    {implicit_acc, implicit_meta, [], implicit, id, elem}
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
              {{:change, event}, val, opts} when is_list(opts) ->
                term = put_implicit_state(term, id, mod, val)
                term = apply_implicit_term_options(term, opts)

                {view_state, term} =
                  case get_in(term.events, [id, :change]) do
                    nil -> {:noreply, term}
                    change -> route_change_fun.(term, id, change, event)
                  end

                {view_state, true, term}

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
            case get_in(term.focus_meta, [id, :implicit_owner]) do
              owner_id when is_binary(owner_id) ->
                do_dispatch_implicit_event(
                  term,
                  owner_id,
                  payload,
                  route_change_fun,
                  MapSet.put(visited, id)
                )

              _ ->
                {:noreply, false, term}
            end
        end
    end
  end

  defp apply_implicit_term_options(term, opts) do
    Enum.reduce(opts, term, fn
      {:focus, focused}, acc ->
        %{acc | focused: focused, allow_unfocused?: is_nil(focused)}

      _, acc ->
        acc
    end)
  end

  defp add_implicit_item(acc, meta_acc, term, id, mod, items, root_attrs) do
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

    {implicit_state, implicit_meta} =
      case Code.ensure_loaded(mod) do
        {:module, _module} ->
          cond do
            function_exported?(mod, :init, 3) ->
              normalize_init_result(mod.init(items, root_attrs, last_state))

            function_exported?(mod, :init, 2) ->
              normalize_init_result(mod.init(items, last_state))

            true ->
              raise ArgumentError, "implicit #{inspect(mod)} must implement init/2 or init/3"
          end

        {:error, reason} ->
          raise ArgumentError,
                "implicit #{inspect(mod)} could not be loaded (#{inspect(reason)})"
      end

    {
      Map.put(acc, id, {mod, implicit_state}),
      Map.put(meta_acc, id, implicit_meta)
    }
  end

  defp normalize_init_result({:ok, implicit_state, implicit_meta}) when is_list(implicit_meta) do
    {implicit_state, Map.new(implicit_meta)}
  end

  defp normalize_init_result({:ok, implicit_state}) do
    {implicit_state, %{}}
  end

  defp normalize_init_result(implicit_state) do
    {implicit_state, %{}}
  end
end
