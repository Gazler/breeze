defmodule Breeze.List do
  def init(children, last_state) do
    values =
      children
      |> Enum.filter(&Map.has_key?(&1, :value))
      |> Enum.map(&(&1.value))

    %{values: values, selected: last_state[:selected], offset: last_state[:offset] || 0, length: length(values)}
  end

  def handle_event(_, %{"key" => "ArrowDown", "element" => element}, %{offset: offset, values: values} = state) do
    index = Enum.find_index(values, &(&1 == state.selected))
    value = if index, do: Enum.at(values, index + 1) || :reset, else: :reset
    offset = offset_calc(:down, offset, index, element)
    {value, offset} = if value == :reset, do: {hd(values), 0}, else: {value, offset}
    index = Enum.find_index(values, &(&1 == value))
    {{:change, %{offset: offset, index: index, value: value}}, %{state | selected: value, offset: offset}}
  end

  def handle_event(_, %{"key" => "ArrowUp", "element" => element}, %{offset: offset, values: values} = state) do
    index = Enum.find_index(values, &(&1 == state.selected))
    first = hd(Enum.reverse(values))
    value = if index, do: Enum.at(values, index - 1) || first, else: first
    offset = if value == first, do: length(values) - element.height, else: offset_calc(:up, offset, index, element)
    index = Enum.find_index(values, &(&1 == value))
    {{:change, %{offset: offset, index: index, value: value}}, %{state | selected: value, offset: offset}}
  end

  def handle_event(_, _, state), do: {:noreply, state}

  def handle_modifiers(:child, flags, state) do
    if state.selected == Keyword.get(flags, :value) do
      [selected: true]
    else
      []
    end
  end

  def handle_modifiers(:root, flags, state) do
    [style: "offset-top-#{state.offset}"]
  end

  # index = 9
  # content_height = 13
  # height = 8
  # clamp = 4

  defp offset_calc(:down, offset, index, element) do
    offset =
    if index && index > (element.height - clamp()) && index <= element.content_height - clamp() - 1 && offset - index < clamp()  do
      offset + 1
    else
      offset
    end

    max(0, min(offset, element.content_height - element.height - 1))
  end

  # index = 12
  # content_height = 13
  # height = 8
  # clamp = 4
  # offset = 5

  defp offset_calc(:up, offset, index, element) do
    offset =
    if index && (element.height + index - clamp() + 2 >= element.content_height) && offset - index < clamp()  do
      offset
    else
      offset - 1
    end

    max(offset, 0)
  end

  defp clamp(), do: 4
end



defmodule Docs do
  use Breeze.View

  def mount(_opts, term) do
    {:ok, docs} = :application.get_key(:phoenix, :modules)

    term =
      term
      |> focus("docs")
      |> assign(docs: docs, functions: nil, selected: nil, mod_total: length(docs), mod_index: 0, mod_offset: 0, fun_offset: 0, fun_total: 0, fun_index: 0)

    {:ok, term}
  end

  # TODO: add implicit here

  def render(assigns) do
    ~H"""
    <box style="inline">
      <.list id="docs" br-change="change" index={@mod_index} total={@mod_total} offset={@mod_offset}>
      <:item :for={doc <- @docs} value={doc}><%= inspect(doc) %></:item>
      </.list>
      <.list id="functions" br-change="function" :if={@selected} index={@fun_index} total={@fun_total} offset={@fun_offset}>
      <:item :for={function <- @functions} value={function}><%= function %></:item>
      </.list>
    </box>
    """
  end


  attr(:id, :string, required: true)
  attr(:rest, :global)
  attr(:index, :integer)
  attr(:total, :integer)
  attr(:offset, :integer)

  slot :item do
    attr(:value, :string, required: true)
  end

  def list(assigns) do
    ~H"""
    <box focusable style="border height-screen overflow-hidden width-32 focus:border-3" implicit={Breeze.List} id={@id} {@rest}>
        <box style="absolute left-2 top-0"><%= @index + 1 %>/<%= @total %> (Offset: <%= @offset %>)</box>
        <box
          :for={item <- @item}
          value={item.value}
          style="selected:bg-24 selected:text-0 focus:selected:text-7 focus:selected:bg-4 width-32 overflow-hidden"
        ><%= render_slot(item, %{}) %></box>
    </box>
    """
  end

  def handle_info(_, term) do
    {:noreply, term}
  end

  def handle_event("change", %{value: value, index: index, offset: offset}, term) do
    term =
      case Code.fetch_docs(String.to_existing_atom(value)) do
        {:docs_v1, _, :elixir, _, _, _, props} ->
          funs =
          Enum.reduce(props, [], fn prop, acc ->
            head = elem(prop, 0)
            case head do
              {:function, fun, arity} -> ["#{fun}/#{arity}" | acc]
              _ -> acc
            end
          end)

          assign(term, functions: Enum.reverse(funs), selected: value, fun_total: length(funs), mod_index: index, mod_offset: offset)

        _ -> term
      end

    {:noreply, term}
  end

  def handle_event("function", %{value: value, index: index, offset: offset}, term) do
    term = assign(term, fun_index: index, fun_offset: offset)
    {:noreply, term}
  end

  def handle_event(_, _, term), do: {:noreply, term}
end

Breeze.Server.start_link(view: Docs)
:timer.sleep(100_000)
