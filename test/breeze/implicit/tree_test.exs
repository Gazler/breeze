defmodule Breeze.Implicit.TreeTest do
  use ExUnit.Case, async: true

  alias Breeze.Implicit
  alias Breeze.Viewport

  describe "init/3" do
    test "flattens visible rows from expanded parents" do
      children = [
        %{
          :value => "root",
          :"tree-node" => true,
          :"tree-expandable" => true,
          :"tree-parents" => []
        },
        %{
          :value => "src",
          :"tree-node" => true,
          :"tree-parent" => "root",
          :"tree-parents" => ["root"],
          :"tree-expandable" => true
        },
        %{
          :value => "lib",
          :"tree-node" => true,
          :"tree-parent" => "src",
          :"tree-parents" => ["root", "src"],
          :"tree-expandable" => false
        },
        %{
          :value => "mix",
          :"tree-node" => true,
          :"tree-parents" => [],
          :"tree-expandable" => false
        }
      ]

      state = Implicit.Tree.init(children, %{:"tree-default-expanded" => ["root"]}, %{})

      assert state.values == ["root", "src", "mix"]
      assert MapSet.equal?(state.expanded, MapSet.new(["root"]))
    end

    test "keeps prior expanded state when uncontrolled" do
      children = [
        %{
          :value => "root",
          :"tree-node" => true,
          :"tree-expandable" => true,
          :"tree-parents" => []
        },
        %{
          :value => "src",
          :"tree-node" => true,
          :"tree-parent" => "root",
          :"tree-parents" => ["root"],
          :"tree-expandable" => false
        }
      ]

      state = Implicit.Tree.init(children, %{}, %{expanded: MapSet.new(["root"])})

      assert state.values == ["root", "src"]
    end
  end

  describe "handle_event/3" do
    test "expands, collapses, and navigates visible rows" do
      viewport = Viewport.from_dimensions(%{height: 4, viewport_height: 4, content_height: 4})

      state = %{
        rows: [
          %{value: "root", parent: nil, parents: [], expandable?: true, depth: 0},
          %{value: "src", parent: "root", parents: ["root"], expandable?: true, depth: 1},
          %{value: "lib", parent: "src", parents: ["root", "src"], expandable?: false, depth: 2}
        ],
        values: ["root", "src"],
        selected: "src",
        selected_index: 1,
        offset: 0,
        loop: true,
        scroll_padding: 0,
        expanded: MapSet.new(["root"])
      }

      {{:change, expand_payload}, expanded} =
        Implicit.Tree.handle_event(:ignore, %{"key" => "Enter"}, state)

      assert expanded.values == ["root", "src", "lib"]
      assert MapSet.member?(expanded.expanded, "src")
      assert "src" in expand_payload.expanded

      {{:change, payload}, selected_child} =
        Implicit.Tree.handle_event(
          :ignore,
          %{"key" => "ArrowRight", "element" => viewport},
          expanded
        )

      assert selected_child.selected == "lib"
      assert payload.value == "lib"

      {{:change, _payload}, selected_parent} =
        Implicit.Tree.handle_event(
          :ignore,
          %{"key" => "ArrowLeft", "element" => viewport},
          selected_child
        )

      assert selected_parent.selected == "src"

      {{:change, collapse_payload}, collapsed} =
        Implicit.Tree.handle_event(
          :ignore,
          %{"key" => "ArrowLeft", "element" => viewport},
          selected_parent
        )

      assert collapsed.values == ["root", "src"]
      refute MapSet.member?(collapsed.expanded, "src")
      refute "src" in collapse_payload.expanded
    end
  end

  describe "handle_modifiers/3" do
    test "hides collapsed descendants and switches prefixes" do
      state = %{
        rows: [
          %{value: "root", parent: nil, parents: [], expandable?: true, depth: 0},
          %{value: "src", parent: "root", parents: ["root"], expandable?: true, depth: 1},
          %{value: "lib", parent: "src", parents: ["root", "src"], expandable?: false, depth: 2}
        ],
        values: ["root", "src"],
        selected: "src",
        offset: 0,
        expanded: MapSet.new(["root"])
      }

      assert Implicit.Tree.handle_modifiers(
               :child,
               [{:"tree-node", true}, {:value, "lib"}],
               state
             ) ==
               [style: "hidden"]

      assert Implicit.Tree.handle_modifiers(
               :child,
               [{:"tree-node", true}, {:value, "src"}],
               state
             ) ==
               [selected: true]

      assert Implicit.Tree.handle_modifiers(
               :child,
               [{:"tree-collapsed-prefix", true}, {:selected_owner_value, "src"}],
               state
             ) == []

      assert Implicit.Tree.handle_modifiers(
               :child,
               [{:"tree-expanded-prefix", true}, {:selected_owner_value, "src"}],
               state
             ) == [style: "hidden"]
    end
  end
end
