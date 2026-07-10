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
       lines: []
     )}
  end

  @impl Breeze.View
  def render(assigns) do
    ~H"""
    <box class={["bg overflow-hidden", width_style(@width)]}>
      <box class="bg bold width-full">{@title}</box>
      <box class="bg width-full">{@helper_text}</box>
      <box
        id="logger"
        focusable
        implicit={Breeze.Implicit.Scroll}
        scroll-autoscroll="bottom"
        class={"bg border-rounded width-full overflow-scroll scrollbar-arrows focus:border-4 #{height_style(@height)}"}
      >
        <box :for={entry <- @lines} style={entry.style}>{entry.line}</box>
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

  defp height_style(:full), do: "height-full"
  defp height_style("full"), do: "height-full"
  defp height_style(height), do: "height-#{height}"

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
