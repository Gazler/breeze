{:ok, handler_config} = :logger.get_handler_config(:default)

updated_config =
  handler_config
  |> Map.update!(:config, fn config ->
    Map.put(config, :type, :standard_error)
  end)

:ok = :logger.remove_handler(:default)
:ok = :logger.add_handler(:default, :logger_std_h, updated_config)

defmodule Breeze.List do
  def init(children, last_state) do
    %{values: Enum.map(children, &(&1.value)), selected: last_state[:selected]}
  end

  def handle_event(_, %{"key" => "ArrowDown"}, %{values: values} = state) do
    index = Enum.find_index(values, &(&1 == state.selected))
    value = if index, do: Enum.at(values, index + 1) || hd(values), else: hd(values)
    {{:change, %{value: value}}, %{state | selected: value}}
  end

  def handle_event(_, %{"key" => "ArrowUp"}, %{values: values} = state) do
    index = Enum.find_index(values, &(&1 == state.selected))
    first = hd(Enum.reverse(values))
    value = if index, do: Enum.at(values, index - 1) || first, else: first
    {{:change, %{value: value}}, %{state | selected: value}}
  end

  def handle_event(_, _, state), do: state.selected

  def handle_modifiers(flags, state) do
    if state.selected == Keyword.get(flags, :value) do
      [selected: true]
    else
      []
    end
  end
end

defmodule Focus do
  use Breeze.View

  def mount(_opts, term) do
    {:ok, assign(term, last_value: "none")}
  end

  def render(assigns) do
    ~H"""
    <box id="lol">
      <box style="inline border focus:border-3" focusable id="base">
        <.list :for={id <- ["l1", "l2", "l3", "l4", "l5"]} br-change="change" id={id}>
          <:item value="hello">Hello</:item>
          <:item value="world">World</:item>
          <:item value="foo">Foo</:item>
        </.list>
      </box>

      <box style="inline border focus:border-3" focusable id="basel">
        <.list :for={id <- ["ll1", "ll2", "ll3", "ll4", "ll5"]} id={id}>
          <:item value="hello">Hello</:item>
          <:item value="world">World</:item>
          <:item value="foo">Foo</:item>
        </.list>
      </box>
      <box><%= @last_value %></box>
    </box>
    """
  end

  attr(:id, :string, required: true)
  attr(:rest, :global)

  slot :item do
    attr(:value, :string, required: true)
  end

  def list(assigns) do
    ~H"""
    <box focusable style="border focus:border-3" implicit={Breeze.List} id={@id} {@rest}>
      <%= for item <- @item do %>
        <box
          value={item.value}
          style="selected:bg-24 selected:text-0 focus:selected:text-7 focus:selected:bg-4"
        ><%= render_slot(item, %{}) %></box>
      <% end %>
    </box>
    """
  end

  def handle_info(_, term) do
    {:noreply, term}
  end

  def handle_event("change", %{value: value}, term) do
    {:noreply, assign(term, last_value: value)}
  end

  def handle_event(_, _, term) do
    {:noreply, term}
  end
end


Breeze.Server.start_link(view: Focus, hide_cursor: false)
:timer.sleep(100_000)
