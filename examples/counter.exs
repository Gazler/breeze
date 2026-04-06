defmodule Demo do
  use Breeze.View
  import Breeze.Blocks

  def mount(_opts, term) do
    {:ok,
     term
     |> assign(counter: 0)
     |> put_local_keybindings([
       {"ArrowUp", "Increment"},
       {"ArrowDown", "Decrement"},
       {"q", "Quit"}
     ])}
  end

  def render(assigns) do
    ~H"""
    <box style="grid grid-cols-1 grid-rows-2 width-screen height-screen">
      <box>
        <box style="text-5 bold">Counter: {@counter}</box>
      </box>
      <box style="height-1 bg-panel overflow-hidden">
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
    global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
