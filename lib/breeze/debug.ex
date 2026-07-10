defmodule Breeze.Debug do
  @moduledoc false

  use Breeze.View

  def mount(opts, term) do
    width = Keyword.get(opts, :width, 42)
    height = Keyword.get(opts, :height, 22)
    fixed = Keyword.get(opts, :fixed, false)
    right = Keyword.get(opts, :right, 0)
    bottom = Keyword.get(opts, :bottom, 0)
    stats = Keyword.get(opts, :stats, %{})

    if term.server do
      Breeze.Server.Diagnostics.subscribe_stats(term.server, self())
    end

    {:ok,
     assign(term,
       stats: stats,
       width: width,
       height: height,
       fixed: fixed,
       right: right,
       bottom: bottom
     )}
  end

  def render(assigns) do
    stats = assigns.stats || %{}
    hot_width = max(assigns.width - 5, 1)
    profile_width = max(assigns.width - 4, 1)

    assigns =
      assign(assigns,
        root_style: root_style(assigns),
        input_label: fmt_us(stats[:last_input_us]),
        cause_label: fmt_atom(stats[:last_render_cause]),
        root_label:
          fmt_window(
            stats[:last_root_snapshot_app_us] || stats[:last_root_snapshot_us],
            stats[{:avg, :last_root_snapshot_app_us}] || stats[{:avg, :last_root_snapshot_us}],
            stats[{:max, :last_root_snapshot_app_us}] || stats[{:max, :last_root_snapshot_us}]
          ),
        live_label:
          fmt_window(
            stats[:last_live_children_app_us] || stats[:last_live_children_us],
            stats[{:avg, :last_live_children_app_us}] || stats[{:avg, :last_live_children_us}],
            stats[{:max, :last_live_children_app_us}] || stats[{:max, :last_live_children_us}]
          ),
        base_label:
          fmt_window(
            stats[:last_render_base_app_us] || stats[:last_render_base_us],
            stats[{:avg, :last_render_base_app_us}] || stats[{:avg, :last_render_base_us}],
            stats[{:max, :last_render_base_app_us}] || stats[{:max, :last_render_base_us}]
          ),
        prep_label:
          fmt_window(
            stats[:last_prepare_decorations_us],
            stats[{:avg, :last_prepare_decorations_us}],
            stats[{:max, :last_prepare_decorations_us}]
          ),
        compose_label:
          fmt_window(
            stats[:last_frame_compose_us],
            stats[{:avg, :last_frame_compose_us}],
            stats[{:max, :last_frame_compose_us}]
          ),
        write_label:
          fmt_window(
            stats[:last_terminal_write_us],
            stats[{:avg, :last_terminal_write_us}],
            stats[{:max, :last_terminal_write_us}]
          ),
        frame_label:
          fmt_window(
            stats[:last_frame_us],
            stats[{:avg, :last_frame_us}],
            stats[{:max, :last_frame_us}]
          ),
        anim_label:
          fmt_window(
            stats[:last_animation_us],
            stats[{:avg, :last_animation_us}],
            stats[{:max, :last_animation_us}]
          ),
        render_count_label:
          fmt_rate(stats[:render_base_count] || 0, stats[{:rate, :render_base_count}] || 0),
        flush_count_label:
          fmt_rate(
            stats[:flush_input_batch_count] || 0,
            stats[{:rate, :flush_input_batch_count}] || 0
          ),
        invalidation_count_label:
          fmt_rate(
            stats[:child_invalidated_count] || 0,
            stats[{:rate, :child_invalidated_count}] || 0
          ),
        animation_count_label:
          fmt_rate(stats[:animation_tick_count] || 0, stats[{:rate, :animation_tick_count}] || 0),
        bytes_label: stats[:last_frame_bytes] || 0,
        overlays_label: stats[:overlay_count] || 0,
        focus_label: stats[:focused] || "-",
        pending_label: to_string(stats[:pending?] || false),
        screen_label: fmt_screen(stats[:screen]),
        hottest_child_label: fmt_hottest_child(stats[:last_live_children] || [], hot_width),
        profile_1: fmt_profile(Enum.at(stats[:last_render_profile] || [], 0), profile_width),
        profile_2: fmt_profile(Enum.at(stats[:last_render_profile] || [], 1), profile_width),
        profile_3: fmt_profile(Enum.at(stats[:last_render_profile] || [], 2), profile_width),
        profile_4: fmt_profile(Enum.at(stats[:last_render_profile] || [], 3), profile_width),
        profile_5: fmt_profile(Enum.at(stats[:last_render_profile] || [], 4), profile_width)
      )

    ~H"""
    <box style={@root_style}>
      <box style="bg-0 width-full height-full">
        <box style="bold bg-0 width-full">Debug</box>
        <box style="bg-0 width-full">input: {@input_label}</box>
        <box style="bg-0 width-full">cause: {@cause_label}</box>
        <box style="bg-0 width-full">root l/a/m: {@root_label}</box>
        <box style="bg-0 width-full">live l/a/m: {@live_label}</box>
        <box style="bg-0 width-full">base l/a/m: {@base_label}</box>
        <box style="bg-0 width-full">prep l/a/m: {@prep_label}</box>
        <box style="bg-0 width-full">comp l/a/m: {@compose_label}</box>
        <box style="bg-0 width-full">write l/a/m: {@write_label}</box>
        <box style="bg-0 width-full">frame l/a/m: {@frame_label}</box>
        <box style="bg-0 width-full">anim l/a/m: {@anim_label}</box>
        <box style="bg-0 width-full">renders: {@render_count_label}</box>
        <box style="bg-0 width-full">flushes: {@flush_count_label}</box>
        <box style="bg-0 width-full">invalid: {@invalidation_count_label}</box>
        <box style="bg-0 width-full">ticks: {@animation_count_label}</box>
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

  def handle_info({:debug_stats, stats}, term),
    do: {:noreply, assign(term, stats: stats), invalidate: false}

  def handle_info(_, term), do: {:noreply, term}

  defp fmt_us(nil), do: "-"
  defp fmt_us(value) when is_integer(value), do: "#{Float.round(value / 1000, 2)}ms"
  defp fmt_atom(nil), do: "-"
  defp fmt_atom(value) when is_atom(value), do: Atom.to_string(value)
  defp fmt_atom(value), do: to_string(value)

  defp fmt_window(last, avg, max_value) do
    "#{fmt_us(last)}/#{fmt_us(avg)}/#{fmt_us(max_value)}"
  end

  defp fmt_rate(total, rate) do
    "#{total} (#{rate}/s)"
  end

  defp fmt_screen(%{width: width, height: height}), do: "#{width}x#{height}"
  defp fmt_screen(_screen), do: "-"

  defp fmt_hottest_child([%{id: id, view: view, us: us} | _], width) do
    fit_text("#{id} #{view} #{fmt_us(us)}", width)
  end

  defp fmt_hottest_child(_children, _width), do: "-"

  defp fmt_profile(%{label: label, metric: metric, value: value}, width) do
    fit_text("#{label} #{metric_name(metric)} #{fmt_us(value)}", width)
  end

  defp fmt_profile(_entry, _width), do: "-"

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

  defp fit_text(text, width) when is_binary(text) and is_integer(width) and width > 3 do
    if String.length(text) > width do
      String.slice(text, 0, width - 3) <> "..."
    else
      text
    end
  end

  defp fit_text(text, _width), do: text
end
