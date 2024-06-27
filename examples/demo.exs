defmodule Demo do
  use Breeze.View

  def mount(_opts, term) do
    Process.send_after(self(), :tick, 200)
    {:ok, assign(term, name: "world")}
  end

  def render(assigns) do
    ~H"""
    <box>
      <box style="bold">This is a thing</box>
      <.announce :for={x <- [1, 2, 3]} name={@name} index={x} />
      <box>And I'm after</box>
    </box>
    """
  end

  def announce(assigns) do
    ~H"""
    <box style={"bg-#{:rand.uniform(8)} absolute left-0 top-#{@index}"}>
      hello <%= @name %> <%= @index %>
    </box>
    """
  end

  def handle_info(:tick, term) do
    name = if term.assigns.name == "world", do: "elixir", else: "world"
    Process.send_after(self(), :tick, 200)
    {:noreply, assign(term, name: name)}
  end

  def handle_info(_, term) do
    {:noreply, term}
  end
end

# Breeze.Renderer.render(Demo, %{name: "hello"})

Breeze.Server.start_link(view: Demo)
:timer.sleep(5000)
