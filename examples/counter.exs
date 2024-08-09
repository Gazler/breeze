defmodule Demo do
  use Breeze.View

  def mount(_opts, term), do: {:ok, assign(term, counter: 0)}

  def render(assigns) do
    ~H"""
      <box style="text-5 bold">Counter: <%= @counter %></box>
    """
  end

  def handle_event(_, %{"key" => "ArrowUp"}, term), do:
    {:noreply, assign(term, counter: term.assigns.counter + 1)}

  def handle_event(_, %{"key" => "ArrowDown"}, term), do:
    {:noreply, assign(term, counter: term.assigns.counter - 1)}

  def handle_event(_, %{"key" => "q"}, term), do: {:stop, term}
  def handle_event(_, _, term), do: {:noreply, term}
end

Breeze.Server.start_link(view: Demo)
receive do
end
