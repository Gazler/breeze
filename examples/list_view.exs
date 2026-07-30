defmodule ListViewDemo do
  use Breeze.View
  import Breeze.Blocks

  @large_item_count 10_000

  def mount(_opts, term) do
    {:ok,
     term
     |> focus("languages")
     |> assign(
       large_items: 1..@large_item_count,
       mode: :default,
       selected: nil
     )}
  end

  def render(assigns) do
    ~H"""
    <box class="grid grid-cols-1 grid-rows-3 w-screen h-screen">
      <box class="h-3 pl-1 pr-1">
        <box class="font-bold">List view demo</box>
        <box>{mode_label(@mode)}</box>
        <box class="text-muted">Press v to toggle between lists.</box>
      </box>
      <box class="h-full pl-1 pr-1">
        <.list :if={@mode == :default} id="languages" br-change="change" class="focus:border-1 w-32">
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
        <.list
          :if={@mode == :virtual}
          id="large-list"
          br-change="change"
          virtual
          class="focus:border-1 w-full h-full"
        >
          <:item :for={index <- @large_items} value={to_string(index)}>Item {index}</:item>
        </.list>
      </box>
      <box class="h-2 w-full bg-panel overflow-hidden">
        <box class="h-1 pl-1">Selected: {@selected || "none"}</box>
        <.keybinding_bar keybindings={@breeze.keybindings} class="h-1 w-full pl-1"/>
      </box>
    </box>
    """
  end

  def handle_event("change", %{value: value}, term), do: {:noreply, assign(term, selected: value)}
  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(_, term), do: {:noreply, term}

  def toggle_list(_event, term) do
    {mode, focused} =
      case term.assigns.mode do
        :default -> {:virtual, "large-list"}
        :virtual -> {:default, "languages"}
      end

    {:noreply, term |> assign(mode: mode, selected: nil) |> focus(focused)}
  end

  defp mode_label(:default), do: "Default list (9 items)"
  defp mode_label(:virtual), do: "Virtual list (#{@large_item_count} items)"
end

Breeze.Example.run(
  [
    view: ListViewDemo,
    mouse: true,
    global_keybindings: [
      {"v", "Toggle list", &ListViewDemo.toggle_list/2},
      {"q", "Quit", fn _event, term -> {:stop, term} end}
    ]
  ],
  keep_alive: :infinity
)
