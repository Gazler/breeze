defmodule Breeze.TestTest do
  use ExUnit.Case, async: true

  alias Breeze.Test, as: BreezeTest

  defmodule DriverView do
    use Breeze.View

    import Breeze.Blocks

    def mount(_opts, term) do
      {:ok, assign(term, mouse_events: [])}
    end

    def render(assigns) do
      ~H"""
      <box id="page" class={"w-#{@breeze.terminal.width} h-#{@breeze.terminal.height} overflow-hidden"}>
        <box id="size" class="text-primary">{@breeze.terminal.width}x{@breeze.terminal.height}</box>
        <.button id="action" class="w-10">Action</.button>
        <box id="secondary" focusable class="w-10 h-1">Secondary</box>
        <.scroll id="items" class="w-12 h-3">
          <box :for={index <- 1..8}>Row {index}</box>
        </.scroll>
      </box>
      """
    end

    def handle_event(
          _,
          %{
            "mouse" => %{"button" => "left", "action" => action} = mouse,
            "target" => "action"
          } = event,
          term
        ) do
      recorded = %{
        action: action,
        col: event["col"],
        row: event["row"],
        ctrl?: Map.get(mouse, "ctrlKey", false)
      }

      {:noreply, assign(term, mouse_events: term.assigns.mouse_events ++ [recorded])}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  setup do
    session = BreezeTest.start!(DriverView, size: {30, 10})
    on_exit(fn -> BreezeTest.stop(session) end)
    %{session: session}
  end

  test "renders plain text without ANSI styling", %{session: session} do
    assert BreezeTest.render!(session) =~ "\e["
    assert BreezeTest.render_text!(session) =~ "30x10"
    refute BreezeTest.render_text!(session) =~ "\e["
  end

  test "resizes a session and refreshes rendered viewport dimensions", %{session: session} do
    assert %Breeze.Viewport{width: 30, height: 10} = BreezeTest.element!(session, "page")

    resized = BreezeTest.resize(session, %{width: 44, height: 12})

    assert session.terminal.size == %{width: 30, height: 10}
    assert resized.terminal.size == %{width: 44, height: 12}
    assert BreezeTest.render_text!(resized) =~ "44x12"
    assert %Breeze.Viewport{width: 44, height: 12} = BreezeTest.element!(resized, "page")
  end

  test "focuses rendered elements and reports current focus", %{session: session} do
    assert {:noreply, nil, true} = BreezeTest.focus(session, nil)
    assert BreezeTest.focused(session) == nil

    assert {:noreply, "secondary", true} = BreezeTest.focus(session, "secondary")
    assert BreezeTest.focused(session) == "secondary"

    assert {:error, {:element_not_found, "missing"}} = BreezeTest.focus(session, "missing")
  end

  test "looks up rendered elements with useful missing-element errors", %{session: session} do
    assert {:ok, %Breeze.Viewport{width: 10, height: 1}} =
             BreezeTest.element(session, "action")

    assert {:error, {:element_not_found, "missing"}} = BreezeTest.element(session, "missing")

    assert_raise ArgumentError, ~r/could not find rendered Breeze element "missing"/, fn ->
      BreezeTest.element!(session, "missing")
    end
  end

  test "clicks an element by ID using relative coordinates and modifiers", %{session: session} do
    assert {:noreply, "action", true} =
             BreezeTest.click(session, "action", at: {2, 0}, ctrl: true)

    assert %{assigns: %{mouse_events: [%{action: "press", col: 2, row: 0, ctrl?: true}]}} =
             BreezeTest.metadata(session)

    assert {:noreply, "action", true} =
             BreezeTest.click(session, "action", action: :release)

    assert %{assigns: %{mouse_events: [_, %{action: "release"}]}} =
             BreezeTest.metadata(session)
  end

  test "returns interaction errors for missing targets and out-of-bounds points", %{
    session: session
  } do
    assert {:error, {:mouse_target_not_found, "missing"}} =
             BreezeTest.click(session, "missing")

    assert {:error, {:point_outside_element, "action", {99, 0}}} =
             BreezeTest.click(session, "action", at: {99, 0})
  end

  test "wheels a scrollable element by ID with a repeat count", %{session: session} do
    assert {:noreply, "items", true} = BreezeTest.focus(session, "items")

    assert {:noreply, "items", true} = BreezeTest.wheel(session, "items", :down, repeat: 2)

    assert %{implicit_state: %{"items" => {Breeze.Implicit.Scroll, %{offset_y: 2}}}} =
             BreezeTest.metadata(session)
  end

  test "rejects invalid resize and mouse options", %{session: session} do
    assert_raise ArgumentError, ~r/expected size/, fn ->
      BreezeTest.resize(session, {0, 10})
    end

    assert_raise ArgumentError, ~r/expected :action/, fn ->
      BreezeTest.click(session, "action", action: :double)
    end

    assert_raise ArgumentError, ~r/expected :repeat/, fn ->
      BreezeTest.wheel(session, "items", :down, repeat: 0)
    end

    assert_raise ArgumentError, ~r/expected wheel direction/, fn ->
      BreezeTest.wheel(session, "items", :left)
    end
  end
end
