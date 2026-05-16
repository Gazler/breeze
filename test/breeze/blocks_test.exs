defmodule Breeze.BlocksTest do
  use ExUnit.Case, async: true

  alias Breeze.Blocks
  alias Breeze.ChildServer

  defmodule UnderlineTabsExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.tabs id="tabs" selected="overview" variant="underline" style="width-24 height-5">
        <:tab value="overview" label="Overview">
          <box>Overview body</box>
        </:tab>
        <:tab value="details" label="Details">
          <box>Details body</box>
        </:tab>
      </.tabs>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule HighlightTabsExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.tabs id="tabs" selected="overview" highlight="error" style="width-24 height-5">
        <:tab value="overview" label="Overview">
          <box>Overview body</box>
        </:tab>
        <:tab value="details" label="Details">
          <box>Details body</box>
        </:tab>
      </.tabs>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule PerTabHighlightTabsExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.tabs id="tabs" selected="details" highlight="accent" style="width-24 height-5">
        <:tab value="overview" label="Overview">
          <box>Overview body</box>
        </:tab>
        <:tab value="details" label="Details" highlight="error">
          <box>Details body</box>
        </:tab>
      </.tabs>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule ButtonExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.button id="confirm" class="width-10">Confirm</.button>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule PanelFocusWithinExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.panel id="panel" class="width-16 height-4">
        <:title>Details</:title>
        <.button id="confirm" class="width-10">{" Confirm "}</.button>
      </.panel>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule MutedListExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.list id="items" variant="muted" style="width-12 height-4" list-selected="two">
        <:item value="one">One</:item>
        <:item value="two">Two</:item>
        <:item value="three">Three</:item>
      </.list>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule UnicodeMarkerListExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.list
        id="items"
        variant="muted"
        selected-indicator="🏡"
        style="width-12 height-4"
        list-selected="two"
      >
        <:item value="one">One</:item>
        <:item value="two">Two</:item>
        <:item value="three">Three</:item>
      </.list>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule UnselectedListExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.list id="items" variant="muted" style="width-12 height-4">
        <:item value="one">One</:item>
        <:item value="two">Two</:item>
        <:item value="three">Three</:item>
      </.list>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule TableExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term) do
      {:ok, term |> focus("cities") |> assign(selected_city: "delhi")}
    end

    def render(assigns) do
      rows = [
        %{id: "tokyo", rank: "1", city: "Tokyo", country: "Japan", population: "37.2m"},
        %{id: "delhi", rank: "2", city: "Delhi", country: "India", population: "32.0m"},
        %{id: "shanghai", rank: "3", city: "Shanghai", country: "China", population: "28.5m"}
      ]

      assigns = assign(assigns, rows: rows)

      ~H"""
      <.table id="cities" rows={@rows} selected={@selected_city} br-change="city_changed">
        <:col :let={city} label="#" width={4} align="right">{city.rank}</:col>
        <:col :let={city} label="City" width={12}>{city.city}</:col>
        <:col :let={city} label="Country" width={12} align="center">{city.country}</:col>
        <:col :let={city} label="Pop." width={10} align={:right}>
          <box class="text-muted">{city.population}</box>
        </:col>
      </.table>
      """
    end

    def handle_event("city_changed", %{value: value}, term) do
      {:noreply, assign(term, selected_city: value)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  describe "merge_class/2" do
    test "matches merge_style semantics" do
      assert Blocks.merge_class("border width-24 height-8", "width-32 bg-4") ==
               "border width-32 height-8 bg-4"
    end
  end

  describe "merge_style/2" do
    test "nil override returns default unchanged" do
      assert Blocks.merge_style("border width-24", nil) == "border width-24"
    end

    test "empty string override returns default unchanged" do
      assert Blocks.merge_style("border width-24", "") == "border width-24"
    end

    test "override replaces a numeric-suffixed token" do
      assert Blocks.merge_style("border width-24 height-8", "width-32") ==
               "border width-32 height-8"
    end

    test "override replaces a non-numeric-suffixed token" do
      assert Blocks.merge_style("border overflow-scroll", "overflow-hidden") ==
               "border overflow-hidden"
    end

    test "new token from override is appended" do
      assert Blocks.merge_style("border width-24", "bg-4") == "border width-24 bg-4"
    end

    test "state-prefixed tokens are matched by their full prefix" do
      assert Blocks.merge_style("border focus:border-3", "focus:border-2") ==
               "border focus:border-2"
    end

    test "multiple overrides are applied in one call" do
      assert Blocks.merge_style(
               "border width-24 height-8 overflow-scroll focus:border-3",
               "width-32 focus:border-2"
             ) ==
               "border width-32 height-8 overflow-scroll focus:border-2"
    end
  end

  test "tabs supports an underline variant" do
    {:ok, pid} = ChildServer.start(view: UnderlineTabsExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "tabs", implicit_state: %{})

    assert box.content =~ "Overview"
    assert box.content =~ "Details"
    assert box.content =~ ~r/\e\[[0-9;]*38;5;4m/
    assert box.content =~ "48;5;4;"
    assert box.content =~ "Overview body"
  end

  test "tabs accepts a configurable highlight color" do
    {:ok, pid} = ChildServer.start(view: HighlightTabsExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "tabs", implicit_state: %{})

    assert box.content =~ "Overview"
    assert box.content =~ ~r/\e\[[0-9;]*38;5;1m/
    assert box.content =~ "48;5;1;"
    assert box.content =~ "Overview body"
  end

  test "tabs allow an individual tab highlight override" do
    {:ok, pid} = ChildServer.start(view: PerTabHighlightTabsExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "tabs", implicit_state: %{})

    assert box.content =~ "Overview"
    assert box.content =~ "Details"
    assert box.content =~ ~r/\e\[[0-9;]*38;5;5m/
    assert box.content =~ "48;5;1;"
    assert box.content =~ "Details body"
  end

  test "tabs render on the panel background by default" do
    {:ok, pid} =
      ChildServer.start(
        view: UnderlineTabsExample,
        start_opts: [],
        theme: Breeze.Theme.builtin(:gruvbox)
      )

    {:ok, _acc, box} = ChildServer.render(pid, implicit_state: %{})

    assert box.content =~ "48;2;50;48;47;"
  end

  test "button renders with primary styling and a focused inverse state" do
    {:ok, pid} = ChildServer.start(view: ButtonExample, start_opts: [])

    {:ok, acc, box} = ChildServer.render(pid, focused: "confirm", implicit_state: %{})

    assert acc.focusables == ["confirm"]
    assert box.content =~ "Confirm"
    assert box.content =~ ~r/\e\[[0-9;]*7;[0-9;]*m/
  end

  test "panel highlights when a descendant is focused" do
    {:ok, pid} = ChildServer.start(view: PanelFocusWithinExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "confirm", implicit_state: %{})

    assert box.content =~ "Confirm"
    assert box.content =~ "Details"
    assert box.content =~ ~r/\e\[[0-9;]*38;5;4m[╭│╰]/
    assert box.content =~ ~r/\e\[[0-9;]*38;5;4mDetails/
  end

  test "list can render muted while unfocused and restore active colors on focus" do
    {:ok, pid} =
      ChildServer.start(
        view: MutedListExample,
        start_opts: [],
        theme: Breeze.Theme.builtin(:gruvbox)
      )

    {:ok, _acc, unfocused_box} =
      ChildServer.render(pid, focused: nil, implicit_state: %{}, allow_unfocused: true)

    {:ok, _acc, focused_box} = ChildServer.render(pid, focused: "items", implicit_state: %{})

    assert unfocused_box.content =~ "Two"
    assert focused_box.content =~ "Two"
    assert unfocused_box.content =~ "48;2;40;40;40;"
    assert unfocused_box.content =~ "38;2;188;175;142"
    assert unfocused_box.content =~ "48;2;105;132;122;"
    assert focused_box.content =~ "38;2;131;165;152m┌"
    assert focused_box.content =~ "38;2;40;40;40m>Two"
  end

  test "list items render their labels" do
    {:ok, pid} = ChildServer.start(view: MutedListExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "items", implicit_state: %{})

    assert box.content =~ "One"
    assert box.content =~ "Two"
  end

  test "list supports wide unicode selected markers" do
    {:ok, pid} = ChildServer.start(view: UnicodeMarkerListExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "items", implicit_state: %{})

    assert box.content =~ "🏡Two"
    assert box.content =~ "  One"
  end

  test "list does not mark every item selected when nothing is selected" do
    {:ok, pid} = ChildServer.start(view: UnselectedListExample, start_opts: [])

    {:ok, _acc, box} =
      ChildServer.render(pid, focused: nil, implicit_state: %{}, allow_unfocused: true)

    refute box.content =~ ">One"
    refute box.content =~ ">Two"
    refute box.content =~ ">Three"
    assert box.content =~ " One"
    assert box.content =~ " Two"
  end

  test "table renders headers, rows, and selectable cells" do
    {:ok, pid} = ChildServer.start(view: TableExample, start_opts: [])

    {:ok, acc, box} = ChildServer.render(pid, focused: "cities", implicit_state: %{})

    assert acc.focusables == ["cities"]
    assert box.content =~ "City"
    assert box.content =~ "Tokyo"
    assert box.content =~ "Delhi"
    assert box.content =~ "India"
    assert box.content =~ ~r/\e\[[0-9;]*48;5;4/
  end

  test "table emits change events from keyboard navigation" do
    {:ok, pid} = ChildServer.start(view: TableExample, start_opts: [])

    assert {:ok, _acc, _box} = ChildServer.render(pid, focused: "cities", implicit_state: %{})
    assert {:noreply, "cities", true} = ChildServer.dispatch_input(pid, "ArrowDown")

    term = :sys.get_state(pid)
    assert term.assigns.selected_city == "shanghai"
  end
end
