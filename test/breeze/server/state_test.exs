defmodule Breeze.Server.StateTest do
  use ExUnit.Case, async: true

  test "server state remains a flat map" do
    assert map_size(%Breeze.Server{}) <= 32
    assert map_size(%Breeze.Server.State.Terminal{}) <= 32
  end

  test "terminal grouping preserves startup options and the view-facing term" do
    terminal = Termite.Terminal.start(adapter: Breeze.LiveViewTest.FakeAdapter)

    {:ok, pid} =
      Breeze.TestSupport.ProcessHelpers.start_app_server(
        view: Breeze.LiveViewTest.CrashingView,
        terminal: terminal,
        alt_screen: false,
        hide_cursor: false,
        mouse: false
      )

    state = :sys.get_state(pid)

    assert %Breeze.Server.State.Terminal{
             terminal: ^terminal,
             alt_screen?: false,
             hide_cursor?: false,
             mouse_mode: false
           } = state.terminal_state

    term = :sys.get_state(state.view_pid)
    assert %Breeze.Term{terminal: ^terminal} = term
    assert term.terminal.reader == terminal.reader
    assert state.terminal_state.reader == terminal.reader
    assert term.assigns.breeze.clipboard == %{osc52: :unknown, supported: false}
    assert term.assigns.breeze.terminal.width == terminal.size.width
    refute Map.has_key?(term, :terminal_state)
  end
end
