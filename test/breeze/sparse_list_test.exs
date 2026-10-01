defmodule Breeze.SparseListTest do
  use ExUnit.Case, async: true
  alias Breeze.Test

  defmodule View do
    use Breeze.View
    import Breeze.Blocks

    def mount(_, term), do: {:ok, term |> focus("items") |> assign(selected: 0) |> window(0)}

    def render(assigns) do
      ~H"""
      <box class="width-screen height-screen">
        <.list
          id="items"
          virtual
          total={20000}
          start_index={@first}
          selected_index={@selected}
          list-selected={"item-#{@selected}"}
          loop={false}
          list-notify-scroll
          br-change="navigate"
          class="width-full height-full"
        >
          <:item :for={index <- @items} value={"item-#{index}"}>
            <box class="height-1">Row {index}</box>
          </:item>
        </.list>
      </box>
      """
    end

    def handle_event("navigate", %{action: :scroll, offset: offset}, term),
      do: {:noreply, window(term, offset)}

    def handle_event("navigate", %{index: index}, term),
      do: {:noreply, term |> assign(selected: index) |> window(index)}

    defp window(term, index) do
      first = max(div(index, 25) - 3, 0) * 25
      last = min((div(index, 25) + 4) * 25 - 1, 19_999)
      assign(term, first: first, items: first..last)
    end
  end

  test "End and Home use the full extent and render the destination immediately" do
    session = Test.start!(View, size: {80, 20})
    on_exit(fn -> Test.stop(session) end)
    assert Test.render_text!(session) =~ "Row 0"
    assert Test.element!(session, "items").content_height == 20_000
    Test.input(session, "End")
    assert Test.render_text!(session) =~ "Row 19999"
    {_, last} = Test.metadata(session).implicit_state["items"]
    assert last.selected_index == 19_999
    assert last.offset == 20_000 - last.viewport_height
    assert length(last.values) == 100
    assert Test.element!(session, "items").content_height == 20_000
    session = Test.resize(session, {80, 50})
    grown = Test.render_text!(session)
    assert grown =~ "Row 19952"
    assert grown =~ "Row 19999"
    Test.input(session, "Home")
    assert Test.render_text!(session) =~ "Row 0"
    {_, first} = Test.metadata(session).implicit_state["items"]
    assert first.offset == 0
    assert length(first.values) == 100
  end

  test "wheel, resize and page navigation keep absolute positions with a bounded row set" do
    session = Test.start!(View, size: {80, 20})
    on_exit(fn -> Test.stop(session) end)
    Test.wheel(session, "items", :down, repeat: 10_000)
    screen = Test.render_text!(session)
    assert screen =~ "Row 10000"
    assert screen == Test.render_text!(session)
    {_, state} = Test.metadata(session).implicit_state["items"]
    assert state.selected_index == 0
    assert state.selected == nil
    assert length(state.values) == 175
    session = Test.resize(session, {80, 50})
    assert Test.render_text!(session) =~ "Row 10040"
    Test.input(session, "End")
    Test.render!(session)
    {_, last} = Test.metadata(session).implicit_state["items"]
    Test.input(session, "PageUp")
    assert Test.render_text!(session) =~ "Row #{19_999 - last.viewport_height + 1}"
    {_, prior} = Test.metadata(session).implicit_state["items"]
    assert prior.selected_index == 19_999 - last.viewport_height + 1
  end
end
