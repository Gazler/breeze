defmodule Breeze.Implicit.ModalTest do
  use ExUnit.Case, async: true

  alias Breeze.Implicit.Modal

  describe "init/3" do
    test "preserves the previous state" do
      assert Modal.init([], %{}, %{open: true}) == %{open: true}
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
    test "root modifiers do not override modal positioning" do
      assert Modal.handle_modifiers(:root, [], %{}) == []
    end
  end
end
