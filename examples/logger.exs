require Logger

defmodule LoggerExample do
  use Breeze.View
  import Breeze.Blocks
  alias Breeze.IO

  @calls [:puts, :inspect, :debug, :info, :notice, :warning, :error]

  def mount(_opts, term) do
    send(self(), :emit_log)

    {:ok,
     term
     |> assign(log_count: 0, last_level: "waiting", show_logs: false)
     |> put_local_keybindings([{"l", "Emit log"}])}
  end

  def render(assigns) do
    ~H"""
    <box class="grid grid-cols-1 grid-rows-2 width-screen height-screen bg">
      <box :if={!@show_logs} class="width-full height-full padding-2">
        <box class="width-full bold text-primary">Logger inspector example</box>
        <box class="width-full">
        </box>
        <box class="width-full">This application emits output every second.</box>
        <box class="width-full">It rotates through Logger, IO.puts, and IO.inspect calls.</box>
        <box class="width-full">IO.inspect uses IEx-style pretty printing and syntax colors.</box>
        <box class="width-full">Press l to emit another entry immediately.</box>
        <box class="width-full">
        </box>
        <box class="width-full text-muted">Run the remote inspector in another shell:</box>
        <box class="width-full">mix breeze.inspector</box>
        <box class="width-full text-muted">The Logs tab shows this node's captured output.</box>
        <box class="width-full">
        </box>
        <box class="inline width-full">
          <box class="width-14 text-muted">entries</box>
          <box>{@log_count}</box>
        </box>
        <box class="inline width-full">
          <box class="width-14 text-muted">last call</box>
          <box>{@last_level}</box>
        </box>
      </box>
      <live
        :if={@show_logs}
        id="local-logs"
        view={Breeze.Logger}
        start_opts={[title: "Local application logs", width: :screen, height: :full, max_lines: 1000]}
        class="width-full height-full"
      >
      </live>
      <box class="height-1 width-full overflow-hidden bg-emphasize-12">
        <.keybinding_bar
          keybindings={@breeze.keybindings}
          class="inline width-full height-1 overflow-hidden bg-emphasize-12 padding-left-1 padding-right-1"
        />
      </box>
    </box>
    """
  end

  def handle_event(_, %{"key" => "l"}, term), do: {:noreply, emit_log(term)}
  def handle_event(_, _, term), do: {:noreply, term}

  def toggle_logs(_event, term) do
    show_logs = !term.assigns.show_logs
    focused = if show_logs, do: "local-logs::logger", else: nil
    {:noreply, term |> assign(show_logs: show_logs) |> focus(focused)}
  end

  def handle_info(:emit_log, term) do
    Process.send_after(self(), :emit_log, 1_000)
    {:noreply, emit_log(term)}
  end

  def handle_info(_, term), do: {:noreply, term}

  defp emit_log(term) do
    count = term.assigns.log_count + 1
    call = Enum.at(@calls, rem(count - 1, length(@calls)))

    case call do
      :puts ->
        IO.puts("Breeze.IO.puts example entry=#{count}")

      :inspect ->
        IO.inspect(
          %{entry: count, source: __MODULE__, values: Enum.to_list(1..5)},
          label: "Breeze.IO.inspect example",
          width: 32
        )

      level ->
        Logger.log(level, "Logger example level=#{level} entry=#{count}")
    end

    assign(term, log_count: count, last_level: to_string(call))
  end
end

Breeze.Example.run(
  [
    view: LoggerExample,
    logger: :replace,
    inspector: true,
    global_keybindings: [
      {"t", "Toggle logs", &LoggerExample.toggle_logs/2},
      {"q", "Quit", fn _event, term -> {:stop, term} end}
    ]
  ],
  keep_alive: :infinity
)
