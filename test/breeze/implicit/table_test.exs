defmodule Breeze.Implicit.TableTest do
  use ExUnit.Case, async: true

  alias Breeze.Implicit.Table
  alias Breeze.Viewport

  describe "init/3" do
    test "keeps prior selection when still present" do
      children = [
        %{:"table-row" => true, value: "one"},
        %{:"table-row" => true, value: "two"},
        %{:"table-row" => true, value: "three"}
      ]

      state = Table.init(children, %{}, %{selected: "two", offset: 2})

      assert state.selected == "two"
      assert state.selected_index == 1
      assert state.offset == 2
    end

    test "prefers table-selected from root attrs" do
      children = [
        %{:"table-row" => true, value: "one"},
        %{:"table-row" => true, value: "two"},
        %{:"table-row" => true, value: "three"}
      ]

      state =
        Table.init(
          children,
          %{:"table-selected" => "three"},
          %{selected: "one", selected_index: 0, offset: 0}
        )

      assert state.selected == "three"
      assert state.selected_index == 2
    end
  end

  describe "handle_event/3" do
    test "moves selection and adjusts scroll" do
      viewport = Viewport.from_dimensions(%{height: 3, viewport_height: 3, content_height: 10})

      state = %{
        values: Enum.map(1..10, &"row-#{&1}"),
        selected: "row-1",
        selected_index: 0,
        offset: 0,
        loop: true,
        scroll_padding: 0
      }

      {{:change, payload}, state} =
        Table.handle_event(:ignore, %{"key" => "ArrowDown", "element" => viewport}, state)

      assert state.selected == "row-2"
      assert state.selected_index == 1
      assert payload == %{value: "row-2", index: 1, offset: 0}
    end

    test "selects the clicked row and emits change" do
      viewport = Viewport.from_dimensions(%{height: 4, viewport_height: 4, content_height: 6})

      state = %{
        values: ["alpha", "beta", "gamma"],
        selected: "alpha",
        selected_index: 0,
        offset: 0,
        loop: true,
        scroll_padding: 0
      }

      {{:change, payload}, state} =
        Table.handle_event(
          :ignore,
          %{
            "mouse" => %{button: :left, action: :press},
            "row" => 2,
            "element" => viewport
          },
          state
        )

      assert state.selected == "gamma"
      assert state.selected_index == 2
      assert payload == %{value: "gamma", index: 2, offset: 0}
    end
  end

  describe "handle_modifiers/3" do
    test "marks selected rows and scrolls the body" do
      state = %{selected: "row", offset: 3}

      assert Table.handle_modifiers(:child, [{:value, "row"}, {:"table-row", true}], state) ==
               [selected: true]

      assert Table.handle_modifiers(:child, [{:value, "other"}, {:"table-row", true}], state) ==
               []

      assert Table.handle_modifiers(:root, [], state) == [scroll_y: 3]
    end
  end
end
