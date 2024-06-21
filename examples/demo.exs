defmodule Demo do
  use Breeze.View

  def mount(_opts, term) do
    Process.send_after(self(), :tick, 200)
    {:ok, assign(term, name: "world")}
  end

  def render(assigns) do
    ~H"""
    <box>
      <box style={style(%{bold: true})}>
      This is a thing
      </box>
      <.announce :for={x <- [1, 2, 3]} name={@name} index={x} />
      <box>
        And I'm after
      </box>
    </box>
    """
  end

  def announce(assigns) do
    ~H"""
    <box style={style(%{background_color: :rand.uniform(8), position: :absolute, left: 5, top: @index})}>
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
