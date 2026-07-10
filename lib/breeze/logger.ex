defmodule Breeze.Logger do
  @moduledoc """
  A live log viewer for Breeze applications.

  Mount it like any other child view:

      <live id="logs" view={Breeze.Logger} start_opts={[title: "Logs"]} />

  Configure log capture when starting `Breeze.Server`, then mount this view to
  display the captured entries. Mounting the view does not alter the VM's logger
  handlers.
  """

  use Breeze.View

  @default_max_lines 200
  @level_order [:debug, :info, :notice, :warning, :error, :critical, :alert, :emergency]

  @impl Breeze.View
  def mount(opts, term) do
    case Breeze.Logger.Collector.subscribe(self()) do
      :ok ->
        :ok

      {:error, :not_started} ->
        raise ArgumentError,
              "Breeze.Logger requires logger capture to be configured when starting Breeze.Server"
    end

    {:ok,
     assign(term,
       title: Keyword.get(opts, :title, "Logs"),
       width: Keyword.get(opts, :width, 80),
       height: Keyword.get(opts, :height, 18),
       min_level: Keyword.get(opts, :min_level, :debug),
       clear_key: Keyword.get(opts, :clear_key, "c"),
       helper_text:
         helper_text(
           Keyword.get(opts, :min_level, :debug),
           Keyword.get(opts, :clear_key, "c")
         ),
       max_lines: Keyword.get(opts, :max_lines, @default_max_lines),
       terminal_width: terminal_width(term),
       terminal_height: terminal_height(term),
       lines: []
     )}
  end

  @impl Breeze.View
  def render(assigns) do
    assigns =
      assign(assigns,
        scroll_height: scroll_height(assigns),
        display_lines: display_lines(assigns)
      )

    ~H"""
    <box class={["bg overflow-hidden", width_style(@width), height_style(@height, assigns)]}>
      <box class="bg bold width-full">{@title}</box>
      <box class="bg width-full">{@helper_text}</box>
      <box
        id="logger"
        focusable
        implicit={Breeze.Implicit.Scroll}
        scroll-autoscroll="bottom"
        class={"bg border-rounded width-full overflow-scroll scrollbar-arrows focus:border-4 height-#{@scroll_height}"}
      >
        <box :for={entry <- @display_lines} style={entry.style}>{entry.line}</box>
      </box>
    </box>
    """
  end

  @impl Breeze.View
  def handle_event(_, %{"key" => key}, %{assigns: %{clear_key: key}} = term)
      when is_binary(key) do
    :ok = Breeze.Logger.Collector.clear()
    {:noreply, assign(term, lines: [])}
  end

  def handle_event(_, _, term), do: {:noreply, term}

  @impl Breeze.View
  def handle_info({:logger_snapshot, entries}, term) do
    {:noreply, assign(term, lines: filter_entries(entries, term.assigns))}
  end

  def handle_info({:logger_entry, entry}, term) do
    {:noreply, assign(term, lines: append_entry(term.assigns.lines, entry, term.assigns))}
  end

  def handle_info(:resize, term) do
    {:noreply,
     assign(term,
       terminal_width: terminal_width(term),
       terminal_height: terminal_height(term)
     )}
  end

  def handle_info(_, term), do: {:noreply, term}

  defp append_entry(lines, entry, assigns) do
    if include_level?(entry.level, assigns.min_level) do
      (lines ++ [decorate_entry(entry)]) |> Enum.take(-assigns.max_lines)
    else
      lines
    end
  end

  defp filter_entries(entries, assigns) do
    entries
    |> Enum.filter(&include_level?(&1.level, assigns.min_level))
    |> Enum.map(&decorate_entry/1)
    |> Enum.take(-assigns.max_lines)
  end

  defp include_level?(level, min_level) do
    level_value(level) >= level_value(min_level)
  end

  defp level_value(level) do
    Enum.find_index(@level_order, &(&1 == level)) || 0
  end

  defp decorate_entry(entry) do
    Map.put(entry, :style, level_style(entry.level))
  end

  defp width_style(:screen), do: "width-screen"
  defp width_style("screen"), do: "width-screen"
  defp width_style(width), do: "width-#{width}"

  defp height_style(:full, assigns), do: "height-#{total_height(:full, assigns)}"
  defp height_style("full", assigns), do: "height-#{total_height("full", assigns)}"
  defp height_style(height, _assigns), do: "height-#{height}"

  defp scroll_height(%{height: height} = assigns), do: max(total_height(height, assigns) - 2, 1)

  defp total_height(:full, assigns), do: Map.get(assigns, :terminal_height, 24)
  defp total_height("full", assigns), do: Map.get(assigns, :terminal_height, 24)
  defp total_height(height, _assigns) when is_integer(height), do: height

  defp display_lines(assigns) do
    width = log_line_width(assigns)

    Enum.flat_map(assigns.lines, fn entry ->
      entry.line
      |> wrap_line(width)
      |> Enum.map(&%{entry | line: &1})
    end)
  end

  defp log_line_width(%{width: width} = assigns) do
    width
    |> total_width(assigns)
    |> Kernel.-(2)
    |> max(1)
  end

  defp total_width(:screen, assigns), do: Map.get(assigns, :terminal_width, 80)
  defp total_width("screen", assigns), do: Map.get(assigns, :terminal_width, 80)
  defp total_width(width, _assigns) when is_integer(width), do: width

  defp wrap_line(line, width) when width <= 1, do: [String.slice(to_string(line), 0, 1)]

  defp wrap_line(line, width) do
    line = to_string(line)

    cond do
      line == "" ->
        [""]

      String.length(line) <= width ->
        [line]

      true ->
        {chunk, rest} = split_line(line, width)
        [chunk | wrap_line(rest, width)]
    end
  end

  defp split_line(line, width) do
    segment = String.slice(line, 0, width)

    split_at =
      if whitespace?(String.at(line, width)) do
        width
      else
        segment
        |> String.graphemes()
        |> Enum.with_index()
        |> Enum.reduce(nil, fn
          {" ", index}, _last -> index
          {"\t", index}, _last -> index
          {_grapheme, _index}, last -> last
        end)
      end

    split_at =
      case split_at do
        nil -> width
        0 -> width
        index -> index
      end

    chunk = String.slice(line, 0, split_at)

    rest =
      line
      |> String.slice(split_at, String.length(line) - split_at)
      |> String.trim_leading()

    {chunk, rest}
  end

  defp whitespace?(value), do: value in [" ", "\t"]

  defp terminal_width(%{terminal: %{size: %{width: width}}}) when is_integer(width), do: width
  defp terminal_width(_term), do: 80

  defp terminal_height(%{terminal: %{size: %{height: height}}}) when is_integer(height),
    do: height

  defp terminal_height(_term), do: 24

  defp level_style(:debug), do: "text-8"
  defp level_style(:info), do: "text-6"
  defp level_style(:notice), do: "text-4"
  defp level_style(:warning), do: "text-3 bold"
  defp level_style(:error), do: "text-1 bold"
  defp level_style(:critical), do: "text-1 bold"
  defp level_style(:alert), do: "text-1 bold"
  defp level_style(:emergency), do: "text-1 bold bg-11"
  defp level_style(_), do: "text-7"

  defp helper_text(min_level, nil), do: "Showing #{min_level}+ logs. Use j/k or arrows to scroll."

  defp helper_text(min_level, false),
    do: "Showing #{min_level}+ logs. Use j/k or arrows to scroll."

  defp helper_text(min_level, clear_key) do
    "Showing #{min_level}+ logs. Use j/k or arrows to scroll. Press #{clear_key} to clear."
  end
end
