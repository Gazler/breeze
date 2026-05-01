defmodule Breeze.Server.Inspector do
  @moduledoc false

  def picks_mouse?(state), do: Breeze.Inspector.picks_mouse?(state)

  def select_target(state, %{button: :left, action: :press} = event) do
    Breeze.Inspector.select_at(state, event)
  end

  def select_target(state, %{action: :move} = event) do
    Breeze.Inspector.hover_at(state, event)
  end

  def select_target(state, _event), do: state

  def toggle_key?(key, state) do
    Breeze.Inspector.enabled?(state) and key == Breeze.Inspector.toggle_key(state)
  end

  def move_key?(key, state) do
    Breeze.Inspector.enabled?(state) and state.inspector_state.visible? and
      key == Breeze.Inspector.move_key(state)
  end

  def merge_render_data(%{inspector_state: %{config: false}} = state, _acc, _metadata), do: state

  def merge_render_data(state, acc, metadata) do
    %{viewports: viewports, bounds: bounds, flags: flags, boxes: boxes} = nodes(acc)

    state
    |> update_rendered(
      viewports: viewports,
      mouse_targets: bounds,
      flags: flags,
      boxes: Map.merge(state.rendered.boxes, boxes),
      focus_meta: Map.get(metadata, :focus_meta, %{}),
      implicit_state: Map.get(metadata, :implicit_state, %{}),
      implicit_meta: Map.get(metadata, :implicit_meta, %{})
    )
    |> Breeze.Inspector.sync_selected_id()
  end

  def push_snapshot_now(%{inspector_state: %{config: false}} = state), do: state

  def push_snapshot_now(%{inspector_state: %{subscribers: subscribers}} = state) do
    snapshot = Breeze.Inspector.snapshot(state)
    Breeze.RemoteInspector.publish(snapshot)

    if MapSet.size(subscribers) > 0 do
      Enum.each(subscribers, fn subscriber ->
        if is_pid(subscriber), do: send(subscriber, {:inspector_snapshot, snapshot})
      end)
    end

    state
  end

  defp update_rendered(state, updates), do: %{state | rendered: struct!(state.rendered, updates)}

  defp nodes(acc) do
    source_boxes = Map.get(acc, :boxes, %{})

    acc.elements
    |> Enum.sort()
    |> Enum.zip(acc.dimensions)
    |> Enum.reduce(%{viewports: %{}, bounds: %{}, flags: %{}, boxes: %{}}, fn {{idx, flags}, dims},
                                                                              node_acc ->
      key = node_key(idx, flags)
      viewport = Breeze.Viewport.from_dimensions(dims)

      width = max((viewport.width || 0) - 1, 0)
      height = max(viewport.height - 1, 0)
      normalized_flags = Keyword.put(flags, :__inspector_idx__, idx)

      bounds = %{
        left: viewport.left,
        top: viewport.top,
        right: viewport.left + width,
        bottom: viewport.top + height
      }

      %{
        viewports: Map.put(node_acc.viewports, key, viewport),
        bounds: Map.put(node_acc.bounds, key, bounds),
        flags: Map.put(node_acc.flags, key, normalized_flags),
        boxes: put_node_box(node_acc.boxes, key, source_boxes, idx, flags)
      }
    end)
  end

  defp node_key(idx, flags) do
    case Keyword.get(flags, :id) do
      id when is_binary(id) -> id
      _ -> "__inspector__" <> Integer.to_string(idx)
    end
  end

  defp put_node_box(boxes, key, source_boxes, idx, flags) do
    case Map.get(boxes, key) do
      nil ->
        case Map.get(source_boxes, idx) || Map.get(source_boxes, Keyword.get(flags, :id)) do
          nil -> boxes
          box -> Map.put(boxes, key, box)
        end

      _box ->
        boxes
    end
  end
end
