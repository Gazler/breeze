defmodule Breeze.RemoteInspector.Pages.LLM do
  @moduledoc """
  Sample remote inspector page with a compact, text-first view of the active app.

  It can be attached when starting the inspector:

      mix breeze.inspector --page Breeze.RemoteInspector.Pages.LLM
  """

  @behaviour Breeze.RemoteInspector.Page

  use Breeze.View
  import Breeze.Blocks

  def page, do: [id: "llm", label: "LLM", render_tree: true]

  def render(assigns) do
    ~H"""
    <.scroll id="remote-inspector-llm-page" class="width-full height-full padding-top-1">
      <box class="width-full bold text-primary">LLM Context</box>
      <box class="width-full">root_view={module_name(snapshot_value(@snapshot, :root_view))}</box>
      <box class="width-full">source={source_line(@active_source)}</box>
      <box class="width-full">screen={screen_line(@screen)}</box>
      <box class="width-full">counts={counts_line(snapshot_value(@snapshot, :counts))}</box>
      <box class="width-full">focus={focus_line(@snapshot)}</box>
      <box class="width-full">
        selected={selected_line(@selected, snapshot_value(@snapshot, :selected_id))}
      </box>
      <box class="width-full">hovered={value(snapshot_value(@snapshot, :hovered_id))}</box>
      <box class="width-full">
      </box>
      <box :for={row <- render_tree_rows(@render_tree)} class={row.class}>{row.text}</box>
    </.scroll>
    """
  end

  defp snapshot_value(%{} = snapshot, key), do: Map.get(snapshot, key)
  defp snapshot_value(_snapshot, _key), do: nil

  defp module_name(module) when is_atom(module), do: inspect(module)
  defp module_name(module) when is_binary(module), do: module
  defp module_name(_module), do: "-"

  defp source_line(nil), do: "-"
  defp source_line({node, pid}), do: "#{node}:#{pid}"
  defp source_line(%{node: node, pid: pid}), do: "#{node}:#{inspect(pid)}"
  defp source_line(source), do: inspect(source)

  defp screen_line(%{width: width, height: height}), do: "#{width}x#{height}"
  defp screen_line(_screen), do: "-"

  defp counts_line(%{
         elements: elements,
         focusables: focusables,
         mouse_targets: mouse_targets,
         children: children
       }) do
    "elements=#{elements} focusables=#{focusables} mouse_targets=#{mouse_targets} children=#{children}"
  end

  defp counts_line(_counts), do: "-"

  defp focus_line(%{focused: focused, focus: focus}) when is_map(focus) do
    focusables =
      focus
      |> Map.get(:focusables, [])
      |> List.wrap()
      |> length()

    "focused=#{value(focused)} focusables=#{focusables} active_scope=#{value(Map.get(focus, :active_scope))}"
  end

  defp focus_line(_snapshot), do: "-"

  defp selected_line(selected, selected_id) do
    "id=#{value(selected_id)} component=#{value(selected_value(selected, :component))} class=#{value(selected_value(selected, :class))}"
  end

  defp selected_value(%{} = selected, key), do: Map.get(selected, key)
  defp selected_value(_selected, _key), do: nil

  defp render_tree_rows(nil), do: [%{class: "width-full text-muted", text: "render_tree=-"}]

  defp render_tree_rows(%{} = tree) do
    rows = [
      %{class: "width-full bold text-primary", text: "Render Tree"},
      %{
        class: "width-full text-muted",
        text:
          "kind=#{value(Map.get(tree, :kind, :rendered))} selected=#{value(Map.get(tree, :selected_id))} truncated=#{inspect(Map.get(tree, :truncated?, false))}"
      }
    ]

    nodes =
      tree
      |> Map.get(:nodes, [])
      |> flatten_tree()
      |> Enum.take(12)
      |> Enum.map(fn node ->
        %{
          class: "width-full overflow-hidden",
          text: "#{String.duplicate("  ", node.depth)}#{value(node.id)} #{label_text(node.label)}"
        }
      end)

    rows ++ nodes
  end

  defp render_tree_rows(_tree), do: [%{class: "width-full text-muted", text: "render_tree=-"}]

  defp flatten_tree(nodes, depth \\ 0)

  defp flatten_tree(nodes, depth) when is_list(nodes) do
    Enum.flat_map(nodes, &flatten_tree_node(&1, depth))
  end

  defp flatten_tree(_nodes, _depth), do: []

  defp flatten_tree_node(%{} = node, depth) do
    row = %{
      depth: depth,
      id: Map.get(node, :id),
      label: Map.get(node, :label)
    }

    [row | flatten_tree(Map.get(node, :children, []), depth + 1)]
  end

  defp flatten_tree_node(_node, _depth), do: []

  defp label_text(nil), do: ""
  defp label_text(label) when is_binary(label), do: label

  defp label_text(labels) when is_list(labels) do
    labels
    |> Enum.map(fn
      %{__struct__: BackBreeze.TextSpan, text: text} -> text
      value -> to_string(value)
    end)
    |> Enum.join("")
  end

  defp label_text(label), do: to_string(label)

  defp value(nil), do: "-"
  defp value(value) when is_binary(value), do: value
  defp value(value) when is_atom(value), do: inspect(value)
  defp value(value), do: inspect(value)
end
