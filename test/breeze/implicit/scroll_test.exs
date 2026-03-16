defmodule Breeze.Implicit.ScrollTest do
  use ExUnit.Case, async: true

  alias Breeze.Implicit.Scroll
  alias Breeze.Viewport

  describe "init/3" do
    test "carries autoscroll configuration from root attrs" do
      state = Scroll.init([], %{"scroll-autoscroll": "bottom"}, %{})

      assert state.offset_y == 0
      assert state.autoscroll == "bottom"
      assert state.pinned_bottom == true
    end

    test "preserves prior scroll state" do
      state =
        Scroll.init([], %{}, %{offset_y: 4, autoscroll: "bottom", pinned_bottom: false})

      assert state.offset_y == 4
      assert state.autoscroll == "bottom"
      assert state.pinned_bottom == false
    end
  end

  describe "handle_event/3" do
    test "updates offset and clears pinned_bottom when user scrolls away" do
      viewport = %{viewport_height: 4, content_height: 12, height: 4}
      state = %{offset_y: 8, autoscroll: "bottom", pinned_bottom: true}

      assert {:noreply, next_state} =
               Scroll.handle_event(
                 :ignore_me,
                 %{"key" => "ArrowUp", "element" => viewport},
                 state
               )

      assert next_state.offset_y == 7
      assert next_state.pinned_bottom == false
    end

    test "keeps pinned_bottom when user scrolls to end" do
      viewport = %{viewport_height: 4, content_height: 12, height: 4}
      state = %{offset_y: 6, autoscroll: "bottom", pinned_bottom: false}

      assert {:noreply, next_state} =
               Scroll.handle_event(:ignore_me, %{"key" => "End", "element" => viewport}, state)

      assert next_state.offset_y == 8
      assert next_state.pinned_bottom == true
    end

    test "wheel scroll moves the viewport" do
      viewport = %{viewport_height: 4, content_height: 12, height: 4}
      state = %{offset_y: 3, autoscroll: nil, pinned_bottom: false}

      assert {:noreply, next_state} =
               Scroll.handle_event(
                 :ignore_me,
                 %{"mouse" => %{button: :wheel_down}, "element" => viewport},
                 state
               )

      assert next_state.offset_y == 5
      assert next_state.pinned_bottom == false
    end

    test "wheel scroll respects coalesced repeat counts" do
      viewport = %{viewport_height: 4, content_height: 20, height: 4}
      state = %{offset_y: 3, autoscroll: nil, pinned_bottom: false}

      assert {:noreply, next_state} =
               Scroll.handle_event(
                 :ignore_me,
                 %{"mouse" => %{button: :wheel_down, repeat: 3}, "element" => viewport},
                 state
               )

      assert next_state.offset_y == 9
    end
  end

  describe "handle_modifiers/3" do
    test "autoscrolls to bottom when pinned" do
      viewport = Viewport.from_dimensions(%{viewport_height: 5, content_height: 14, height: 5})
      state = %{offset_y: 4, autoscroll: "bottom", pinned_bottom: true}

      assert [scroll_y: 9] = Scroll.handle_modifiers(:root, [layout_element: viewport], state)
    end

    test "does not autoscroll when user has scrolled away" do
      viewport = Viewport.from_dimensions(%{viewport_height: 5, content_height: 14, height: 5})
      state = %{offset_y: 3, autoscroll: "bottom", pinned_bottom: false}

      assert [scroll_y: 3] = Scroll.handle_modifiers(:root, [layout_element: viewport], state)
    end

    test "clamps offset even without autoscroll" do
      viewport = Viewport.from_dimensions(%{viewport_height: 5, content_height: 9, height: 5})
      state = %{offset_y: 20}

      assert [scroll_y: 4] = Scroll.handle_modifiers(:root, [layout_element: viewport], state)
    end
  end
end
