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

  defmodule StyleReconciliationProbe do
    @behaviour Breeze.Implicit

    def init([%{style_input: item_style}], %{style_input: root_style}, _state) do
      {:ok, %{item_style: item_style, root_style: root_style}}
    end

    def handle_modifiers(_type, _flags, _state), do: []
  end

  test "keeps the owning implicit on the focused routing path" do
    previous = InputRouting.signature(implicit_live_tree("before"))
    desired = InputRouting.signature(implicit_live_tree("after"))

    assert InputRouting.structure_changed?(previous, desired, "focused")
    refute InputRouting.structure_changed?(previous, desired, "outside")
  end

  test "treats implicit item attributes as potential routing structure" do
    previous = InputRouting.signature(implicit_tree("second"))
    desired = InputRouting.signature(implicit_tree("changed"))

    assert InputRouting.structure_changed?(previous, desired, "focused")
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

  test "treats unfocused implicit root attributes as potential routing structure" do
    previous = InputRouting.signature(attribute_driven_implicit_tree(false))
    desired = InputRouting.signature(attribute_driven_implicit_tree(true))

    assert InputRouting.structure_changed?(previous, desired, "outside")
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

  test "normalizes root and item styles like the renderer during reconciliation" do
    signature = InputRouting.signature(styled_implicit_tree())

    refute InputRouting.focused_implicit_changed?(
             signature,
             "styled",
             {StyleReconciliationProbe, %{item_style: "text-red", root_style: "border-rounded"}},
             %{},
             nil
           )
  end

  defp implicit_tree(sibling_value, class \\ nil) do
    root_attrs = [{:attribute, ["id", "outside"]}] |> maybe_add_class(class)

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

  defp attribute_driven_implicit_tree(trap?) do
    [
      {:box, [],
       [
         {:attribute, ["id", "implicit"]},
         {:attribute, ["implicit", ReconciliationProbe]},
         {:attribute, ["routing-trap", trap?]}
       ]}
    ]
  end

  defp styled_implicit_tree do
    [
      {:box, [],
       [
         {:attribute, ["id", "styled"]},
         {:attribute, ["implicit", StyleReconciliationProbe]},
         {:attribute, ["style", "border-rounded"]},
         {:box, [], [{:attribute, ["style", "text-red"]}]}
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
