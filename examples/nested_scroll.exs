defmodule NestedScrollExample do
  use Breeze.View
  import Breeze.Blocks

  def mount(_opts, term) do
    {:ok, focus(term, "child-scroll")}
  end

  def render(assigns) do
    ~H"""
    <box class="grid grid-cols-1 grid-rows-2 w-screen h-screen bg">
      <box class="w-full h-4 px-1 border-b bg-panel overflow-hidden">
        <box class="font-bold text-primary">Nested scroll chaining</box>
        <box>At CHILD bottom, the current burst is flushed before PARENT takes over.</box>
        <box class="text-muted">
          Wheel gestures stay latched to one region · Tab changes focus · q quits
        </box>
      </box>
      <.scroll id="parent-scroll" class="w-full h-full bg focus:scrollbar-primary">
        <box class="w-full px-2 pt-1">
          <box class="font-bold">PARENT VIEWPORT</box>
          <box class="text-muted">This heading belongs to the parent scroll region.</box>
          <box>
          </box>
          <box class="w-full p-1 border-rounded border-stroke bg-panel">
            <box class="font-bold text-primary">CHILD VIEWPORT</box>
            <box class="text-muted">Keep the pointer inside this box while scrolling.</box>
            <.scroll
              id="child-scroll"
              class="w-full h-8 border-rounded border-stroke bg focus:border-primary focus:scrollbar-primary"
            >
              <box :for={index <- 1..13} class="h-1 px-1">Child row {pad(index)}</box>
              <box class="h-1 px-1 font-bold text-primary">CHILD BOTTOM · keep scrolling ↓</box>
            </.scroll>
          </box>
          <box>
          </box>
          <box class="font-bold">PARENT CONTINUES</box>
          <box class="text-muted">These rows move once the child reaches its edge.</box>
          <box :for={index <- 1..16} class="h-1">Parent row {pad(index)}</box>
          <box class="font-bold text-primary">PARENT BOTTOM</box>
        </box>
      </.scroll>
    </box>
    """
  end

  def handle_event(_, _, term), do: {:noreply, term}
  def handle_info(_, term), do: {:noreply, term}

  defp pad(index) do
    index
    |> Integer.to_string()
    |> String.pad_leading(2, "0")
  end
end

Breeze.Example.run(
  [
    view: NestedScrollExample,
    mouse: true,
    global_keybindings: [{"q", "Quit", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
