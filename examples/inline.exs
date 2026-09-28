defmodule InlineDemo do
  use Breeze.View
  import Breeze.Blocks

  def mount(_opts, term) do
    {:ok,
     term
     |> switch_theme(:gruvbox)
     |> assign(entries: 0, lines: 0, latest: "Choose an action below.")
     |> focus("inline-info")}
  end

  def render(assigns) do
    ~H"""
    <box class="rounded p-1 w-screen">
      <box class="w-full font-bold">Inline Breeze · {@entries} entries / {@lines} lines</box>
      <box class="w-full text-muted">Write colored output to your terminal history.</box>
      <box class="w-full grid grid-cols-2 md:grid-cols-4 gap-x-1 pt-1">
        <.button id="inline-info" variant="bordered" class="w-full text-center">Info</.button>
        <.button
          id="inline-success"
          variant="bordered"
          highlight="success"
          class="w-full text-center border-success"
        >
          Success
        </.button>
        <.button
          id="inline-warning"
          variant="bordered"
          highlight="warning"
          class="w-full text-center border-warning"
        >
          Warning
        </.button>
        <.button
          id="inline-report"
          variant="bordered"
          highlight="secondary"
          class="w-full text-center border-secondary"
        >
          Report + link
        </.button>
      </box>
      <box class="w-full pt-1">{@latest}</box>
      <box class="w-full text-muted">Theme: {@breeze.theme.name} · F3: cycle theme</box>
      <box class="w-full text-muted">
        Tab / Shift+Tab: focus · Enter / Space: write · c: crash · q: quit
      </box>
    </box>
    """
  end

  def handle_event(_, %{"key" => key}, %{focused: focused} = term)
      when key in ["Enter", " "] do
    write_entry(focused, term)
  end

  def handle_event(_, %{"key" => "c"}, _term), do: raise("Intentional inline demo crash")
  def handle_event(_, %{"key" => "q"}, term), do: {:stop, term}
  def handle_event(_, _, term), do: {:noreply, term}

  defp write_entry(id, term)
       when id in ["inline-info", "inline-success", "inline-warning", "inline-report"] do
    entry = term.assigns.entries + 1
    {label, output} = entry_content(id, entry)
    lines = length(String.split(output, "\n"))

    color =
      case id do
        "inline-info" -> :primary
        "inline-success" -> :success
        "inline-warning" -> :warning
        "inline-report" -> :secondary
      end

    output =
      Termite.Style.ansi256()
      |> Termite.Style.foreground(Breeze.Theme.color(term.theme, color))
      |> Termite.Style.render_to_string(output)

    {:noreply,
     term
     |> append_scrollback(output)
     |> assign(
       entries: entry,
       lines: term.assigns.lines + lines,
       latest: "Last output: #{label} (#{lines} #{if lines == 1, do: "line", else: "lines"})"
     )}
  end

  defp write_entry(_id, term), do: {:noreply, term}

  defp entry_content("inline-info", entry),
    do: {"Info", "[info ##{entry}] Listening for the next request."}

  defp entry_content("inline-success", entry),
    do: {"Success", "[success ##{entry}] Request completed and saved."}

  defp entry_content("inline-warning", entry) do
    {"Warning",
     "[warning ##{entry}] A slow request will be retried. This longer message wraps across terminal rows while the buttons stay available below it."}
  end

  defp entry_content("inline-report", entry) do
    {"Report",
     Enum.join(
       [
         "[report ##{entry}] Sample run",
         "  Fetch data       done",
         "  Validate input   done",
         "  Save result      done",
         "  Result: 3 steps completed successfully.",
         "  Docs: \e]8;;https://hexdocs.pm/breeze/\e\\https://hexdocs.pm/breeze/\e]8;;\e\\"
       ],
       "\n"
     )}
  end
end

# Leave mouse reporting off so the terminal owns wheel scrollback and text selection.
Breeze.Example.run(
  view: InlineDemo,
  screen: :inline,
  reload: true,
  mouse: false,
  global_keybindings: [{"F3", "Theme", &Breeze.View.cycle_theme/2}]
)
