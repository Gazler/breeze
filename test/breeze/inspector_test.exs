defmodule Breeze.InspectorTest do
  use ExUnit.Case, async: true

  alias Breeze.Inspector
  alias Breeze.Server.State
  alias Breeze.Viewport

  defmodule RenderTreeView do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box id="root" class="panel">
        <box id="field" focusable class="input text-primary bg-panel">Field</box>
        <box id="variant" class="selected:text-primary selected:bg-panel">Variant</box>
        <box id="nested" class="label">
          <box id="leaf" class="text-primary bg-panel">Leaf</box>
        </box>
      </box>
      """
    end
  end

  defmodule ComponentTreeView do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <box id="root">
        <.input id="url" input-value="abc"/>
        <box id="plain">Plain</box>
      </box>
      """
    end
  end

  defmodule StyleMapTreeView do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box id="root" style={%{foreground_color: {235, 219, 178}, background_color: {40, 40, 40}}}>
        Styled
      </box>
      """
    end
  end

  test "toggle uses configured keys and clears hover state while re-syncing selection" do
    state =
      base_state(%{
        inspector: [toggle_key: "F9", move_key: "F10"],
        inspector_state: %{selected_id: "field", hovered_id: "nested"}
      })

    assert Inspector.enabled?(state)
    assert Inspector.remote?(state)
    assert Inspector.toggle_key(state) == "F9"
    assert Inspector.move_key(state) == "F10"

    opened = Inspector.toggle(state)
    assert opened.inspector_state.visible?
    assert opened.inspector_state.selected_id == "field"
    assert opened.inspector_state.hovered_id == nil

    closed = Inspector.toggle(opened)
    refute closed.inspector_state.visible?
    assert closed.inspector_state.selected_id == "field"
    assert closed.inspector_state.hovered_id == nil

    refute Inspector.remote?(base_state(%{inspector: [remote: false]}))
  end

  test "snapshot falls back to the focused element when the selected id is stale" do
    state =
      base_state(%{
        inspector: true,
        inspector_state: %{visible?: true, selected_id: "missing", hovered_id: "nested"},
        focused: "field"
      })

    snapshot = Inspector.snapshot(state)

    assert snapshot.enabled?
    assert snapshot.visible?
    assert snapshot.selected_id == "field"
    assert snapshot.hovered_id == "nested"
    assert snapshot.toggle_key == "F4"
    assert snapshot.move_key == "PageUp"
    assert snapshot.selected.actual_id == "field"
    assert snapshot.selected.focus_meta == %{group: :form}
    assert snapshot.hovered.actual_id == "nested"
  end

  test "snapshot falls back to the first explicit id before anonymous inspector nodes" do
    state =
      base_state(%{
        inspector: true,
        inspector_state: %{visible?: true, selected_id: nil},
        focused: nil,
        rendered: %{
          flags: %{
            "__inspector__1" => [__inspector_idx__: 1],
            "field" => [id: "field"],
            "nested" => [id: "nested"]
          }
        }
      })

    snapshot = Inspector.snapshot(state)

    assert snapshot.selected_id == "field"
    assert snapshot.selected.actual_id == "field"
  end

  test "renderer only builds render tree data when requested" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {acc, _box} =
      Breeze.Renderer.render(RenderTreeView, %{},
        terminal: terminal,
        theme: true,
        theme_source: true
      )

    refute Map.has_key?(acc, :render_tree)

    {acc, _box} =
      Breeze.Renderer.render(RenderTreeView, %{},
        terminal: terminal,
        theme: true,
        theme_source: true,
        render_tree?: true
      )

    assert is_map(acc.render_tree)
  end

  test "render tree handles style maps with tuple colors" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    theme = Breeze.Theme.default(terminal: terminal)

    {acc, _box} =
      Breeze.Renderer.render(StyleMapTreeView, %{},
        terminal: terminal,
        theme: theme,
        theme_source: theme,
        render_tree?: true
      )

    state =
      %Breeze.Server{
        terminal: terminal,
        view: StyleMapTreeView,
        theme: theme,
        inspector_state: %State.Inspector{config: true, selected_id: "root"},
        rendered: %State.Rendered{}
      }
      |> Breeze.Server.Inspector.merge_render_data(acc, %{})

    tree = Inspector.render_tree(state, expanded: ["root"], selected_id: "root", limit: 10)

    assert [%{id: "root", label_parts: label_parts}] = tree.nodes

    assert %{
             text: "●",
             token: :swatch,
             role: :foreground,
             foreground_color: {235, 219, 178},
             background_color: nil
           } in label_parts

    assert %{
             text: "●",
             token: :swatch,
             role: :background,
             foreground_color: {40, 40, 40},
             background_color: nil
           } in label_parts
  end

  test "snapshot advertises render tree availability and queries a bounded tree window" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    theme =
      Breeze.Theme.new(%{
        name: "tree-test",
        defaults: %{foreground_color: {9, 9, 9}, background_color: {0, 0, 0}},
        palette: %{primary: {1, 2, 3}, panel: {4, 5, 6}},
        extras: %{}
      })

    {acc, _box} =
      Breeze.Renderer.render(RenderTreeView, %{},
        terminal: terminal,
        theme: theme,
        theme_source: true,
        render_tree?: true
      )

    state =
      %Breeze.Server{
        terminal: terminal,
        view: RenderTreeView,
        theme: theme,
        input: %State.Input{last_interaction_at: 456},
        frame: %State.Frame{last_render_at: 123},
        inspector_state: %State.Inspector{config: true, selected_id: "leaf"},
        rendered: %State.Rendered{}
      }
      |> Breeze.Server.Inspector.merge_render_data(acc, %{})

    snapshot = Inspector.snapshot(state)

    assert snapshot.selected_id == "leaf"
    assert snapshot.render_tree?
    assert snapshot.last_render_at == 123
    assert snapshot.last_interaction_at == 456
    refute Map.has_key?(snapshot, :render_tree)

    tree = Inspector.render_tree(state, expanded: ["root"], selected_id: "leaf", limit: 10)

    assert [
             %{
               id: "root",
               label: root_label,
               children: [
                 %{id: "field", label: field_label, label_parts: field_label_parts, children: []},
                 %{
                   id: "variant",
                   label: variant_label,
                   label_parts: variant_label_parts,
                   children: []
                 },
                 %{
                   id: "nested",
                   children: [
                     %{
                       id: "leaf",
                       label: leaf_label,
                       label_parts: leaf_label_parts,
                       children: []
                     }
                   ]
                 }
               ]
             }
           ] = tree.nodes

    assert root_label =~ "<box#root.panel>"
    assert field_label =~ "#field"
    assert field_label =~ ".input"
    assert field_label =~ ".input.text-primary●.bg-panel●>"

    assert %{
             text: "●",
             token: :swatch,
             role: :foreground,
             foreground_color: {1, 2, 3},
             background_color: nil
           } in field_label_parts

    assert %{
             text: "●",
             token: :swatch,
             role: :background,
             foreground_color: {4, 5, 6},
             background_color: nil
           } in field_label_parts

    assert variant_label =~ ".selected:text-primary●.selected:bg-panel●>"

    assert %{
             text: "●",
             token: :swatch,
             role: :foreground,
             foreground_color: {1, 2, 3},
             background_color: nil
           } in variant_label_parts

    assert %{
             text: "●",
             token: :swatch,
             role: :background,
             foreground_color: {4, 5, 6},
             background_color: nil
           } in variant_label_parts

    assert leaf_label =~ ".text-primary●.bg-panel●>"

    assert %{
             text: "●",
             token: :swatch,
             role: :foreground,
             foreground_color: {1, 2, 3},
             background_color: nil
           } in leaf_label_parts

    assert %{
             text: "●",
             token: :swatch,
             role: :background,
             foreground_color: {4, 5, 6},
             background_color: nil
           } in leaf_label_parts

    assert %{label_parts: [%{text: "<", token: :punctuation}, %{text: "box", token: :tag} | _]} =
             hd(tree.nodes)

    refute Enum.any?(hd(tree.nodes).label_parts, &match?(%{token: :swatch}, &1))

    assert "nested" in tree.expanded

    tree = Inspector.render_tree(state, expanded: ["root"], selected_id: "field", limit: 10)

    assert [
             %{
               children: [
                 %{id: "field"},
                 %{id: "variant"},
                 %{id: "nested", expandable?: true, children: []}
               ]
             }
           ] = tree.nodes
  end

  test "render tree can expose a code tree view with component labels" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    theme = Breeze.Theme.default(terminal: terminal)

    {acc, _box} =
      Breeze.Renderer.render(ComponentTreeView, %{},
        terminal: terminal,
        theme: theme,
        theme_source: theme,
        render_tree?: true
      )

    state =
      %Breeze.Server{
        terminal: terminal,
        view: ComponentTreeView,
        theme: theme,
        inspector_state: %State.Inspector{config: true, selected_id: "url"},
        rendered: %State.Rendered{}
      }
      |> Breeze.Server.Inspector.merge_render_data(acc, %{})

    snapshot = Inspector.snapshot(state)

    assert snapshot.render_tree?
    assert snapshot.render_tree_kinds == [:rendered, :code]

    rendered_tree =
      Inspector.render_tree(state, expanded: ["root"], selected_id: "url", limit: 10)

    code_tree =
      Inspector.render_tree(state, kind: :code, expanded: ["root"], selected_id: "url", limit: 10)

    assert rendered_tree.kind == :rendered
    assert code_tree.kind == :code

    assert [
             %{
               id: "root",
               children: [
                 %{id: "url", label: rendered_label, label_parts: rendered_label_parts},
                 %{id: "plain"}
               ]
             }
           ] = rendered_tree.nodes

    assert [
             %{
               id: "root",
               children: [
                 %{id: "url", label: code_label, label_parts: code_label_parts, tree_kind: :code},
                 %{id: "plain", label: plain_label}
               ],
               tree_kind: :code
             }
           ] = code_tree.nodes

    assert rendered_label =~ "<box#url"
    assert rendered_label =~ "Breeze.Blocks.input"
    assert code_label =~ "<Breeze.Blocks.input#url"
    assert plain_label =~ "<box#plain"

    assert %{text: "box", token: :tag} in rendered_label_parts
    assert %{text: " Breeze.Blocks.input", token: :component} in rendered_label_parts
    assert %{text: "Breeze.Blocks.input", token: :tag} in code_label_parts
    refute Enum.any?(code_label_parts, &match?(%{token: :component}, &1))
  end

  test "select_at cycles overlapping targets from inner to outer elements" do
    state =
      base_state(%{
        inspector: true,
        inspector_state: %{visible?: true, selected_id: "field"}
      })

    click = %{x: 4, y: 3}

    state = Inspector.select_at(state, click)
    assert state.inspector_state.selected_id == "nested"
    assert state.inspector_state.hovered_id == "nested"

    state = Inspector.select_at(state, click)
    assert state.inspector_state.selected_id == "field"
    assert state.inspector_state.hovered_id == "field"
  end

  test "hover_at and select_at ignore mouse events inside the inspector panel" do
    state =
      base_state(%{
        inspector: true,
        inspector_state: %{visible?: true, selected_id: "field", hovered_id: "nested"}
      })

    bottom_panel_event = %{x: 10, y: 24}

    assert Inspector.hover_at(state, bottom_panel_event).inspector_state.hovered_id == "nested"
    assert Inspector.select_at(state, bottom_panel_event).inspector_state.selected_id == "field"

    top_docked =
      state
      |> Inspector.toggle_position()
      |> then(fn state ->
        %{state | inspector_state: %{state.inspector_state | hovered_id: "nested"}}
      end)

    top_panel_event = %{x: 10, y: 1}

    assert Inspector.hover_at(top_docked, top_panel_event).inspector_state.hovered_id == "nested"
    assert Inspector.select_at(top_docked, top_panel_event).inspector_state.selected_id == "field"
  end

  test "overlays are empty when hidden and include markers plus panel rows when visible" do
    state =
      base_state(%{
        inspector: true,
        inspector_state: %{visible?: true, selected_id: "field", hovered_id: "nested"}
      })

    hidden = %{state | inspector_state: %{state.inspector_state | visible?: false}}
    assert Inspector.overlays(hidden) == []

    overlays = Inspector.overlays(state)
    content_rows = Enum.filter(overlays, &Map.has_key?(&1, :content))
    marker_rows = Enum.reject(overlays, &Map.has_key?(&1, :content))

    assert length(content_rows) == Inspector.panel_height()
    assert Enum.any?(content_rows, &String.contains?(&1.content, "Inspector [F4]"))
    assert Enum.any?(marker_rows, &(&1.char == "("))
    assert Enum.any?(marker_rows, &(&1.char == "["))
  end

  defp base_state(overrides) do
    Map.merge(
      %{
        inspector: false,
        inspector_state: %{
          visible?: false,
          selected_id: nil,
          hovered_id: nil,
          panel_position: :bottom
        },
        focused: nil,
        view: __MODULE__.ExampleView,
        theme: nil,
        terminal: %Termite.Terminal{size: %{width: 80, height: 24}},
        rendered: %{
          mouse_targets: %{
            "field" => %{left: 0, right: 12, top: 0, bottom: 3},
            "nested" => %{left: 2, right: 6, top: 1, bottom: 2}
          },
          flags: %{
            "field" => [id: "field", focusable: true, class: "input"],
            "nested" => [id: "nested", class: "label"]
          },
          viewports: %{
            "field" => %Viewport{
              left: 0,
              top: 0,
              width: 13,
              height: 4,
              viewport_width: 13,
              viewport_height: 4,
              content_width: 13,
              content_height: 4
            },
            "nested" => %Viewport{
              left: 2,
              top: 1,
              width: 5,
              height: 2,
              viewport_width: 5,
              viewport_height: 2,
              content_width: 5,
              content_height: 2
            }
          },
          boxes: %{},
          focus_meta: %{"field" => %{group: :form}},
          implicit_state: %{},
          implicit_meta: %{}
        },
        children: %{},
        focus_memory: %{}
      },
      overrides
    )
  end
end
