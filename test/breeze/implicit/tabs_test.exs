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
        widths: Enum.map(~w(Overview Requests Responses Headers Cookies Timeline Inspector Settings Shortcuts Advanced), &(String.length(&1) + 2)),
        selected: "overview",
        selected_index: 0,
        offset_x: 0,
        viewport_width: 38,
        delegate_target: "panel-overview"
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
  end
end
