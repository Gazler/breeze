try do
  :ok = :logger.set_handler_config(:default, :level, :emergency)
rescue
  _ -> :ok
end

defmodule CrashHandlerExample do
  use Breeze.View

  @tick_ms 1_000

  def mount(_opts, term) do
    Process.send_after(self(), :tick, @tick_ms)
    {:ok, term |> assign(counter: 0) |> focus("boom")}
  end

  def render(assigns) do
    ~H"""
    <box style="width-screen height-screen">
      <box style="height-1 bold">Crash Handler Demo</box>
      <box style="height-1">
      </box>
      <box style="grid grid-cols-1 grid-rows-2 height-full">
        <box id="boom" focusable style="border-rounded width-32 height-3 focus:border-4">
          <box>Press c to raise</box>
          <box>Counter {@counter}</box>
        </box>
        <box style="height-1">
        </box>
        <box>q quits, r restarts after a crash</box>
        <box style="height-1">
        </box>
        <live
          id="logs"
          view={Breeze.Logger}
          start_opts={[title: "Captured logs", width: 72, height: 12, min_level: :debug, max_lines: 40, clear_key: nil]}
        >
        </live>
      </box>
    </box>
    """
  end

  def handle_event(_, %{"key" => "c"}, _term) do
    raise "crash demo"
  end

  def handle_event(_, %{"key" => "Enter"}, term) do
    {:noreply, assign(term, counter: term.assigns.counter + 1)}
  end

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(:tick, term) do
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, assign(term, counter: term.assigns.counter + 1)}
  end

  def handle_info(_, term), do: {:noreply, term}
end

Breeze.Example.run(
  view: CrashHandlerExample,
  hide_cursor: true,
  global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
)
