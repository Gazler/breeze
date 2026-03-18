defmodule Breeze.Logger do
  @moduledoc """
  A live log viewer for Breeze applications.

  Mount it like any other child view:

      <live id="logs" view={Breeze.Logger} start_opts={[title: "Logs"]} />

  This view hooks into Erlang's `:logger` and keeps a bounded list of recent
  entries in its own state so it can be routed, persisted, or preloaded.
  """

  use Breeze.View

  @default_max_lines 200
  @level_order [:debug, :info, :notice, :warning, :error, :critical, :alert, :emergency]

  def mount(opts, term) do
    max_entries = Keyword.get(opts, :max_entries, 1000)
    {:ok, _collector} = Breeze.LoggerCollector.ensure_started(max_entries: max_entries)
    :ok = Breeze.LoggerCollector.subscribe(self())

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
       lines: []
     )}
  end

  def render(assigns) do
    ~H"""
    <box style={"width-#{@width}"}>
      <box style="bold">{@title}</box>
      <box>{@helper_text}</box>
      <box
        id="logger"
        focusable
        implicit={Breeze.Implicit.Scroll}
        scroll-autoscroll="bottom"
        style={"border-rounded overflow-scroll scrollbar-arrows focus:border-4 width-#{@width} height-#{@height}"}
      >
        <box :for={entry <- @lines} style={entry.style}>{entry.line}</box>
      </box>
    </box>
    """
  end

  def handle_event(_, %{"key" => key}, %{assigns: %{clear_key: key}} = term)
      when is_binary(key) do
    :ok = Breeze.LoggerCollector.clear()
    {:noreply, assign(term, lines: [])}
  end

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info({:logger_snapshot, entries}, term) do
    {:noreply, assign(term, lines: filter_entries(entries, term.assigns))}
  end

  def handle_info({:logger_entry, entry}, term) do
    {:noreply, assign(term, lines: append_entry(term.assigns.lines, entry, term.assigns))}
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
