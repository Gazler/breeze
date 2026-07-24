defmodule Breeze.Renderer.InputRoutingTest do
  use ExUnit.Case, async: true

  alias Breeze.Renderer.InputRouting

  defmodule ReconciliationProbe do
    @behaviour Breeze.Implicit

    def init(_items, root_attrs, state) do
      {:ok, Map.put(state, :value, Map.get(root_attrs, :"input-value")),
       captures_printable_keys: true}
    end

    def handle_modifiers(_type, _flags, _state), do: []
  end

  test "keeps the owning implicit on the focused routing path" do
    previous = InputRouting.signature(implicit_live_tree("before"))
    desired = InputRouting.signature(implicit_live_tree("after"))

    assert InputRouting.structure_changed?(previous, desired, "focused")
    refute InputRouting.structure_changed?(previous, desired, "outside")
  end

  test "leaves non-routing implicit attributes to explicit reconciliation" do
    previous = InputRouting.signature(implicit_tree("second"))
    desired = InputRouting.signature(implicit_tree("changed"))

    refute InputRouting.structure_changed?(previous, desired, "focused")
  end

  test "ignores non-routing attributes outside the focused implicit" do
    previous = InputRouting.signature(implicit_tree("second", "muted"))
    desired = InputRouting.signature(implicit_tree("second", "accent"))

    refute InputRouting.structure_changed?(previous, desired, "outside")
  end

  test "detects global focus structure changes" do
    previous = InputRouting.signature(focus_scope_tree(nil))
    desired = InputRouting.signature(focus_scope_tree("trap"))

    assert InputRouting.structure_changed?(previous, desired, nil)
  end

  test "collects live entries without exposing traversal to the server" do
    signature =
      InputRouting.signature([
        {:box, [],
         [
           {:live, [id: "first", view: FirstView]},
           {:box, [], [{:live, [id: "second", view: SecondView]}]}
         ]}
      ])

    assert InputRouting.live_entries(signature) == %{
             "first" => %{"id" => "first", "view" => FirstView},
             "second" => %{"id" => "second", "view" => SecondView}
           }
  end

  test "reuses the focused implicit init lifecycle for reconciliation" do
    signature = InputRouting.signature(controlled_input_tree("", ReconciliationProbe))

    assert InputRouting.focused_implicit_changed?(
             signature,
             "input",
             {ReconciliationProbe, %{value: "typed"}},
             %{captures_printable_keys: true},
             nil
           )

    refute InputRouting.focused_implicit_changed?(
             signature,
             "input",
             {ReconciliationProbe, %{value: ""}},
             %{captures_printable_keys: true},
             nil
           )
  end

  defp implicit_tree(sibling_value, class \\ nil) do
    root_attrs =
      [{:attribute, ["id", "outside"]}]
      |> maybe_add_class(class)

    [
      {:box, [],
       root_attrs ++
         [
           {:box, [],
            [
              {:attribute, ["id", "implicit"]},
              {:attribute, ["implicit", Breeze.Implicit.List]},
              {:box, [],
               [
                 {:attribute, ["id", "focused"]},
                 {:attribute, ["value", "first"]}
               ]},
              {:box, [],
               [
                 {:attribute, ["id", "sibling"]},
                 {:attribute, ["value", sibling_value]}
               ]}
            ]}
         ]}
    ]
  end

  defp implicit_live_tree(value) do
    [
      {:box, [],
       [
         {:attribute, ["id", "outside"]},
         {:box, [],
          [
            {:attribute, ["id", "implicit"]},
            {:attribute, ["implicit", Breeze.Implicit.List]},
            {:box, [],
             [
               {:attribute, ["id", "focused"]},
               {:attribute, ["value", "first"]}
             ]},
            {:live, [id: "child", view: FirstView, assigns: %{value: value}]}
          ]}
       ]}
    ]
  end

  defp focus_scope_tree(scope) do
    scope_attr = if scope, do: [{:attribute, ["focus-scope", scope]}], else: []

    [
      {:box, [],
       [
         {:box, [],
          [{:attribute, ["id", "dialog"]}] ++
            scope_attr ++
            [
              {:box, [],
               [
                 {:attribute, ["id", "button"]},
                 {:attribute_bool, ["focusable"]}
               ]}
            ]}
       ]}
    ]
  end

  defp controlled_input_tree(value, module) do
    [
      {:box, [],
       [
         {:attribute, ["id", "input"]},
         {:attribute, ["implicit", module]},
         {:attribute, ["input-value", value]}
       ]}
    ]
  end

  defp maybe_add_class(attrs, nil), do: attrs
  defp maybe_add_class(attrs, class), do: attrs ++ [{:attribute, ["class", class]}]
end
