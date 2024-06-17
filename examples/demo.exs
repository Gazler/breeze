defmodule Demo do
  use Breeze.View

  def mount(_opts, term) do
    Process.send_after(self(), :tick, 200)
    {:ok, assign(term, name: "world", test: "foo")}
  end

  def render(assigns) do
    ~H"""
    <box style={%{bold: @name == :world, foreground_color: :rand.uniform(8)}}>
      <.announce a="b" name={@name} another={@name}>
        <%= @test %>
      </.announce>
    </box>
    """
  end

  def announce(assigns) do
    ~H"""
      Hello <%= @name %>
      <%= render_slot(@inner_block) %>
      <.more />
    """
  end

  def more(assigns) do
    ~H"""
      <.box>More things</.box>
    """
  end

  def handle_info(:tick, term) do
    name = if term.assigns.name == "world", do: "elixir", else: "world"
    Process.send_after(self(), :tick, 200)
    {:noreply, assign(term, name: name)}
  end
end

Demo.render(%{name: "lol", test: "foo"})
|> IO.inspect
#:timer.sleep(5000)
