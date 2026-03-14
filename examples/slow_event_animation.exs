defmodule SlowEventAnimationDemo do
  use Breeze.View

  def mount(_opts, term) do
    {:ok, assign(term, runs: 0, status: "Idle")}
  end

  def render(assigns) do
    ~H"""
    <box style="width-screen height-screen">
      <box style="bold">Async Server Demo</box>
      <box>
        This view blocks in handle_event/3 for three seconds, while the spinner implicit keeps animating.
      </box>
      <box style="height-1">
      </box>
      <box>Press r to start blocking work.</box>
      <box>Press q to quit.</box>
      <box style="height-1">
      </box>
      <box style="inline">
        <box id="spinner" implicit={Breeze.Implicit.AsyncSpinner} style="width-1">
        </box>
        <box style="width-2">
        </box>
        <box>Animation stays live during blocking work.</box>
      </box>
      <box>Completed runs: {@runs}</box>
      <box>Status: {@status}</box>
    </box>
    """
  end

  def handle_event(_, %{"key" => "r"}, term) do
    Process.sleep(3_000)
    runs = term.assigns.runs + 1
    {:noreply, assign(term, runs: runs, status: "Finished run #{runs}")}
  end

  def handle_event(_, _, term), do: {:noreply, term}
  def handle_info(_, term), do: {:noreply, term}
end

Breeze.Example.run(
  [
    view: SlowEventAnimationDemo,
    hide_cursor: true,
    global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
