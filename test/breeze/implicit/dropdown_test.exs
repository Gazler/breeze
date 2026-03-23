defmodule Breeze.Implicit.DropdownTest do
  use ExUnit.Case, async: true

  alias Breeze.Implicit.Dropdown

  defmodule DropdownView do
    use Breeze.View
    import Breeze.Blocks

    def mount(_, term) do
      {:ok, focus(term, "method") |> assign(method: "POST", methods: ["GET", "POST", "PUT"])}
    end

    def render(assigns) do
      ~H"""
      <box style="width-screen height-screen">
        <.dropdown
          id="method"
          selected={@method}
          br-change="method_changed"
          class="bg-primary text-background bold focus:inverse width-10"
        >
          <:item :for={method <- @methods} value={method}>{" #{method}"}</:item>
        </.dropdown>
      </box>
      """
    end

    def handle_event(_, %{"key" => "\x14"}, term) do
      term =
        update_implicit(term, "method", fn
          {Breeze.Implicit.Dropdown, state} -> Breeze.Implicit.Dropdown.open(state)
          {_mod, state} -> state
        end)

      {:noreply, focus(term, "method")}
    end

    def handle_event(_, _, term), do: {:noreply, term}
  end

  defmodule GridDropdownView do
    use Breeze.View
    import Breeze.Blocks

    def mount(_, term) do
      {:ok, focus(term, "method") |> assign(method: "POST", methods: ["GET", "POST", "PUT"])}
    end

    def render(assigns) do
      ~H"""
      <box style="width-screen height-screen">
        <box style="grid grid-cols-3 height-1">
          <.dropdown
            id="method"
            selected={@method}
            br-change="method_changed"
            class="bg-primary text-background bold focus:inverse width-10"
          >
            <:item :for={method <- @methods} value={method}>{" #{method}"}</:item>
          </.dropdown>
          <box>{" filler "}</box>
          <box>{" tail "}</box>
        </box>
      </box>
      """
    end

    def handle_event(_, %{"key" => "\x14"}, term) do
      term =
        update_implicit(term, "method", fn
          {Breeze.Implicit.Dropdown, state} -> Breeze.Implicit.Dropdown.open(state)
          {_mod, state} -> state
        end)

      {:noreply, focus(term, "method")}
    end

    def handle_event(_, _, term), do: {:noreply, term}
  end

  test "opens on enter and selects the highlighted item" do
    children = [
      %{:"dropdown-item" => true, value: "GET"},
      %{:"dropdown-item" => true, value: "POST"},
      %{:"dropdown-item" => true, value: "PUT"}
    ]

    state = Dropdown.init(children, %{:"dropdown-selected" => "POST"}, %{})

    assert {:noreply, open_state} = Dropdown.handle_event(nil, %{"key" => "Enter"}, state)
    assert open_state.open? == true
    assert open_state.highlighted_index == 1

    assert {:noreply, moved_state} =
             Dropdown.handle_event(nil, %{"key" => "ArrowDown"}, open_state)

    assert moved_state.highlighted_index == 2

    assert {{:change, %{value: "PUT", index: 2}}, selected_state} =
             Dropdown.handle_event(nil, %{"key" => "Enter"}, moved_state)

    assert selected_state.open? == false
    assert selected_state.selected == "PUT"
    assert selected_state.selected_index == 2
  end

  test "selecting an item keeps focus on the dropdown in the child server" do
    terminal = %Termite.Terminal{size: %{width: 40, height: 12}}
    {:ok, pid} = Breeze.ChildServer.start(view: DropdownView, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "method", true} = Breeze.ChildServer.dispatch_input(pid, "\x14")
    assert {:noreply, "method", true} = Breeze.ChildServer.dispatch_input(pid, "Enter")

    metadata = Breeze.ChildServer.metadata(pid)
    assert metadata.focused == "method"
  end

  test "item modifiers collapse the items when closed" do
    state = %{
      values: ["GET"],
      selected: "GET",
      selected_index: 0,
      highlighted_index: 0,
      open?: false,
      menu_width: 12,
      menu_height: 3
    }

    assert [style: "absolute left-0 top-0 width-0 height-0 overflow-hidden layer-21"] =
             Dropdown.handle_modifiers(:child, [{:"dropdown-item", true}, {:value, "GET"}], state)
  end

  test "highlighted item gets selected modifier when open" do
    state = %{
      values: ["GET", "POST"],
      selected: "POST",
      selected_index: 1,
      highlighted_index: 1,
      open?: true,
      menu_width: 12,
      menu_height: 4
    }

    assert [selected: true, style: "absolute left-0 top-1 width-12 layer-21"] =
             Dropdown.handle_modifiers(
               :child,
               [{:"dropdown-item", true}, {:"dropdown-item-index", 0}, {:value, "POST"}],
               state
             )
  end

  test "full-width menu modifiers keep width-full when open" do
    state = %{
      values: ["GET", "POST"],
      selected: "POST",
      selected_index: 1,
      highlighted_index: 1,
      open?: true,
      menu_width: :full,
      menu_height: 4
    }

    assert [style: "absolute left-0 top-1 width-full height-4 overflow-hidden layer-20"] =
             Dropdown.handle_modifiers(:child, [{:"dropdown-frame", true}], state)

    assert [selected: true, style: "absolute left-0 top-2 width-full layer-21"] =
             Dropdown.handle_modifiers(
               :child,
               [{:"dropdown-item", true}, {:"dropdown-item-index", 1}, {:value, "POST"}],
               state
             )
  end

  test "indicator modifiers swap visibility based on open state" do
    closed_state = %{
      values: ["GET", "POST"],
      selected: "POST",
      selected_index: 1,
      highlighted_index: 1,
      open?: false,
      menu_width: 12,
      menu_height: 4
    }

    open_state = %{closed_state | open?: true}

    assert [style: "absolute right-1 top-0 width-1 height-1"] =
             Dropdown.handle_modifiers(
               :child,
               [{:"dropdown-indicator-closed", true}],
               closed_state
             )

    assert [style: "absolute right-1 top-0 width-0 height-0 overflow-hidden"] =
             Dropdown.handle_modifiers(:child, [{:"dropdown-indicator-open", true}], closed_state)

    assert [style: "absolute right-1 top-0 width-0 height-0 overflow-hidden"] =
             Dropdown.handle_modifiers(:child, [{:"dropdown-indicator-closed", true}], open_state)

    assert [style: "absolute right-1 top-0 width-1 height-1"] =
             Dropdown.handle_modifiers(:child, [{:"dropdown-indicator-open", true}], open_state)
  end

  test "ctrl-t is ignored by the dropdown implicit" do
    children = [
      %{:"dropdown-item" => true, value: "GET"},
      %{:"dropdown-item" => true, value: "POST"}
    ]

    state = Dropdown.init(children, %{:"dropdown-selected" => "POST"}, %{})
    assert {:noreply, ^state} = Dropdown.handle_event(nil, %{"key" => "\x14"}, state)
  end

  test "opened dropdown renders its menu items" do
    terminal = %Termite.Terminal{size: %{width: 40, height: 12}}
    {:ok, pid} = Breeze.ChildServer.start(view: DropdownView, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "method", true} = Breeze.ChildServer.dispatch_input(pid, "\x14")

    state = :sys.get_state(pid)

    assert {:ok, _acc, box} =
             Breeze.ChildServer.render(pid, focused: state.focused, terminal: terminal)

    assert box.content =~ "GET"
    assert box.content =~ "POST"
    assert box.content =~ "PUT"
    assert box.content =~ "▲"
  end

  test "closed dropdown renders the closed indicator without animate" do
    terminal = %Termite.Terminal{size: %{width: 40, height: 12}}
    {:ok, pid} = Breeze.ChildServer.start(view: DropdownView, terminal: terminal)

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert box.content |> String.graphemes() |> Enum.count(&(&1 == "▼")) == 1
    assert box.content =~ "▼"
    refute box.content =~ "▲"
  end

  test "opened dropdown still renders inside a grid row" do
    terminal = %Termite.Terminal{size: %{width: 40, height: 12}}
    {:ok, pid} = Breeze.ChildServer.start(view: GridDropdownView, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "method", true} = Breeze.ChildServer.dispatch_input(pid, "\x14")

    state = :sys.get_state(pid)

    assert {:ok, _acc, box} =
             Breeze.ChildServer.render(pid, focused: state.focused, terminal: terminal)

    assert box.content =~ "GET"
    assert box.content =~ "POST"
    assert box.content =~ "PUT"
  end
end
