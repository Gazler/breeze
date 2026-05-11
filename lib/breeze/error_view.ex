defmodule Breeze.ErrorView do
  @moduledoc false

  use Breeze.View

  @stacktrace_id "error-stacktrace"
  @history_id "error-history"
  @focus_order [@stacktrace_id, @history_id]

  def render_assigns(view, crash, %{width: width, height: height} = size) do
    crash = prepare_crash(view, crash, size)

    outer_width = max(width, 40)
    outer_height = max(height, 12)
    inner_width = max(outer_width - 2, 1)
    inner_height = max(outer_height - 2, 1)
    header_height = min(5, inner_height)
    body_height = max(inner_height - header_height - 1, 1)
    footer_height = max(inner_height - header_height - body_height, 0)
    layout = pane_layout(inner_width, body_height, crash.focused)

    entries = frame_entries(crash)
    selected_index = selected_index(crash, entries)
    message_lines = message_lines(view, crash, entries, selected_index, layout.right_inner_width)
    message_content_width = message_content_width(message_lines, layout.right_inner_width)

    %{
      crash: crash,
      outer_width: outer_width,
      outer_height: outer_height,
      header_height: header_height,
      body_height: body_height,
      footer_height: footer_height,
      pane_gap: layout.pane_gap,
      left_pane_width: layout.left_outer_width,
      right_pane_width: layout.right_outer_width,
      pane_inner_height: layout.pane_inner_height,
      selected_index: selected_index,
      entry_count: length(entries),
      stacktrace_pane_style:
        pane_style(crash.focused == @stacktrace_id, layout.left_outer_width, body_height),
      history_pane_style:
        pane_style(crash.focused == @history_id, layout.right_outer_width, body_height),
      stacktrace_title_style: pane_title_style(layout.left_inner_width),
      history_title_style: pane_title_style(layout.right_inner_width),
      header_lines: header_lines(view, crash, inner_width, header_height),
      footer_lines: footer_lines(inner_width, footer_height, crash),
      stacktrace_items:
        Enum.with_index(entries)
        |> Enum.map(fn {entry, index} ->
          %{index: index, label: pad_line(entry.summary, layout.left_inner_width)}
        end),
      history_lines: message_lines,
      history_content_height: length(message_lines),
      history_content_width: message_content_width,
      stacktrace_list_width: layout.left_inner_width,
      stacktrace_list_height: layout.stacktrace_list_height,
      history_scroll_width: layout.right_inner_width,
      history_scroll_height: layout.history_scroll_height
    }
  end

  def frame_count(crash) do
    length(frame_entries(crash))
  end

  def prepare_crash(view, crash, size) do
    assigns = base_assigns(view, crash, size)
    entries = frame_entries(crash)
    selected_index = selected_index(crash, entries)
    focused = normalize_focus(crash[:focused])

    implicit_state =
      normalize_implicit_state(crash[:implicit_state] || %{}, entries, assigns, selected_index)

    crash
    |> Map.put(:focused, focused)
    |> Map.put(:implicit_state, implicit_state)
    |> Map.put(:selected_index, selected_index_from_state(implicit_state, selected_index))
  end

  def handle_input(view, crash, input, size) do
    crash = prepare_crash(view, crash, size)
    assigns = render_assigns(view, crash, size)
    entries = frame_entries(crash)

    case input do
      {:key, key} when key in ["r", "R"] ->
        :restart

      {:key, key} when key in ["y", "Y", "c", "C"] ->
        {:copy_details, crash}

      {:key, key} when key in ["\t", "ArrowRight", "l"] ->
        {:update, %{crash | focused: rotate_focus(crash.focused, 1)}}

      {:key, key} when key in ["ShiftTab", "ArrowLeft", "h"] ->
        {:update, %{crash | focused: rotate_focus(crash.focused, -1)}}

      {:key, key} ->
        {:update, dispatch_focused_key(crash, entries, assigns, key)}

      _ ->
        {:update, crash}
    end
  end

  def render(assigns) do
    ~H"""
    <box style="border-rounded width-screen height-screen">
      <box :for={line <- @header_lines} style={"width-#{@outer_width - 2}"}>{line}</box>
      <box style={"inline width-#{@outer_width - 2} height-#{@body_height}"}>
        <box style={@stacktrace_pane_style}>
          <box style={@stacktrace_title_style}>Stacktrace</box>
          <box
            id="error-stacktrace"
            focusable
            implicit={Breeze.Implicit.List}
            list-loop="true"
            list-scroll-padding={1}
            list-initial-index={@selected_index}
            list-width={@stacktrace_list_width}
            style={"width-#{@stacktrace_list_width} height-#{@stacktrace_list_height} overflow-scroll scrollbar-arrows focus:scrollbar-3"}
          >
            <box
              :for={item <- @stacktrace_items}
              value={Integer.to_string(item.index)}
              style={"selected:bg-4 selected:text-7 focus:selected:text-7 focus:selected:bg-4 width-#{@stacktrace_list_width}"}
            >
              {item.label}
            </box>
          </box>
        </box>
        <box style={"width-#{@pane_gap}"}>
        </box>
        <box style={@history_pane_style}>
          <box style={@history_title_style}>Crash Details</box>
          <box
            id="error-history"
            focusable
            implicit={Breeze.Implicit.Scroll}
            style={"width-#{@history_scroll_width} height-#{@history_scroll_height} overflow-scroll scrollbar-arrows focus:scrollbar-3"}
          >
            <box :for={line <- @history_lines} style={"width-#{@history_content_width} height-1"}>
              {line}
            </box>
          </box>
        </box>
      </box>
      <box :for={line <- @footer_lines} style={"width-#{@outer_width - 2}"}>{line}</box>
    </box>
    """
  end

  def handle_event(_, _, term), do: {:noreply, term}
  def handle_info(_, term), do: {:noreply, term}

  def details_text(view, crash) do
    entries = frame_entries(crash)
    selected_index = selected_index(crash, entries)

    [
      "Breeze Error",
      "View #{inspect(view)}",
      "",
      "Crash Details",
      ""
      | message_lines(view, crash, entries, selected_index, 100)
    ]
    |> Enum.join("\n")
  end

  defp dispatch_focused_key(crash, entries, assigns, key) do
    case crash.focused do
      @stacktrace_id ->
        dispatch_stacktrace_key(crash, entries, assigns, key)

      @history_id ->
        dispatch_history_key(crash, assigns, key)

      _ ->
        crash
    end
  end

  defp dispatch_stacktrace_key(crash, _entries, assigns, key) do
    case Map.get(crash.implicit_state, @stacktrace_id) do
      {Breeze.Implicit.List, implicit} ->
        payload = %{"key" => key, "element" => list_element(assigns)}

        case Breeze.Implicit.List.handle_event(:ignore_me, payload, implicit) do
          {{:change, %{index: index}}, updated} ->
            put_crash_implicit(crash, @stacktrace_id, Breeze.Implicit.List, updated, index)

          {:noreply, updated} ->
            put_crash_implicit(
              crash,
              @stacktrace_id,
              Breeze.Implicit.List,
              updated,
              updated.selected_index
            )
        end

      _ ->
        crash
    end
  end

  defp dispatch_history_key(crash, assigns, key) do
    case Map.get(crash.implicit_state, @history_id) do
      {Breeze.Implicit.Scroll, implicit} ->
        payload = %{"key" => key, "element" => scroll_element(assigns)}

        case Breeze.Implicit.Scroll.handle_event(:ignore_me, payload, implicit) do
          {:noreply, updated} ->
            put_crash_implicit(
              crash,
              @history_id,
              Breeze.Implicit.Scroll,
              updated,
              crash.selected_index
            )
        end

      _ ->
        crash
    end
  end

  defp put_crash_implicit(crash, id, mod, state, selected_index) do
    crash
    |> Map.put(:implicit_state, Map.put(crash.implicit_state || %{}, id, {mod, state}))
    |> Map.put(:selected_index, selected_index || 0)
  end

  defp base_assigns(_view, crash, %{width: width, height: height}) do
    outer_width = max(width, 40)
    outer_height = max(height, 12)
    inner_width = max(outer_width - 2, 1)
    inner_height = max(outer_height - 2, 1)
    header_height = min(5, inner_height)
    body_height = max(inner_height - header_height - 1, 1)
    layout = pane_layout(inner_width, body_height, normalize_focus(crash[:focused]))

    %{
      left_inner_width: layout.left_inner_width,
      right_inner_width: layout.right_inner_width,
      pane_inner_height: layout.pane_inner_height,
      stacktrace_list_height: layout.stacktrace_list_height,
      history_scroll_height: layout.history_scroll_height
    }
  end

  defp pane_layout(inner_width, body_height, focused) do
    pane_gap = 1

    {left_outer_width, right_outer_width} =
      if focused == @history_id and inner_width >= 40 do
        left_outer_width = 12
        {left_outer_width, max(inner_width - left_outer_width - pane_gap, 1)}
      else
        left_outer_width = max(div(max(inner_width - pane_gap, 1), 2), 24)
        {left_outer_width, max(inner_width - left_outer_width - pane_gap, 24)}
      end

    left_inner_width = max(left_outer_width - 2, 1)
    right_inner_width = max(right_outer_width - 2, 1)
    pane_inner_height = max(body_height - 2, 1)

    %{
      pane_gap: pane_gap,
      left_outer_width: left_outer_width,
      right_outer_width: right_outer_width,
      left_inner_width: left_inner_width,
      right_inner_width: right_inner_width,
      pane_inner_height: pane_inner_height,
      stacktrace_list_height: max(pane_inner_height - 2, 1),
      history_scroll_height: max(pane_inner_height - 2, 1)
    }
  end

  defp normalize_implicit_state(implicit_state, entries, assigns, selected_index) do
    stacktrace_children =
      Enum.with_index(entries)
      |> Enum.map(fn {_entry, index} -> %{value: Integer.to_string(index)} end)

    {list_state, _list_meta} =
      case Map.get(implicit_state, @stacktrace_id) do
        {Breeze.Implicit.List, state} ->
          normalize_init_result(
            Breeze.Implicit.List.init(
              stacktrace_children,
              list_root_attrs(assigns, selected_index),
              state
            )
          )

        _ ->
          normalize_init_result(
            Breeze.Implicit.List.init(
              stacktrace_children,
              list_root_attrs(assigns, selected_index),
              %{}
            )
          )
      end

    {history_state, _history_meta} =
      case Map.get(implicit_state, @history_id) do
        {Breeze.Implicit.Scroll, state} ->
          normalize_init_result(Breeze.Implicit.Scroll.init([], %{}, state))

        _ ->
          normalize_init_result(Breeze.Implicit.Scroll.init([], %{}, %{}))
      end

    %{
      @stacktrace_id => {Breeze.Implicit.List, list_state},
      @history_id => {Breeze.Implicit.Scroll, history_state}
    }
  end

  defp normalize_init_result({:ok, state, meta}) when is_list(meta), do: {state, Map.new(meta)}
  defp normalize_init_result(state), do: {state, %{}}

  defp selected_index(crash, entries) do
    default = default_selected_index(entries)

    case Map.get(crash[:implicit_state] || %{}, @stacktrace_id) do
      {Breeze.Implicit.List, state} ->
        normalize_index(state.selected_index, length(entries), default)

      _ ->
        normalize_index(crash[:selected_index], length(entries), default)
    end
  end

  defp selected_index_from_state(implicit_state, fallback) do
    case Map.get(implicit_state, @stacktrace_id) do
      {Breeze.Implicit.List, state} -> state.selected_index || fallback
      _ -> fallback
    end
  end

  defp list_root_attrs(assigns, selected_index) do
    %{
      :"list-loop" => true,
      :"list-scroll-padding" => 1,
      :"list-initial-index" => selected_index,
      :"list-width" => assigns.left_inner_width
    }
  end

  defp list_element(assigns) do
    %{
      width: assigns.stacktrace_list_width,
      height: assigns.stacktrace_list_height,
      viewport_width: assigns.stacktrace_list_width,
      viewport_height: assigns.stacktrace_list_height
    }
  end

  defp scroll_element(assigns) do
    %{
      width: assigns.history_scroll_width,
      height: assigns.history_scroll_height,
      viewport_width: assigns.history_scroll_width,
      viewport_height: assigns.history_scroll_height,
      content_width: assigns.history_content_width,
      content_height: assigns.history_content_height
    }
  end

  defp pane_title_style(width), do: "width-#{width}"

  defp pane_style(true, pane_outer_width, body_height),
    do: "border border-4 width-#{pane_outer_width} height-#{body_height}"

  defp pane_style(false, pane_outer_width, body_height),
    do: "border width-#{pane_outer_width} height-#{body_height}"

  defp rotate_focus(current, delta) do
    index = Enum.find_index(@focus_order, &(&1 == current)) || 0
    size = length(@focus_order)
    Enum.at(@focus_order, rem(index + delta + size, size))
  end

  defp normalize_focus(focused) when focused in @focus_order, do: focused
  defp normalize_focus(_focused), do: @stacktrace_id

  defp header_lines(view, crash, width, height) do
    [
      "Breeze Error",
      "View #{inspect(view)}",
      "",
      Exception.format_banner(crash.kind, crash.reason, crash.stacktrace)
    ]
    |> Enum.flat_map(&split_lines/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(max(height, 1))
    |> pad_lines(width, height)
  end

  defp footer_lines(_width, 0, _crash), do: []

  defp footer_lines(width, height, crash) do
    default =
      "Tab switches panes. Arrows or j/k move and scroll. y copies details. r restarts. q quits."

    [
      crash[:notice] || default
    ]
    |> pad_lines(width, height)
  end

  defp message_lines(view, _crash, [], _selected_index, width) do
    ["Selected Frame", "", "View #{inspect(view)}", "", "No stacktrace frames captured"]
    |> wrap_lines(width)
  end

  defp message_lines(view, crash, entries, selected_index, width) do
    selected = Enum.at(entries, selected_index)

    selected_lines =
      [
        "Selected Frame",
        "",
        "View #{inspect(view)}"
        | selected.detail_lines
      ]
      |> wrap_lines(width)

    selected_lines ++ ["", "Crash Message", ""] ++ wrap_lines(crash_message_lines(crash), width)
  end

  defp crash_message_lines(crash) do
    case formatted_exception_lines(crash) do
      [] -> ["No crash message available"]
      lines -> lines
    end
  end

  defp selected_frame_lines(nil), do: ["No stacktrace frames captured"]

  defp selected_frame_lines(frame) do
    [
      "",
      "Module   #{inspect(frame.module)}",
      "Function #{frame.function}/#{frame.arity}",
      "File     #{frame.file}",
      "Line     #{frame.line}"
    ]
  end

  defp frame_entries(crash) do
    frames = frame_maps(crash.stacktrace)

    if frames == [] do
      fallback_entries(crash)
    else
      Enum.map(frames, fn frame ->
        %{
          summary:
            "#{String.pad_leading(Integer.to_string(frame.index), 2)} #{frame_summary(frame)}",
          detail_lines: selected_frame_lines(frame),
          app?: app_frame?(frame)
        }
      end)
    end
  end

  defp app_frame?(%{file: file}) when is_binary(file) do
    String.contains?(file, "/lib/") or String.contains?(file, "/test/")
  end

  defp app_frame?(_frame), do: false

  defp frame_maps(stacktrace) do
    stacktrace
    |> Enum.with_index(1)
    |> Enum.map(fn {frame, index} -> frame_map(frame, index) end)
  end

  defp frame_map({module, function, arity, location}, index) do
    %{
      index: index,
      module: module,
      module_name: inspect(module),
      function: function,
      arity: arity,
      file: normalize_file(location[:file]),
      line: location[:line] || 0
    }
  end

  defp frame_map(other, index) do
    %{
      index: index,
      module: :unknown,
      module_name: inspect(other),
      function: :unknown,
      arity: 0,
      file: inspect(other),
      line: 0
    }
  end

  defp frame_summary(frame) do
    "#{frame.module_name}.#{frame.function}/#{frame.arity} #{Path.basename(frame.file)}:#{frame.line}"
  end

  defp fallback_entries(crash) do
    formatted_lines = formatted_exception_lines(crash)

    [
      %{
        summary: "01 No structured stacktrace captured",
        detail_lines:
          [
            "",
            "No structured stacktrace captured",
            ""
          ] ++ formatted_lines,
        app?: true
      }
    ]
  end

  defp default_selected_index(entries) do
    case Enum.find_index(entries, & &1.app?) do
      nil -> 0
      index -> index
    end
  end

  defp normalize_file(nil), do: "unknown"
  defp normalize_file(file), do: file |> to_string() |> Path.relative_to_cwd()

  defp formatted_exception_lines(crash) do
    crash.kind
    |> Exception.format(crash.reason, crash.stacktrace)
    |> String.split("\n", trim: true)
  end

  defp normalize_index(nil, _length, default), do: default
  defp normalize_index(_index, 0, _default), do: 0

  defp normalize_index(index, length, _default) when is_integer(index),
    do: min(max(index, 0), length - 1)

  defp normalize_index(_index, _length, default), do: default

  defp split_lines(text), do: String.split(to_string(text), "\n", trim: false)

  defp pad_lines(lines, width, height) do
    padded = Enum.map(lines, &pad_line(&1, width))
    padded ++ List.duplicate(String.duplicate(" ", width), max(height - length(padded), 0))
  end

  defp pad_line(line, width) do
    line
    |> truncate_line(width)
    |> String.pad_trailing(width)
  end

  defp truncate_line(line, width) when byte_size(line) <= width, do: line
  defp truncate_line(line, width) when width > 3, do: String.slice(line, 0, width - 3) <> "..."
  defp truncate_line(_line, width) when width > 0, do: String.duplicate(".", width)
  defp truncate_line(line, width), do: String.slice(line, 0, width)

  defp message_content_width(lines, min_width) do
    Enum.reduce(lines, min_width, fn line, width ->
      max(width, String.length(to_string(line)))
    end)
  end

  defp wrap_lines(lines, width) do
    Enum.flat_map(lines, &wrap_line(&1, width))
  end

  defp wrap_line(line, width) when width <= 1, do: [String.slice(to_string(line), 0, 1)]

  defp wrap_line(line, width) do
    line = to_string(line)

    cond do
      line == "" ->
        [""]

      String.length(line) <= width ->
        [line]

      true ->
        segment = String.slice(line, 0, width)

        split_at =
          case String.split(segment, " ") do
            [_single] ->
              width

            parts ->
              parts
              |> Enum.drop(-1)
              |> Enum.join(" ")
              |> String.length()
          end

        split_at = if split_at <= 0, do: width, else: split_at
        chunk = String.slice(line, 0, split_at)

        rest =
          line |> String.slice(split_at, String.length(line) - split_at) |> String.trim_leading()

        [chunk | wrap_line(rest, width)]
    end
  end
end
