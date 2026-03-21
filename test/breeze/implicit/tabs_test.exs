defmodule Breeze.Implicit.TabsTest do
  use ExUnit.Case, async: true

  alias Breeze.Implicit.Tabs

  defmodule ClickableTabsView do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, assign(term, selected_tab: "overview")}

    def render(assigns) do
      ~H"""
      <.tabs
        id="tabs"
        selected={@selected_tab}
        br-change="select_tab"
        style="width-24 height-6"
        item_class="selected:bg-primary selected:text selected:bold width-10"
      >
        <:tab value="overview" label="Overview">
          <.scroll id="tabs-panel-overview" class="width-full height-full">
            <box>overview</box>
          </.scroll>
        </:tab>
        <:tab value="details" label="Details">
          <.scroll id="tabs-panel-details" class="width-full height-full">
            <box>details</box>
          </.scroll>
        </:tab>
      </.tabs>
      """
    end

    def handle_event("select_tab", %{value: value}, term) do
      {:noreply, assign(term, selected_tab: value)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  describe "init/3" do
    test "uses the root selected tab when provided" do
      children = [
        %{:"tab-label" => "Overview", value: "overview"},
        %{:"tab-label" => "Details", value: "details"}
      ]

      state = Tabs.init(children, %{:"tab-selected" => "details"}, %{})

      assert state.selected == "details"
      assert state.selected_index == 1
    end
  end

  describe "handle_event/3" do
    test "ignores horizontal navigation when there are no tabs" do
      state = %{
        values: [],
        widths: [],
        selected: nil,
        selected_index: 0,
        offset_x: 0,
        viewport_width: 20
      }

      assert Tabs.handle_event(nil, %{"key" => "ArrowRight"}, state) == {:noreply, state}
      assert Tabs.handle_event(nil, %{"key" => "ArrowLeft"}, state) == {:noreply, state}
    end

    test "delegates vertical navigation keys to the active panel target" do
      state = %{
        values: ["overview", "details"],
        widths: [10, 9],
        selected: "overview",
        selected_index: 0,
        offset_x: 0,
        viewport_width: 20,
        delegate_target: "panel-overview",
        target_prefix: "tabs-tab-"
      }

      assert Tabs.handle_event(nil, %{"key" => "ArrowDown"}, state) ==
               {{:delegate, "panel-overview"}, state}

      assert Tabs.handle_event(nil, %{"key" => "PageDown"}, state) ==
               {{:delegate, "panel-overview"}, state}
    end

    test "repeated horizontal navigation computes scroll offsets without crashing" do
      state = %{
        values: [
          "overview",
          "requests",
          "responses",
          "headers",
          "cookies",
          "timeline",
          "inspector",
          "settings",
          "shortcuts",
          "advanced"
        ],
        widths:
          Enum.map(
            ~w(Overview Requests Responses Headers Cookies Timeline Inspector Settings Shortcuts Advanced),
            &(String.length(&1) + 2)
          ),
        selected: "overview",
        selected_index: 0,
        offset_x: 0,
        viewport_width: 38,
        delegate_target: "panel-overview",
        target_prefix: "tabs-tab-"
      }

      final_state =
        Enum.reduce(1..20, state, fn _, acc ->
          assert {{:change, _payload}, next_state} =
                   Tabs.handle_event(nil, %{"key" => "ArrowRight"}, acc)

          next_state
        end)

      assert is_integer(final_state.offset_x)
      assert final_state.offset_x >= 0
    end

    test "selects a tab when its label is clicked" do
      state = %{
        values: ["overview", "details"],
        widths: [10, 9],
        selected: "overview",
        selected_index: 0,
        offset_x: 0,
        viewport_width: 20,
        delegate_target: "panel-overview",
        target_prefix: "tabs-tab-"
      }

      assert {{:change, %{value: "details", index: 1}}, next_state} =
               Tabs.handle_event(
                 nil,
                 %{"mouse" => %{button: :left, action: :press}, "target" => "tabs-tab-details"},
                 state
               )

      assert next_state.selected == "details"
      assert next_state.selected_index == 1
    end

    test "clicking a rendered tab label updates the selected tab" do
      terminal = %Termite.Terminal{size: %{width: 30, height: 10}}
      {:ok, pid} = Breeze.ChildServer.start(view: ClickableTabsView, terminal: terminal)

      assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
      state = :sys.get_state(pid)

      bounds = state.mouse_targets["tabs-tab-details"]
      x = div(bounds.left + bounds.right, 2) + 1
      y = div(bounds.top + bounds.bottom, 2) + 1

      assert {_status, _focused, _changed} =
               Breeze.ChildServer.dispatch_input(pid, %{
                 "mouse" => %{button: :left, action: :press, x: x, y: y, modifiers: []}
               })

      assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
      assert box.content =~ "details"

      assert %{implicit_state: %{"tabs" => {Breeze.Implicit.Tabs, state}}} =
               Breeze.ChildServer.metadata(pid)

      assert state.selected == "details"
    end
  end
end
