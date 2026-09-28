defmodule Breeze.InputRouter.JobControlTest do
  use ExUnit.Case, async: true

  alias Breeze.InputRouter.JobControl
  alias Breeze.LiveViewTest.RecordingAdapter
  alias Breeze.Server.State.Terminal

  test "suspension restores shell modes before signalling and app modes after continuation" do
    parent = self()

    job = %JobControl{
      executable: "test-kill",
      input_mode: fn mode ->
        send(parent, {:mode, mode})
        :ok
      end,
      command: fn executable, args, opts ->
        send(parent, {:command, executable, args, opts})
        {"", 0}
      end
    }

    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    state = %Terminal{
      terminal: terminal,
      alt_screen_active?: true,
      hide_cursor?: true,
      mouse_mode: true
    }

    assert {:ok, _terminal} = JobControl.suspend(job, state)
    messages = drain_messages()
    command = {:command, "test-kill", ["-s", "STOP", System.pid()], [stderr_to_stdout: true]}
    {before_stop, [^command | after_continue]} = Enum.split_while(messages, &(&1 != command))

    assert {:terminal_write, "\e[<u\e[>4;0m"} in before_stop
    assert {:terminal_write, "\e[?25h"} in before_stop
    assert {:terminal_write, "\e[?1049l"} in before_stop
    assert List.last(before_stop) == {:mode, :cooked}
    assert hd(after_continue) == {:mode, :raw}
    assert {:terminal_write, "\e[?1049h"} in after_continue
    assert {:terminal_write, "\e[>1u\e[>4;2m"} in after_continue
    assert {:terminal_write, "\e[?25l"} in after_continue
    assert {:terminal_write, "\e[?1000h"} in after_continue
    assert {:terminal_write, "\e[2J"} in after_continue
  end

  test "failed or missing kill executable restores the app and returns an error" do
    parent = self()
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    state = %Terminal{terminal: terminal, alt_screen_active?: false, hide_cursor?: false}

    for command <- [
          fn _, _, _ -> {"permission denied\n", 1} end,
          fn _, _, _ -> raise ErlangError, original: :enoent end
        ] do
      job = %JobControl{
        executable: "test-kill",
        input_mode: fn mode ->
          send(parent, {:mode, mode})
          :ok
        end,
        command: command,
        enhanced_keyboard?: false
      }

      assert {{:error, _reason}, _terminal} = JobControl.suspend(job, state)
      messages = drain_messages()
      assert {:mode, :cooked} in messages
      assert {:mode, :raw} in messages
      assert {:terminal_write, "\e[2J"} in messages
      refute {:terminal_write, "\e[?1049h"} in messages
      refute {:terminal_write, "\e[?25l"} in messages
      refute {:terminal_write, "\e[>1u\e[>4;2m"} in messages
    end
  end

  defp drain_messages do
    receive do
      message -> [message | drain_messages()]
    after
      0 -> []
    end
  end
end
