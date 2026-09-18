defmodule Breeze.InputRouter.TerminalCleanupTest do
  use ExUnit.Case, async: true

  alias Breeze.InputRouter.TerminalCleanup
  alias Breeze.LiveViewTest.RecordingAdapter

  test "screen preservation and restoration guards are independent per terminal" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    first = TerminalCleanup.register(terminal, [])
    second = TerminalCleanup.register(terminal, [])

    refute first.guard == second.guard
    TerminalCleanup.preserve_screen(first, true)
    assert {:restored, _} = TerminalCleanup.restore(first)
    refute_received {:terminal_write, "\e[2J"}
    refute_received {:terminal_write, "\e[?1049l"}
    assert :already_restored = TerminalCleanup.restore(first)

    assert {:restored, _} = TerminalCleanup.restore(second)
    assert_received {:terminal_write, "\e[2J"}
    assert_received {:terminal_write, "\e[?1049l"}
  end

  test "explicit exit hook shares only its own terminal's latest cleanup state" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    parent = self()

    cleanup =
      TerminalCleanup.register(terminal,
        register: fn callback ->
          send(parent, {:exit_callback, callback})
          :ok
        end
      )

    assert_receive {:exit_callback, callback}
    TerminalCleanup.preserve_screen(cleanup, true)
    assert :ok = callback.(0)
    refute_received {:terminal_write, "\e[2J"}
    refute_received {:terminal_write, "\e[?1049l"}
    assert :already_restored = TerminalCleanup.restore(cleanup)
  end
end
