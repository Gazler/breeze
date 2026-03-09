defmodule Breeze.Implicit.ModalTest do
  use ExUnit.Case, async: true

  alias Breeze.Implicit.Modal

  describe "init/3" do
    test "centers the modal from root dimensions" do
      state =
        Modal.init(
          [],
          %{:width => 20, :height => 6, :"screen-width" => 80, :"screen-height" => 24},
          %{}
        )

      assert state.frame_width == 22
      assert state.frame_height == 8
      assert state.left == 29
      assert state.top == 8
    end
  end

  describe "handle_event/3" do
    test "escape emits a close change" do
      state = %{left: 0, top: 0}

      assert Modal.handle_event(nil, %{"key" => "Escape"}, state) ==
               {{:change, %{action: :close}}, state}
    end
  end

  describe "handle_modifiers/3" do
    test "root modifiers position the modal absolutely" do
      assert Modal.handle_modifiers(:root, [], %{left: 12, top: 4}) ==
               [style: "absolute left-12 top-4"]
    end
  end
end
