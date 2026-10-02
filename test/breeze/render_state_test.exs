defmodule Breeze.RenderStateTest do
  use ExUnit.Case, async: true

  alias Breeze.{RenderState, Term}

  defmodule Receiver do
    def handle_event(_, payload, state),
      do: {:noreply, Map.put(state, :received, payload)}
  end

  defmodule Idle do
    def handle_event(_, _, state), do: {:noreply, state}
  end

  defmodule Explicit do
    def handle_event(_, payload, state) do
      next_state = if payload["update"], do: Map.put(state, :updated, true), else: state
      {:noreply, next_state, state.opts}
    end
  end

  defmodule Change do
    def handle_event(_, payload, state), do: {{:change, payload}, state, state.opts}
  end

  test "capture options update routing and consume events without an implicit state change" do
    term = put_in(term().implicit_state["source"], {Explicit, %{opts: [capture_mouse: true]}})
    assert {:noreply, true, captured} = dispatch(term, %{})
    assert captured.mouse_capture == "source"
    assert captured.implicit_state == term.implicit_state

    releasing =
      put_in(captured.implicit_state["source"], {Explicit, %{opts: [capture_mouse: false]}})

    assert {:noreply, true, released} = dispatch(releasing, %{})
    assert released.mouse_capture == nil
    assert released.implicit_state == releasing.implicit_state
  end

  test "explicit non-consumption still applies capture options before delegation" do
    term =
      put_in(
        term().implicit_state["source"],
        {Explicit, %{opts: [capture_mouse: true, consumed: false]}}
      )

    assert {:noreply, true, result} = dispatch(term, %{"key" => "ArrowDown"})
    assert result.mouse_capture == "source"
    assert {Receiver, %{received: %{"key" => "ArrowDown"}}} = result.implicit_state["target"]
  end

  test "another implicit cannot release or steal the focused implicit's capture" do
    for capture <- [false, true] do
      term = %{term() | mouse_capture: "source"}

      term =
        put_in(
          term.implicit_state["target"],
          {Explicit, %{opts: [capture_mouse: capture]}}
        )

      assert {:noreply, false, ^term} = dispatch(term, %{}, "target")
    end
  end

  test "change replies apply capture and focus options before notifying the view" do
    for opts <- [[capture_mouse: true, focus: "source"], [focus: "source", capture_mouse: true]] do
      term = %{term() | focused: "target"}
      term = put_in(term.implicit_state["source"], {Change, %{opts: opts}})
      assert {:noreply, true, result} = dispatch(term, %{"key" => "Enter"})
      assert result.mouse_capture == "source"
      assert result.focused == "source"
      assert result.assigns.change["key"] == "Enter"

      term = put_in(result.implicit_state["source"], {Change, %{opts: [capture_mouse: false]}})
      assert {:noreply, true, released} = dispatch(term, %{})
      assert released.mouse_capture == nil
    end
  end

  test "explicit consumption stops fallback even with unchanged state" do
    term = put_in(term().implicit_state["source"], {Explicit, %{opts: [consumed: true]}})
    assert {:noreply, true, ^term} = dispatch(term, %{"key" => "ArrowDown"})
  end

  test "explicit non-consumption delegates while retaining changed state" do
    term = put_in(term().implicit_state["source"], {Explicit, %{opts: [consumed: false]}})
    assert {:noreply, true, result} = dispatch(term, %{"key" => "ArrowDown", "update" => true})
    assert {Explicit, %{updated: true}} = result.implicit_state["source"]
    assert {Receiver, %{received: %{"key" => "ArrowDown"}}} = result.implicit_state["target"]
  end

  test "explicit non-consumption without a target leaves the event for the view" do
    term = %{term() | events: %{}}
    term = put_in(term.implicit_state["source"], {Explicit, %{opts: [consumed: false]}})
    assert {:noreply, false, result} = dispatch(term, %{"key" => "x", "update" => true})
    assert {Explicit, %{updated: true}} = result.implicit_state["source"]
  end

  test "replies without consumed use state changes and ignore delegation" do
    for {mod, state} <- [{Idle, %{}}, {Explicit, %{opts: []}}] do
      term = put_in(term().implicit_state["source"], {mod, state})
      assert {:noreply, false, ^term} = dispatch(term, %{"key" => "ArrowDown"})
    end

    term = put_in(term().implicit_state["source"], {Explicit, %{opts: []}})
    assert {:noreply, true, result} = dispatch(term, %{"update" => true})
    assert {Explicit, %{updated: true}} = result.implicit_state["source"]
    assert result.implicit_state["target"] == {Receiver, %{}}
  end

  defp dispatch(term, payload, id \\ "source") do
    RenderState.dispatch_implicit_event(term, id, payload, fn term, _, _, event ->
      {:noreply, %{term | assigns: %{change: event}}}
    end)
  end

  defp term do
    %Term{
      focused: "source",
      events: %{"source" => %{delegate_events: "target", change: "changed"}},
      elements: %{"target" => %{viewport_height: 5}},
      implicit_state: %{
        "source" => {Breeze.Implicit.Checkbox, %{checked: false, disabled: false}},
        "target" => {Receiver, %{}}
      }
    }
  end

  test "unconsumed keyboard and mouse events reach the target with its viewport" do
    for payload <- [%{"key" => "ArrowDown"}, %{"mouse" => %{"button" => "wheel_down"}}] do
      assert {:noreply, true, result} = dispatch(term(), payload)
      assert result.focused == "source"
      assert {Receiver, %{received: received}} = result.implicit_state["target"]
      assert received == Map.put(payload, "element", %{viewport_height: 5})
      assert result.implicit_state["source"] == term().implicit_state["source"]
    end
  end

  test "checkbox activation is consumed before delegation" do
    for payload <- [
          %{"key" => " "},
          %{"key" => "Enter"},
          %{"mouse" => %{"button" => "left", "action" => "press"}}
        ] do
      assert {:noreply, true, result} = dispatch(term(), payload)
      assert result.assigns.change == %{value: true}
      assert {Receiver, %{}} = result.implicit_state["target"]
      assert map_size(elem(result.implicit_state["target"], 1)) == 0
    end
  end

  test "default consumption stores the reply without delegating" do
    term = put_in(term().implicit_state["source"], {Receiver, %{}})
    assert {:noreply, true, result} = dispatch(term, %{"key" => "ArrowDown"})
    assert result.implicit_state["target"] == {Receiver, %{}}
  end

  test "plain elements can delegate" do
    term = %{term() | implicit_state: %{"target" => {Receiver, %{}}}}
    assert {:noreply, true, _} = dispatch(term, %{"key" => "ArrowDown"})
  end

  test "absent, empty, missing and cyclic targets stop safely" do
    for events <- [
          %{},
          %{"source" => %{delegate_events: ""}},
          %{"source" => %{delegate_events: "missing"}},
          %{"source" => %{delegate_events: "source"}},
          %{
            "source" => %{delegate_events: "target"},
            "target" => %{delegate_events: "source"}
          }
        ] do
      term = %{term() | events: events}
      term = put_in(term.implicit_state["target"], {Explicit, %{opts: [consumed: false]}})
      assert {:noreply, false, ^term} = dispatch(term, %{"key" => "ArrowDown"})
    end
  end
end
