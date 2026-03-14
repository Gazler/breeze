defmodule Demo do
  use Breeze.View

  def mount(_opts, term), do: {:ok, term}

  def render(assigns) do
    ~H"""
    <box style="grid grid-cols-2 grid-rows-3 width-screen height-screen">
      <box style="border border-1">Top Left</box>
      <box style="border border-2">Top Right</box>
      <box style="border border-3">Middle Left</box>
      <box style="border border-4">Middle Right</box>
      <box style="border border-5">Bottom Left</box>
      <box style="border border-6">Bottom Right</box>
    </box>
    """
  end

  def handle_event(_, _, term), do: {:noreply, term}
end

Breeze.Example.run(
  [
    view: Demo,
    global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
