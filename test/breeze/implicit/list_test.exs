defmodule Breeze.Implicit.ListTest do
  use ExUnit.Case, async: true

  alias Breeze.Implicit
  alias Breeze.Viewport

  describe "init/3" do
    test "keeps prior selection when still present" do
      children = [%{value: "one"}, %{value: "two"}, %{value: "three"}]

      state = Implicit.List.init(children, %{}, %{selected: "two", offset: 2})

      assert state.selected == "two"
      assert state.selected_index == 1
      assert state.offset == 2
    end

    test "reads root options" do
      children = [%{value: "a"}, %{value: "b"}, %{value: "c"}]

      state =
        Implicit.List.init(children, %{:"list-loop" => false, :"list-scroll-padding" => "2"}, %{})

      assert state.loop == false
      assert state.scroll_padding == 2
    end

    test "prefers list-selected from the root attrs over the prior internal selection" do
      children = [%{value: "one"}, %{value: "two"}, %{value: "three"}]

      state =
        Implicit.List.init(
          children,
          %{:"list-selected" => "three"},
          %{selected: "one", selected_index: 0, offset: 0}
        )

      assert state.selected == "three"
      assert state.selected_index == 2
    end

    test "reads full values and offset from root attrs for windowed lists" do
      children = [%{value: "two"}, %{value: "three"}]

      state =
        Implicit.List.init(
          children,
          %{:"list-values" => ["one", "two", "three", "four"], :"list-offset" => 1},
          %{selected: "three", selected_index: 2, offset: 0}
        )

      assert state.values == ["one", "two", "three", "four"]
      assert state.selected == "three"
      assert state.selected_index == 2
      assert state.offset == 1
    end
  end

  describe "handle_event/3" do
    test "moves selection down and adjusts scroll" do
      viewport = Viewport.from_dimensions(%{height: 3, viewport_height: 3, content_height: 10})

      state = %{
        values: Enum.map(1..10, &"item-#{&1}"),
        selected: "item-1",
        selected_index: 0,
        offset: 0,
        loop: true,
        scroll_padding: 0,
        width: 0
      }

      {{:change, payload}, state} =
        Implicit.List.handle_event(:ignore, %{"key" => "ArrowDown", "element" => viewport}, state)

      assert state.selected_index == 1
      assert state.selected == "item-2"
      assert state.offset == 0
      assert payload == %{value: "item-2", index: 1, offset: 0}
    end

    test "loops at the end by default" do
      viewport = Viewport.from_dimensions(%{height: 3, viewport_height: 3, content_height: 3})

      state = %{
        values: ["a", "b", "c"],
        selected: "c",
        selected_index: 2,
        offset: 0,
        loop: true,
        scroll_padding: 0,
        width: 0
      }

      {{:change, payload}, state} =
        Implicit.List.handle_event(:ignore, %{"key" => "ArrowDown", "element" => viewport}, state)

      assert state.selected == "a"
      assert state.selected_index == 0
      assert payload.value == "a"
    end

    test "does not loop when disabled" do
      viewport = Viewport.from_dimensions(%{height: 3, viewport_height: 3, content_height: 3})

      state = %{
        values: ["a", "b", "c"],
        selected: "c",
        selected_index: 2,
        offset: 0,
        loop: false,
        scroll_padding: 0,
        width: 0
      }

      {{:change, _payload}, state} =
        Implicit.List.handle_event(:ignore, %{"key" => "ArrowDown", "element" => viewport}, state)

      assert state.selected == "c"
      assert state.selected_index == 2
    end

    test "selects the clicked row and emits change" do
      viewport = Viewport.from_dimensions(%{height: 4, viewport_height: 4, content_height: 6})

      state = %{
        values: ["alpha", "beta", "gamma"],
        selected: "alpha",
        selected_index: 0,
        offset: 0,
        loop: true,
        scroll_padding: 0,
        width: 0
      }

      {{:change, payload}, state} =
        Implicit.List.handle_event(
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

    test "wheel scroll updates offset without changing selection" do
      viewport = Viewport.from_dimensions(%{height: 3, viewport_height: 3, content_height: 8})

      state = %{
        values: Enum.map(1..8, &"item-#{&1}"),
        selected: "item-2",
        selected_index: 1,
        offset: 1,
        loop: true,
        scroll_padding: 0,
        width: 0
      }

      assert {:noreply, next_state} =
               Implicit.List.handle_event(
                 :ignore,
                 %{"mouse" => %{button: :wheel_down}, "element" => viewport},
                 state
               )

      assert next_state.offset == 2
      assert next_state.selected == "item-2"
      assert next_state.selected_index == 1
    end

    test "wheel scroll respects coalesced repeat counts" do
      viewport = Viewport.from_dimensions(%{height: 3, viewport_height: 3, content_height: 8})

      state = %{
        values: Enum.map(1..8, &"item-#{&1}"),
        selected: "item-2",
        selected_index: 1,
        offset: 1,
        loop: true,
        scroll_padding: 0,
        width: 0
      }

      assert {:noreply, next_state} =
               Implicit.List.handle_event(
                 :ignore,
                 %{"mouse" => %{button: :wheel_down, repeat: 3}, "element" => viewport},
                 state
               )

      assert next_state.offset == 4
      assert next_state.selected == "item-2"
      assert next_state.selected_index == 1
    end
  end

  describe "handle_modifiers/3" do
    test "marks selected children" do
      state = %{selected: "value", offset: 2}

      assert Implicit.List.handle_modifiers(:child, [value: "value"], state) == [selected: true]
      assert Implicit.List.handle_modifiers(:child, [value: "other"], state) == []
      assert Implicit.List.handle_modifiers(:root, [], state) == [scroll_y: 2]
    end
  end
end
