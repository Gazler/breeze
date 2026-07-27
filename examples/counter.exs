defmodule Demo do
  use Breeze.View
  import Breeze.Blocks

  def mount(_opts, term) do
    {:ok,
     term
     |> assign(counter: 0)
     |> put_local_keybindings([
       {"ArrowUp", "Increment"},
       {"ArrowDown", "Decrement"}
     ])}
  end

  def render(assigns) do
    ~H"""
    <box class="grid grid-cols-1 grid-rows-2 w-screen h-screen">
      <box>
        <box class="text-5 font-bold">Counter: {@counter}</box>
      </box>
      <box class="h-1 bg-panel overflow-hidden">
        <.keybinding_bar keybindings={@breeze.keybindings}/>
      </box>
    </box>
    """
  end

  def handle_event(_, %{"key" => "ArrowUp"}, term),
    do: {:noreply, assign(term, counter: term.assigns.counter + 1)}

  def handle_event(_, %{"key" => "ArrowDown"}, term),
    do: {:noreply, assign(term, counter: term.assigns.counter - 1)}

  def handle_event(_, _, term), do: {:noreply, term}
end

Breeze.Example.run(
  [
    view: Demo,
    alt_screen: false,
    global_keybindings: [{"q", "Quit", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
