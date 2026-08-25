defmodule Breeze.Implicit.DropdownTest do
  use ExUnit.Case, async: true

  import Breeze.TestSupport.ProcessHelpers, only: [start_child_server: 1]

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

  defmodule CoveredDropdownView do
    use Breeze.View
    import Breeze.Blocks

    def mount(_, term), do: {:ok, focus(term, "choice")}

    def render(assigns) do
      ~H"""
      <box class="width-screen height-screen">
        <.dropdown id="choice" selected="one" class="width-20">
          <:item value="one">One</:item>
          <:item value="two">Two</:item>
          <:item value="three">Three</:item>
        </.dropdown>
        <box id="covered" focusable class="absolute left-0 top-2 width-4 height-1">Base</box>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
  end

  defmodule PanelDropdownView do
    use Breeze.View
    import Breeze.Blocks

    def mount(_, term), do: {:ok, focus(term, "choice")}

    def render(assigns) do
      ~H"""
      <box>
        <.panel id="panel" class="width-72 height-21">
          <:title>Panel</:title>
          <box class="inline height-1">
            <box class="width-18">Starter</box>
            <.dropdown id="choice" selected="counter" class="width-32">
              <:item value="blank">Blank</:item>
              <:item value="counter">Counter</:item>
              <:item value="list">List</:item>
            </.dropdown>
          </box>
          <box class="padding-left-18 width-66">An interactive counter with keyboard controls.</box>
          <box class="height-1">
          </box>
          <box class="inline height-1">
            <box class="width-18">Theme</box>
            <.dropdown id="theme" selected="gruvbox" class="width-32">
              <:item value="dracula">Dracula</:item>
              <:item value="gruvbox">Gruvbox</:item>
              <:item value="system">System</:item>
            </.dropdown>
          </box>
        </.panel>
        <box id="footer">Footer</box>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
  end

  test "opens on enter and selects the highlighted item" do
    children = [
      %{:"dropdown-item" => true, value: "GET"},
      %{:"dropdown-item" => true, value: "POST"},
      %{:"dropdown-item" => true, value: "PUT"}
    ]

    {:ok, state} = Dropdown.init(children, %{:"dropdown-selected" => "POST"}, %{})

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

  test "selecting an item keeps focus on the dropdown" do
    session = Breeze.Test.start!(DropdownView, size: {40, 12})
    on_exit(fn -> Breeze.Test.stop(session) end)

    _ = Breeze.Test.render!(session)
    assert {:noreply, "method", true} = Breeze.Test.input(session, "\x14")
    assert {:noreply, "method", true} = Breeze.Test.input(session, "Enter")

    assert Breeze.Test.focused(session) == "method"
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

  test "an open dropdown raises its root above closed sibling dropdowns" do
    assert [style: "layer-40"] = Dropdown.handle_modifiers(:root, [], %{open?: true})
    assert [] = Dropdown.handle_modifiers(:root, [], %{open?: false})
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

    assert [selected: true, style: "absolute left-0 top-1 width-12 height-1 layer-21"] =
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

    assert [selected: true, style: "absolute left-0 top-2 width-full height-1 layer-21"] =
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

    {:ok, state} = Dropdown.init(children, %{:"dropdown-selected" => "POST"}, %{})
    assert {:noreply, ^state} = Dropdown.handle_event(nil, %{"key" => "\x14"}, state)
  end

  test "clicking the rendered trigger opens the dropdown" do
    session = Breeze.Test.start!(DropdownView, size: {40, 12})
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert {:noreply, "method", true} =
             Breeze.Test.click(session, "method")

    assert %{implicit_state: %{"method" => {Dropdown, %{open?: true}}}} =
             Breeze.Test.metadata(session)

    assert {:noreply, "method", true} =
             Breeze.Test.click(session, "method")

    assert %{implicit_state: %{"method" => {Dropdown, %{open?: false}}}} =
             Breeze.Test.metadata(session)
  end

  test "clicking a rendered item selects it and closes the dropdown" do
    session = Breeze.Test.start!(DropdownView, size: {40, 12})
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert {:noreply, "method", true} =
             Breeze.Test.click(session, "method")

    assert {:noreply, "method", true} =
             Breeze.Test.click(session, "method-item-2")

    assert %{
             implicit_state: %{
               "method" => {Dropdown, %{open?: false, selected: "PUT", selected_index: 2}}
             }
           } = Breeze.Test.metadata(session)
  end

  test "dropdown items win mouse hit testing over smaller covered controls" do
    terminal = %Termite.Terminal{size: %{width: 40, height: 12}}
    {:ok, pid} = start_child_server(view: CoveredDropdownView, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "choice", true} = Breeze.ChildServer.dispatch_input(pid, "Enter")
    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    state = :sys.get_state(pid)
    item_bounds = state.mouse_targets["choice-item-1"]
    covered_bounds = state.mouse_targets["covered"]
    x = max(item_bounds.left, covered_bounds.left)
    y = max(item_bounds.top, covered_bounds.top)

    assert x <= min(item_bounds.right, covered_bounds.right)
    assert y <= min(item_bounds.bottom, covered_bounds.bottom)

    assert {:noreply, "choice", true} =
             Breeze.ChildServer.dispatch_input(pid, %{
               "mouse" => %{
                 "button" => "left",
                 "action" => "press",
                 "x" => x,
                 "y" => y
               }
             })

    assert %{
             focused: "choice",
             implicit_state: %{
               "choice" => {Dropdown, %{open?: false, selected: "two", selected_index: 1}}
             }
           } = Breeze.ChildServer.metadata(pid)
  end

  test "opened dropdown renders its menu items" do
    session = Breeze.Test.start!(DropdownView, size: {40, 12})
    on_exit(fn -> Breeze.Test.stop(session) end)

    _ = Breeze.Test.render!(session)
    assert {:noreply, "method", true} = Breeze.Test.input(session, "\x14")

    content = Breeze.Test.render_text!(session)

    assert content =~ "GET"
    assert content =~ "POST"
    assert content =~ "PUT"
    assert content =~ "▲"
  end

  test "closed dropdown renders the closed indicator without animate" do
    session = Breeze.Test.start!(DropdownView, size: {40, 12})
    on_exit(fn -> Breeze.Test.stop(session) end)

    content = Breeze.Test.render_text!(session)

    assert content |> String.graphemes() |> Enum.count(&(&1 == "▼")) == 1
    assert content =~ "▼"
    refute content =~ "▲"
  end

  test "opened dropdown still renders inside a grid row" do
    session = Breeze.Test.start!(GridDropdownView, size: {40, 12})
    on_exit(fn -> Breeze.Test.stop(session) end)

    _ = Breeze.Test.render!(session)
    assert {:noreply, "method", true} = Breeze.Test.input(session, "\x14")

    content = Breeze.Test.render_text!(session)

    assert content =~ "GET"
    assert content =~ "POST"
    assert content =~ "PUT"
  end

  test "opening a dropdown does not expand its containing panel" do
    session = Breeze.Test.start!(PanelDropdownView, size: {80, 24})
    on_exit(fn -> Breeze.Test.stop(session) end)

    closed_panel = Breeze.Test.element!(session, "panel")
    closed_footer = Breeze.Test.element!(session, "footer")
    Breeze.Test.input(session, "Enter")
    opened = Breeze.Test.render_text!(session)
    opened_panel = Breeze.Test.element!(session, "panel")
    opened_footer = Breeze.Test.element!(session, "footer")

    assert opened =~ "Counter"
    assert opened =~ "List"
    refute opened =~ "An interactive"
    assert opened =~ "oard controls."
    assert opened =~ "Theme"

    theme_row = opened |> String.split("\n") |> Enum.find(&String.contains?(&1, "Theme"))
    assert theme_row =~ "List"
    refute theme_row =~ "Gruvbox"
    assert opened_panel.height == closed_panel.height
    assert opened_footer.top == closed_footer.top
  end
end
