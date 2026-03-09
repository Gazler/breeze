defmodule Breeze.Implicit.TabsTest do
  use ExUnit.Case, async: true

  alias Breeze.Implicit.Tabs

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
        delegate_target: "panel-overview"
      }

      assert Tabs.handle_event(nil, %{"key" => "ArrowDown"}, state) ==
               {{:delegate, "panel-overview"}, state}

      assert Tabs.handle_event(nil, %{"key" => "PageDown"}, state) ==
               {{:delegate, "panel-overview"}, state}
    end
  end
end
