defmodule Breeze.Debug do
  @moduledoc false

  use Breeze.View

  def mount(opts, term) do
    width = Keyword.get(opts, :width, 42)
    height = Keyword.get(opts, :height, 22)
    fixed = Keyword.get(opts, :fixed, false)
    right = Keyword.get(opts, :right, 0)
    bottom = Keyword.get(opts, :bottom, 0)

    if term.server do
      Breeze.Server.subscribe_debug(term.server, self())
    end

    {:ok,
     assign(term,
       stats: %{},
       width: width,
       height: height,
       fixed: fixed,
       right: right,
       bottom: bottom
     )}
  end

  def render(assigns) do
    stats = assigns.stats || %{}

    assigns =
      assign(assigns,
        root_style: root_style(assigns),
        input_label: fmt_us(stats[:last_input_us]),
        root_label: fmt_us(stats[:last_root_snapshot_us]),
        live_label: fmt_us(stats[:last_live_children_us]),
        base_label: fmt_us(stats[:last_render_base_us]),
        prep_label: fmt_us(stats[:last_prepare_decorations_us]),
        compose_label: fmt_us(stats[:last_frame_compose_us]),
        write_label: fmt_us(stats[:last_terminal_write_us]),
        frame_label: fmt_us(stats[:last_frame_us]),
        anim_label: fmt_us(stats[:last_animation_us]),
        bytes_label: stats[:last_frame_bytes] || 0,
        overlays_label: stats[:overlay_count] || 0,
        focus_label: stats[:focused] || "-",
        pending_label: to_string(stats[:pending?] || false),
        screen_label: fmt_screen(stats[:screen]),
        hottest_child_label: fmt_hottest_child(stats[:last_live_children] || []),
        profile_1: fmt_profile(Enum.at(stats[:last_render_profile] || [], 0)),
        profile_2: fmt_profile(Enum.at(stats[:last_render_profile] || [], 1)),
        profile_3: fmt_profile(Enum.at(stats[:last_render_profile] || [], 2)),
        profile_4: fmt_profile(Enum.at(stats[:last_render_profile] || [], 3)),
        profile_5: fmt_profile(Enum.at(stats[:last_render_profile] || [], 4))
      )

    ~H"""
    <box style={@root_style}>
      <box style="bg-0 width-full height-full">
        <box style="bold bg-0 width-full">Debug</box>
        <box style="bg-0 width-full">input: {@input_label}</box>
        <box style="bg-0 width-full">root: {@root_label}</box>
        <box style="bg-0 width-full">live: {@live_label}</box>
        <box style="bg-0 width-full">base: {@base_label}</box>
        <box style="bg-0 width-full">prep: {@prep_label}</box>
        <box style="bg-0 width-full">compose: {@compose_label}</box>
        <box style="bg-0 width-full">write: {@write_label}</box>
        <box style="bg-0 width-full">frame: {@frame_label}</box>
        <box style="bg-0 width-full">anim: {@anim_label}</box>
        <box style="bg-0 width-full">bytes: {@bytes_label} overlays: {@overlays_label}</box>
        <box style="bg-0 width-full">focus: {@focus_label} pending: {@pending_label}</box>
        <box style="bg-0 width-full">hot: {@hottest_child_label}</box>
        <box style="bg-0 width-full">p1: {@profile_1}</box>
        <box style="bg-0 width-full">p2: {@profile_2}</box>
        <box style="bg-0 width-full">p3: {@profile_3}</box>
        <box style="bg-0 width-full">p4: {@profile_4}</box>
        <box style="bg-0 width-full">p5: {@profile_5}</box>
        <box style="bg-0 width-full">screen: {@screen_label}</box>
      </box>
    </box>
    """
  end

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info({:debug_stats, stats}, term), do: {:noreply, assign(term, stats: stats)}

  def handle_info(_, term), do: {:noreply, term}

  defp fmt_us(nil), do: "-"
  defp fmt_us(value) when is_integer(value), do: "#{Float.round(value / 1000, 2)}ms"

  defp fmt_screen(%{width: width, height: height}), do: "#{width}x#{height}"
  defp fmt_screen(_screen), do: "-"

  defp fmt_hottest_child([%{id: id, view: view, us: us} | _]) do
    "#{id} #{view} #{fmt_us(us)}"
  end

  defp fmt_hottest_child(_children), do: "-"

  defp fmt_profile(%{label: label, metric: metric, value: value}) do
    "#{label} #{metric_name(metric)} #{fmt_us(value)}"
  end

  defp fmt_profile(_entry), do: "-"

  defp root_style(assigns) do
    base = "border-rounded bg-0 width-#{assigns.width} height-#{assigns.height}"

    if assigns.fixed do
      base <> " fixed right-#{assigns.right} bottom-#{assigns.bottom}"
    else
      base
    end
  end

  defp metric_name(:view_render_us), do: "view"
  defp metric_name(:template_tree_us), do: "tree"
  defp metric_name(:build_tree_us), do: "build"
  defp metric_name(:layout_us), do: "layout"
  defp metric_name(:render_with_dimensions_us), do: "render_dims"
  defp metric_name(:item_render_us), do: "items"
  defp metric_name(:compose_us), do: "compose"
  defp metric_name(:render_children_us), do: "children"
  defp metric_name(:container_render_self_us), do: "self"
  defp metric_name(:container_layer_map_us), do: "layer_map"
  defp metric_name(:layer_maps_to_content_us), do: "content"
  defp metric_name(:child_render_us), do: "render"
  defp metric_name(:render_state_us), do: "state"
  defp metric_name(:decorations_us), do: "decor"
  defp metric_name(metric), do: to_string(metric)
end
