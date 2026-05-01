defmodule Breeze.InspectorTest do
  use ExUnit.Case, async: true

  alias Breeze.Inspector
  alias Breeze.Viewport

  test "toggle uses configured keys and clears hover state while re-syncing selection" do
    state =
      base_state(%{
        inspector: [toggle_key: "F9", move_key: "F10"],
        inspector_state: %{selected_id: "field", hovered_id: "nested"}
      })

    assert Inspector.enabled?(state)
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
