defmodule LargeScroll do
  use Breeze.View
  alias BackBreeze.TextSpan
  alias BackBreeze.VirtualText.Source

  @line_count 20_000
  @line_width 120

  def mount(_opts, term) do
    {:ok,
     term
     |> focus("large-scroll-content")
     |> assign(
       line_count: @line_count,
       line_width: @line_width,
       header_content: header_content(@line_count, @line_width),
       sidebar_content: sidebar_content(),
       content: build_content(@line_count, @line_width)
     )}
  end

  def render(assigns) do
    ~H"""
    <box class="grid grid-cols-1 grid-rows-2 w-screen h-screen bg-panel">
      <box class="h-4 border-b bg-panel font-bold">{@header_content}</box>
      <box class="grid grid-cols-2 w-full h-full bg-panel">
        <box class="w-20 border-r bg-panel">{@sidebar_content}</box>
        <box
          id="large-scroll-content"
          implicit={Breeze.Implicit.Scroll}
          focusable
          class="w-full h-full bg-panel overflow-scroll"
          style={%{scrollbar: %{arrows: true}}}
        >
          {@content}
        </box>
      </box>
    </box>
    """
  end

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(_, term), do: {:noreply, term}

  defp header_content(line_count, line_width) do
    [
      TextSpan.new("Large scroll viewport\n", %{bold: true, background_color: 0}),
      TextSpan.new(
        "#{line_count} lines, ~#{line_width} columns per line. Use j/k, arrows, PageUp/PageDown, Home/End.\n",
        %{background_color: 0}
      ),
      TextSpan.new("q quits.", %{background_color: 0})
    ]
  end

  defp sidebar_content do
    [
      TextSpan.new("Views\n", %{bold: true, background_color: 0}),
      TextSpan.new("  Logs\n", %{background_color: 0}),
      TextSpan.new("  Metrics\n", %{background_color: 0}),
      TextSpan.new("  Requests\n", %{background_color: 0}),
      TextSpan.new("  Events\n", %{background_color: 0})
    ]
  end

  defp build_content(line_count, line_width) do
    Source.lazy(
      cache_key: {:large_scroll, line_count, line_width},
      intrinsic_width: line_width,
      line_count_fn: fn width ->
        line_count * wrapped_segments_per_line(line_width, width)
      end,
      slice_fn: fn start_line, visible_count, width ->
        build_visible_lines(start_line, visible_count, line_count, line_width, width)
      end
    )
  end

  defp build_visible_lines(start_line, visible_count, line_count, logical_width, viewport_width) do
    segment_count = wrapped_segments_per_line(logical_width, viewport_width)

    Enum.map(start_line..(start_line + visible_count - 1), fn line_no ->
      logical_index = div(line_no, segment_count) + 1
      segment_index = rem(line_no, segment_count)

      if logical_index > line_count do
        ""
      else
        line =
          build_logical_line(logical_index, logical_width)
          |> String.slice(segment_index * viewport_width, viewport_width)

        [{line, zebra_style(logical_index)}]
      end
    end)
  end

  defp build_logical_line(index, line_width) do
    prefix = index |> Integer.to_string() |> String.pad_leading(6, "0")
    base = "  Lorem ipsum dolor sit amet, consectetur adipiscing elit. "
    fill_width = max(line_width - String.length(prefix <> base), 0)
    prefix <> base <> String.duplicate("·", fill_width)
  end

  defp wrapped_segments_per_line(line_width, width) when is_integer(width) and width > 0 do
    max(div(line_width + width - 1, width), 1)
  end

  defp wrapped_segments_per_line(line_width, _width), do: line_width

  defp zebra_style(logical_index),
    do: %{background_color: if(rem(logical_index, 2) == 0, do: 8, else: 0)}
end

Breeze.Example.run(
  [
    view: LargeScroll,
    mouse: true,
    global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: 100_000
)
