defmodule FixedExample do
  use Breeze.View

  def mount(_opts, term), do: {:ok, term}

  def render(assigns) do
    ~H"""
    <box style="width-screen height-screen border">
      <box style="bold">Fixed Positioning</box>
      <box>Normal content still flows from the top-left.</box>
      <box style="absolute right-2 top-3 text-3">absolute right-2 top-3</box>
      <box style="fixed right-0 bottom-0 width-18 height-4 border bg-0">
        <box style="bold">fixed</box>
        <box>right-0 bottom-0</box>
      </box>
    </box>
    """
  end

  def handle_event(_, _, term), do: {:noreply, term}
  def handle_info(_, term), do: {:noreply, term}
end

Breeze.Example.run(
  [
    view: FixedExample,
    global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
