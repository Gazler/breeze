defmodule Breeze.LiveView.CrashTest do
  use Breeze.TestSupport.LiveViewCase, async: true

  import Breeze.TestSupport.LiveViewHelpers

  test "server renders a crash screen instead of tearing down the terminal on view exceptions" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        start_app_server(
          view: CrashingView,
          terminal: terminal,
          global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
        )

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)

        state.crash &&
          state.frame.base_output =~ "Breeze Error" &&
          state.frame.base_output =~ "CrashingView" &&
          state.frame.base_output =~ "RuntimeError"
      end)

      state = :sys.get_state(pid)

      assert state.crash
      assert state.frame.base_output =~ "Breeze Error"
      assert state.frame.base_output =~ "CrashingView"
      assert state.frame.base_output =~ "RuntimeError"
      assert state.frame.base_output =~ "Crash Details"
      assert state.frame.base_output =~ "Selected Frame"
      assert state.frame.base_output =~ "Stacktrace"
      assert state.frame.base_output =~ "boom"
      assert Breeze.ErrorView.frame_count(state.crash) > 1
      refute state.frame.base_output =~ "No structured stacktrace captured"

      stop_gen_server(pid)
    end)
  end

  test "server preserves nested live render crashes" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)

      {:ok, pid} = start_app_server(view: RenderCrashingRoot, terminal: terminal)

      wait_until(fn -> :sys.get_state(pid).crash end)

      state = :sys.get_state(pid)

      assert Process.alive?(pid)
      assert Process.alive?(state.view_pid)
      assert %RuntimeError{message: "nested render boom"} = state.crash.reason
      assert state.crash.stacktrace != []
      assert state.frame.base_output =~ "nested render boom"
      refute state.frame.base_output =~ "No structured stacktrace captured"

      stop_gen_server(pid)
    end)
  end

  test "child server ignores missing optional view callbacks" do
    refute function_exported?(RenderOnlyChild, :handle_event, 3)
    refute function_exported?(RenderOnlyChild, :handle_info, 2)

    {:ok, pid} = start_child_server(view: RenderOnlyChild, start_opts: [])

    assert {:noreply, "root", false} = ChildServer.dispatch_input(pid, "x")

    assert {:noreply, "root", false} =
             ChildServer.dispatch_event(pid, :input, %{"key" => "x"})

    assert {:noreply, "root"} = ChildServer.dispatch_info(pid, :message)
  end

  test "server renders configured error view on view exceptions" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        start_app_server(
          view: CrashingView,
          terminal: terminal,
          render_errors: [view: CustomErrorView],
          global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
        )

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)

        state.crash &&
          state.frame.base_output =~ "Custom Error View" &&
          state.frame.base_output =~ "View: Breeze.LiveViewTest.CrashingView" &&
          state.frame.base_output =~ "Kind: :error" &&
          state.frame.base_output =~ "Crash: %RuntimeError"
      end)

      stop_gen_server(pid)
    end)
  end

  test "custom error view without keybindings ignores built-in crash keypresses" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        start_app_server(
          view: CrashingView,
          terminal: terminal,
          render_errors: [view: CustomErrorView]
        )

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)

        state.crash &&
          state.frame.base_output =~ "Custom Error View"
      end)

      send(pid, {reader, {:data, "r"}})

      state = :sys.get_state(pid)
      assert state.crash
      assert state.frame.base_output =~ "Custom Error View"

      stop_gen_server(pid)
    end)
  end

  test "custom error view handles crash keypresses through render_errors keybindings" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        start_app_server(
          view: CrashingView,
          terminal: terminal,
          render_errors: [
            view: KeybindingErrorView,
            keybindings: [{"r", "Restart", :restart}]
          ]
        )

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)

        state.crash &&
          state.frame.base_output =~ "Keybinding Error View" &&
          state.frame.base_output =~ "r" &&
          state.frame.base_output =~ "Restart"
      end)

      send(pid, {reader, {:data, "r"}})

      wait_until(fn ->
        state = :sys.get_state(pid)

        is_nil(state.crash) &&
          state.frame.base_output =~ "ready"
      end)

      stop_gen_server(pid)
    end)
  end

  test "custom error view supports a hard restart keybinding" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        start_app_server(
          view: StatefulCrashRoot,
          terminal: terminal,
          render_errors: [
            view: KeybindingErrorView,
            keybindings: [{"R", "Hard restart", :hard_restart}]
          ]
        )

      root_pid = :sys.get_state(pid).view_pid

      assert {:noreply, "child"} =
               Breeze.ChildServer.dispatch_info(root_pid, {:set_slide, 7})

      assert {:crash, %{} = _crash} = Breeze.Server.dispatch_live_input(pid, "child", "c")

      wait_until(fn ->
        state = :sys.get_state(pid)

        state.crash &&
          state.frame.base_output =~ "Keybinding Error View" &&
          state.frame.base_output =~ "Hard restart"
      end)

      send(pid, {reader, {:data, "R"}})

      wait_until(fn ->
        state = :sys.get_state(pid)

        is_nil(state.crash) &&
          state.frame.base_output =~ "slide 1"
      end)

      stop_gen_server(pid)
    end)
  end

  test "custom error view copies details through render_errors keybindings" do
    parent = self()

    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        start_app_server(
          view: CrashingView,
          terminal: terminal,
          render_errors: [
            view: CustomErrorView,
            keybindings: [{"y", "Copy details", :copy_details}]
          ],
          internal: [
            clipboard: [
              copy_fun: fn text ->
                send(parent, {:copied_custom_error_details, text})
                {:ok, "test-clipboard"}
              end
            ]
          ]
        )

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)

        state.crash &&
          state.frame.base_output =~ "Custom Error View"
      end)

      send(pid, {reader, {:data, "y"}})

      assert_receive {:copied_custom_error_details, details}
      assert details =~ "Breeze Error"
      assert details =~ "CrashingView"
      assert details =~ "RuntimeError"

      wait_until(fn ->
        case :sys.get_state(pid).crash do
          %{notice: "Copied crash details to test-clipboard."} -> true
          _ -> false
        end
      end)

      stop_gen_server(pid)
    end)
  end

  test "crash screen tab switches focus between panes" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        start_app_server(
          view: CrashingView,
          terminal: terminal,
          global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
        )

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        state.crash && state.crash.focused == "error-stacktrace"
      end)

      initial_state = :sys.get_state(pid)
      assert initial_state.crash
      assert initial_state.crash.focused == "error-stacktrace"

      initial_assigns =
        Breeze.ErrorView.render_assigns(CrashingView, initial_state.crash, terminal.size)

      assert initial_assigns.stacktrace_list_width > 10

      send(pid, {reader, {:data, "\t"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        state.crash && state.crash.focused == "error-history"
      end)

      next_state = :sys.get_state(pid)
      assert next_state.crash.focused == "error-history"

      assigns = Breeze.ErrorView.render_assigns(CrashingView, next_state.crash, terminal.size)
      assert assigns.stacktrace_list_width == 10
      assert assigns.history_scroll_width > 50

      stop_gen_server(pid)
    end)
  end

  test "crash screen q quits the server" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        start_app_server(
          view: CrashingView,
          terminal: terminal,
          global_keybindings: [{"^c", "Quit", fn _event, term -> {:stop, term} end}]
        )

      ref = Process.monitor(pid)

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        state.crash && state.frame.base_output =~ "Breeze Error"
      end)

      send(pid, {reader, {:data, "q"}})

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
    end)
  end

  test "crash details text wraps to the details pane width" do
    crash = %{
      kind: :error,
      reason:
        RuntimeError.exception(
          "a long crash message with enough words to wrap inside the details pane instead of scrolling horizontally"
        ),
      stacktrace: [
        {Very.Long.CrashHandler.ModuleName.ForWrapping, :function_name_with_a_long_suffix, 3,
         [file: ~c"test/support/a/very/long/path/to/a/crashing/file_for_wrapping.exs", line: 123]}
      ],
      selected_index: nil,
      focused: "error-stacktrace",
      implicit_state: %{}
    }

    assigns = Breeze.ErrorView.render_assigns(CrashingView, crash, %{width: 60, height: 20})

    assert assigns.history_content_width == assigns.history_scroll_width
    assert Enum.any?(assigns.history_lines, &String.contains?(&1, "horizontally"))
    assert Enum.all?(assigns.history_lines, &(String.length(&1) <= assigns.history_scroll_width))
  end

  test "crash screen keypresses patch rows instead of forcing full redraws" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
      reader = terminal.reader

      {:ok, pid} =
        start_app_server(
          view: CrashingView,
          terminal: terminal,
          global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
        )

      drain_terminal_writes()
      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        state.crash && state.frame.base_output =~ "Breeze Error"
      end)

      drain_terminal_writes()
      send(pid, {reader, {:data, "\t"}})

      writes =
        wait_until(fn ->
          writes = drain_terminal_writes()

          if :sys.get_state(pid).crash.focused == "error-history" and writes != [] do
            IO.iodata_to_binary(writes)
          else
            false
          end
        end)

      refute writes =~ "\e[2J"
      assert writes =~ "Crash Details"

      stop_gen_server(pid)
    end)
  end

  test "crash screen copies plain details when clipboard is available" do
    parent = self()

    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        start_app_server(
          view: CrashingView,
          terminal: terminal,
          internal: [
            clipboard: [
              copy_fun: fn text ->
                send(parent, {:copied_crash_details, text})
                {:ok, "test-clipboard"}
              end
            ]
          ],
          global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
        )

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        state.crash && state.frame.base_output =~ "Breeze Error"
      end)

      send(pid, {reader, {:data, "y"}})

      assert_receive {:copied_crash_details, details}, 500
      assert details =~ "Breeze Error"
      assert details =~ "Crash Details"
      assert details =~ "CrashingView"
      assert details =~ "RuntimeError"
      assert details =~ "boom"

      wait_until(fn ->
        :sys.get_state(pid).frame.base_output =~ "Copied crash details to test-clipboard."
      end)

      notice_ref = :sys.get_state(pid).crash.notice_ref
      send(pid, {:clear_crash_notice, notice_ref})

      wait_until(fn ->
        output = :sys.get_state(pid).frame.base_output

        output =~ "y copies details" and
          not String.contains?(output, "Copied crash details to test-clipboard.")
      end)

      stop_gen_server(pid)
    end)
  end

  test "crash screen accepts uppercase yank key" do
    parent = self()

    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        start_app_server(
          view: CrashingView,
          terminal: terminal,
          internal: [
            clipboard: [
              copy_fun: fn text ->
                send(parent, {:copied_crash_details, text})
                {:ok, "test-clipboard"}
              end
            ]
          ],
          global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
        )

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        state.crash && state.frame.base_output =~ "Breeze Error"
      end)

      send(pid, {reader, {:data, "Y"}})

      assert_receive {:copied_crash_details, details}, 500
      assert details =~ "Breeze Error"
      assert details =~ "RuntimeError"

      wait_until(fn ->
        :sys.get_state(pid).frame.base_output =~ "Copied crash details to test-clipboard."
      end)

      stop_gen_server(pid)
    end)
  end

  test "crash screen prints details to scrollback when clipboard copy times out" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
      reader = terminal.reader

      {:ok, pid} =
        start_app_server(
          view: CrashingView,
          terminal: terminal,
          internal: [
            clipboard: [
              timeout: 10,
              find_executable: fn "wl-copy" -> "/usr/bin/wl-copy" end,
              run_fun: fn _name, _path, _text ->
                Process.sleep(1_000)
                {:ok, "slow-copy"}
              end
            ]
          ],
          global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
        )

      drain_terminal_writes()

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        state.crash && state.frame.base_output =~ "Breeze Error"
      end)

      drain_terminal_writes()
      send(pid, {reader, {:data, "y"}})

      writes =
        wait_until(fn ->
          writes = drain_terminal_writes()
          output = IO.iodata_to_binary(writes)

          if output =~ "Crash Details" and output =~ "Clipboard copy failed: :timeout" and
               output =~ "Press q to quit, r to resume, R to hard restart." do
            output
          else
            false
          end
        end)

      assert writes =~ "\e[?1049l"
      assert writes =~ "Breeze Error"
      assert writes =~ "CrashingView"
      assert writes =~ "RuntimeError"
      assert :sys.get_state(pid).alt_screen_active? == false

      drain_terminal_writes()
      send(pid, {reader, {:data, "r"}})

      restarted_state =
        wait_until(fn ->
          state = :sys.get_state(pid)

          if is_nil(state.crash) and state.frame.base_output =~ "ready" do
            state
          else
            false
          end
        end)

      assert restarted_state.alt_screen_active? == true

      restart_writes = IO.iodata_to_binary(drain_terminal_writes())
      assert restart_writes =~ "\e[?1049h"
      assert restart_writes =~ "ready"

      stop_gen_server(pid)
    end)
  end

  test "server preserves surviving root state across repeated live child crashes" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} = start_app_server(view: StatefulCrashRoot, terminal: terminal)

      root_pid = :sys.get_state(pid).view_pid

      assert {:noreply, "child"} =
               Breeze.ChildServer.dispatch_info(root_pid, {:set_slide, 7})

      assert Breeze.ChildServer.metadata(root_pid).assigns.slide == 7

      Enum.reduce(1..3, root_pid, fn _cycle, current_root_pid ->
        assert {:crash, crash} = Breeze.Server.dispatch_live_input(pid, "child", "c")
        assert %RuntimeError{message: "boom"} = crash.reason
        assert Process.alive?(current_root_pid)

        send(pid, {reader, {:data, "r"}})

        restarted_state =
          wait_until(fn ->
            state = :sys.get_state(pid)

            if is_nil(state.crash) and state.frame.base_output =~ "slide 7" do
              state
            else
              false
            end
          end)

        refute restarted_state.view_pid == current_root_pid
        assert Breeze.ChildServer.metadata(restarted_state.view_pid).assigns.slide == 7
        assert restarted_state.focused == "child"
        assert Process.alive?(restarted_state.children["child"].pid)

        restarted_state.view_pid
      end)

      stop_gen_server(pid)
    end)
  end

  test "uppercase R hard restarts a surviving root from its original start options" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} = start_app_server(view: StatefulCrashRoot, terminal: terminal)

      root_pid = :sys.get_state(pid).view_pid

      assert {:noreply, "child"} =
               Breeze.ChildServer.dispatch_info(root_pid, {:set_slide, 7})

      assert Breeze.ChildServer.metadata(root_pid).assigns.slide == 7
      assert {:crash, %{} = _crash} = Breeze.Server.dispatch_live_input(pid, "child", "c")
      assert Process.alive?(root_pid)
      assert :sys.get_state(pid).frame.base_output =~ "R hard restarts"

      send(pid, {reader, {:data, "R"}})

      restarted_state =
        wait_until(fn ->
          state = :sys.get_state(pid)

          if is_nil(state.crash) and state.frame.base_output =~ "slide 1" do
            state
          else
            false
          end
        end)

      refute restarted_state.view_pid == root_pid
      assert Breeze.ChildServer.metadata(restarted_state.view_pid).assigns.slide == 1
      assert restarted_state.focused == "child"
      assert Process.alive?(restarted_state.children["child"].pid)

      stop_gen_server(pid)
    end)
  end

  test "server restarts from a clean slate when crashed root state is unavailable" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        start_app_server(
          view: CrashingView,
          terminal: terminal,
          global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
        )

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        not is_nil(state.crash)
      end)

      crashed_state = :sys.get_state(pid)
      assert crashed_state.crash

      send(pid, {reader, {:data, "r"}})

      wait_until(fn ->
        state = :sys.get_state(pid)

        is_nil(state.crash) and state.frame.base_output =~ "ready" and
          not String.contains?(state.frame.base_output, "Breeze Error")
      end)

      restarted_state = :sys.get_state(pid)
      refute restarted_state.crash
      assert restarted_state.frame.base_output =~ "ready"
      refute restarted_state.frame.base_output =~ "Breeze Error"

      stop_gen_server(pid)
    end)
  end

  test "server patches fixed live child invalidations without rerendering the root" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    reader = terminal.reader

    {:ok, pid} =
      start_app_server(
        view: DebugToggleRoot,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    drain_terminal_writes()

    send(pid, {reader, {:data, "\eOQ"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      if Map.has_key?(state.children, "debug"), do: state, else: false
    end)

    state = :sys.get_state(pid)
    initial_render_count = state.debug.stats[:render_base_count]
    assert Map.has_key?(state.children, "debug")

    drain_terminal_writes()

    child = state.children["debug"]
    assert {:noreply, "button", true} = Breeze.ChildServer.dispatch_input(child.pid, "+")

    writes =
      wait_until(fn ->
        writes = drain_terminal_writes()
        if Enum.any?(writes, &String.contains?(&1, "Count: 2")), do: writes, else: false
      end)

    next_state = :sys.get_state(pid)

    assert next_state.debug.stats[:render_base_count] == initial_render_count
    assert Enum.any?(writes, &String.contains?(&1, "Count: 2"))

    stop_gen_server(pid)
  end

  test "server fully rerenders when an existing decoration overlaps a live child patch" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      start_app_server(
        view: Breeze.LiveViewTest.DecoratedContainerRoot,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    state =
      wait_until(fn ->
        state = :sys.get_state(pid)
        if Map.has_key?(state.children, "child"), do: state, else: false
      end)

    initial_render_count = state.debug.stats[:render_base_count]
    assert Enum.any?(state.frame.decorations, &(&1.id == "container"))

    child = state.children["child"]
    assert {:noreply, "button", true} = Breeze.ChildServer.dispatch_input(child.pid, "+")

    wait_until(fn ->
      next_state = :sys.get_state(pid)
      next_state.debug.stats[:render_base_count] > initial_render_count
    end)

    next_state = :sys.get_state(pid)

    assert next_state.debug.stats[:last_render_cause] == :child_invalidated
    assert next_state.frame.base_output =~ "Count: 2"

    stop_gen_server(pid)
  end
end
