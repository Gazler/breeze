defmodule Breeze.Viewport do
  def init(_children, last_state) do
    %{offset: last_state[:offset] || 0}
  end

  def handle_event(_, %{"key" => "ArrowDown", "element" => element}, %{offset: offset} = state) do
    offset = min(offset + 1, element.content_height - element.height - 1)
    {:noreply, %{state | offset: offset}}
  end

  def handle_event(_, %{"key" => "ArrowUp"}, %{offset: offset} = state) do
    {:noreply, %{state | offset: max(offset - 1, 0)}}
  end

  def handle_event(_, _, state) do
    {:noreply, state}
  end

  def handle_modifiers(:root, _flags, state) do
    if state.offset > 0 do
      [style: "offset-top-#{state.offset}"]
    else
      []
    end
  end
end


defmodule Scroll do
  use Breeze.View

  def mount(_opts, term) do
    {:ok, focus(term, "content-1")}
  end

  # TODO: add implicit here

  def render(assigns) do
    ~H"""
    <box>
      <box style="inline">
        <.viewport :for={id <- [1, 2, 3]} id={id}>Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.</.viewport>
      </box>
      <box style="border focus:border-3 height-2 overflow-hidden width-15" id="hello" focusable>I don't scroll even though I am long</box>
    </box>
    """
  end

  attr(:id, :string, required: true)
  attr(:rest, :global)

  slot :inner_block

  def viewport(assigns) do
    ~H"""
    <box style={"width-15 height-#{6 + @id} overflow-hidden border focus:border-3"} id={"content-#{@id}"} implicit={Breeze.Viewport} focusable><%= render_slot(@inner_block) %></box>
    """
  end

  def handle_info(_, term) do
    {:noreply, term}
  end

  def handle_event(_, _, term), do: {:noreply, term}
end

Breeze.Server.start_link(view: Scroll)
:timer.sleep(100_000)
