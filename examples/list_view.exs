defmodule ListViewDemo do
  use Breeze.View
  import Breeze.Blocks

  def mount(_opts, term) do
    {:ok, term |> focus("languages") |> assign(selected: nil)}
  end

  def render(assigns) do
    ~H"""
    <box>
      <.list id="languages" br-change="change" style="focus:border-1 width-32">
        <:item value="elixir">Elixir</:item>
        <:item value="erlang">Erlang</:item>
        <:item value="rust">Rust</:item>
        <:item value="go">Go</:item>
        <:item value="zig">Zig</:item>
        <:item value="python">Python</:item>
        <:item value="lua">Lua</:item>
        <:item value="gleam">Gleam</:item>
        <:item value="haskell">Haskell</:item>
      </.list>
      <box :if={@selected} style="border width-24">Selected: {@selected}</box>
    </box>
    """
  end

  def handle_event("change", %{value: value}, term), do: {:noreply, assign(term, selected: value)}
  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(_, term), do: {:noreply, term}
end

Breeze.Example.run(
  [
    view: ListViewDemo,
    global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
