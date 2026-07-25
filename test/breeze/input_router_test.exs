defmodule Breeze.InputRouterTest do
  use ExUnit.Case, async: true

  import Breeze.TestSupport.ProcessHelpers,
    only: [start_app_server: 1, start_input_router: 1, stop_gen_server: 1]

  import Breeze.TestSupport.WaitUntil

  alias Breeze.ChildServer
  alias Breeze.Theme

  defmodule FakeAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(opts) do
      ref = make_ref()
      owner = Keyword.get(opts, :owner)

      if owner do
        send(owner, {:terminal_started, self(), ref})
      end

      {:ok, %{ref: ref, size: %{width: 80, height: 24}, owner: owner}}
    end

    def reader(term), do: {:ok, term.ref}

    def write(%{owner: owner} = term, str) when is_pid(owner) do
      send(owner, {:terminal_write, str})
      {:ok, term}
    end

    def write(term, _str), do: {:ok, term}
    def resize(term), do: term.size
  end

  defmodule PaletteAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(_opts) do
      {:ok, %{ref: make_ref(), size: %{width: 80, height: 24}}}
    end

    def reader(term), do: {:ok, term.ref}
    def resize(term), do: term.size

    def write(term, str) do
      if String.contains?(str, "\e]10;?") do
        owner = self()
        ref = term.ref

        send(owner, {ref, {:data, "\e]10;rgb:f0f0/f0f0/f0f0\a"}})
        send(owner, {ref, {:data, "\e]11;rgb:1010/1111/1212\a"}})
        send(owner, {ref, {:data, "\e]4;1;rgb:aaaa/2222/3333\a"}})
        send(owner, {ref, {:data, "\e]4;2;rgb:2222/aaaa/3333\a"}})
        send(owner, {ref, {:data, "\e]4;3;rgb:cccc/bbbb/3333\a"}})
        send(owner, {ref, {:data, "\e]4;4;rgb:3333/5555/aaaa\a"}})
        send(owner, {ref, {:data, "\e]4;5;rgb:9999/3333/aaaa\a"}})
        send(owner, {ref, {:data, "\e]4;6;rgb:3333/aaaa/aaaa\a"}})
        send(owner, {ref, {:data, "\e]4;9;rgb:dddd/6666/4444\a"}})
        send(owner, {ref, {:data, "\e]4;10;rgb:4444/cccc/5555\a"}})
        send(owner, {ref, {:data, "\e]4;11;rgb:e6e6/d1d1/5a5a\a"}})
        send(owner, {ref, {:data, "\e]4;12;rgb:5f5f/7b7b/e0e0\a"}})
        send(owner, {ref, {:data, "\e]4;13;rgb:b3b3/6b6b/d4d4\a"}})
        send(owner, {ref, {:data, "\e]4;14;rgb:5a5a/d6d6/d6d6\a"}})
      end

      {:ok, term}
    end
  end

  defmodule SplitPaletteAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(_opts) do
      {:ok, %{ref: make_ref(), size: %{width: 80, height: 24}}}
    end

    def reader(term), do: {:ok, term.ref}
    def resize(term), do: term.size

    def write(term, str) do
      if String.contains?(str, "\e]10;?") do
        owner = self()
        ref = term.ref

        send(owner, {ref, {:data, "\e]10;rgb:f0f0/f0f0/f0f0\a"}})
        send(owner, {ref, {:data, "\e]11;rgb:1010/1111/1212\a"}})
        send(owner, {ref, {:data, "\e]4;1;rgb:aaaa/2222/3333\a"}})
        send(owner, {ref, {:data, "\e]4;2;rgb:2222/aaaa/3333\a"}})
        send(owner, {ref, {:data, "\e]4;3;rgb:cccc/bbbb/3333\a"}})
        send(owner, {ref, {:data, "\e]4;4;rgb:3333/5555/aaaa\a"}})
        send(owner, {ref, {:data, "\e]4;5;rgb:9999/3333/aaaa\a"}})
        send(owner, {ref, {:data, "\e]4;6;rgb:3333/aaaa/aaaa\a"}})
        send(owner, {ref, {:data, "\e]4;9;rgb:dddd/6666/4444\a"}})
        send(owner, {ref, {:data, "\e]4;10;rgb:4444/cccc/5555\a"}})
        send(owner, {ref, {:data, "\e]4;11;rgb:e6e6/d1d1/5a5a\a"}})
        send(owner, {ref, {:data, "\e]4;12;rgb:5f5f/7b7b/e0e0\a"}})
        send(owner, {ref, {:data, "\e]4;13;rgb:b3b3/6b6b/d4d4\a"}})
        send(owner, {ref, {:data, "\e]"}})
        send(owner, {ref, {:data, "4;14;rgb:5a5a/d6d6/d6d6\a"}})
      end

      {:ok, term}
    end
  end

  defmodule DelayedPaletteAdapter do
    @behaviour Termite.Terminal.Adapter

    @late_palette_reply "\e]4;5;rgb:9999/3333/aaaa\a" <>
                          "\e]4;6;rgb:3333/aaaa/aaaa\a" <>
                          "\e]4;9;rgb:dddd/6666/4444\a" <>
                          "\e]4;10;rgb:4444/cccc/5555\a" <>
                          "\e]4;11;rgb:e6e6/d1d1/5a5a\a" <>
                          "\e]4;12;rgb:5f5f/7b7b/e0e0\a" <>
                          "\e]4;13;rgb:b3b3/6b6b/d4d4\a" <>
                          "\e]4;14;rgb:5a5a/d6d6/d6d6\a"

    def start(opts) do
      {:ok,
       %{
         ref: make_ref(),
         size: %{width: 80, height: 24},
         owner: Keyword.fetch!(opts, :owner)
       }}
    end

    def reader(term), do: {:ok, term.ref}
    def resize(term), do: term.size
    def late_reply(reader), do: {reader, {:data, @late_palette_reply}}

    def write(term, str) do
      if String.contains?(str, "\e]10;?") do
        ref = term.ref

        send(self(), {ref, {:data, "\e]10;rgb:f0f0/f0f0/f0f0\a"}})
        send(self(), {ref, {:data, "\e]11;rgb:1010/1111/1212\a"}})
        send(self(), {ref, {:data, "\e]4;1;rgb:aaaa/2222/3333\a"}})
        send(self(), {ref, {:data, "\e]4;2;rgb:2222/aaaa/3333\a"}})
        send(self(), {ref, {:data, "\e]4;3;rgb:cccc/bbbb/3333\a"}})
        send(self(), {ref, {:data, "\e]4;4;rgb:3333/5555/aaaa\a"}})
        send(term.owner, {:palette_probe_partial_sent, self()})
      end

      {:ok, term}
    end
  end

  defmodule BlockingView do
    use Breeze.View

    def mount(opts, term) do
      {:ok, assign(term, parent: Keyword.fetch!(opts, :parent))}
    end

    def render(assigns) do
      ~H"""
      <box>blocking</box>
      """
    end

    def handle_event(_, %{"key" => "r"}, term) do
      send(term.assigns.parent, :started)

      receive do
        :unblock -> :ok
      end

      send(term.assigns.parent, :finished)
      {:noreply, term}
    end

    def handle_event(_, %{"key" => "n"}, term) do
      send(term.assigns.parent, :next_handled)
      {:noreply, term}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule FocusedInputView do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term) do
      {:ok, term |> focus("url") |> assign(url: "hello")}
    end

    def render(assigns) do
      ~H"""
      <box style="inline width-24">
        <.input id="url" input-value={@url} br-change="url_changed" style="width-full">{@url}</.input>
        <box style="width-4">tail</box>
      </box>
      """
    end

    def handle_event("url_changed", %{value: value}, term) do
      {:noreply, assign(term, url: value)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule CapturingImplicit do
    def init(_children, _attrs, state) do
      {:ok, state,
       active_when_focused: true,
       captures_printable_keys: true,
       captures_control_keys: true,
       captures_focus_keys: true}
    end

    def handle_event(_, event, state), do: {{:change, event}, state}
    def handle_modifiers(_, _, _), do: []
    def animate(_, box, _, _, _), do: box
  end

  defmodule FocusedCaptureView do
    use Breeze.View

    def mount(opts, term) do
      {:ok, term |> focus("capture") |> assign(parent: Keyword.fetch!(opts, :parent))}
    end

    def render(assigns) do
      ~H"""
      <box>
        <box
          id="capture"
          focusable
          implicit={Breeze.InputRouterTest.CapturingImplicit}
          br-change="captured"
        >
          capture
        </box>
        <box id="other" focusable>other</box>
      </box>
      """
    end

    def handle_event("captured", event, term) do
      send(term.assigns.parent, {:captured, event})
      {:noreply, term}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule FocusCycleView do
    use Breeze.View

    def mount(_opts, term), do: {:ok, focus(term, "one")}

    def render(assigns) do
      ~H"""
      <box>
        <box id="one" focusable>One</box>
        <box id="two" focusable>Two</box>
        <box id="three" focusable>Three</box>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule ThemeSwitchView do
    use Breeze.View

    def mount(_opts, term) do
      {:ok,
       term
       |> put_theme(Theme.builtin(:gruvbox))
       |> assign(actual_theme_mode: term.theme.mode, theme_status: Theme.probe_status(term.theme))}
    end

    def render(assigns) do
      ~H"""
      <box class="text-primary">mode={@actual_theme_mode} status={@theme_status}</box>
      """
    end

    def handle_event(_, %{"key" => "t"}, term) do
      term = put_theme(term, :system)

      {:noreply,
       assign(term,
         actual_theme_mode: term.theme.mode,
         theme_status: Theme.probe_status(term.theme)
       )}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule SessionChildView do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box>child</box>
      """
    end
  end

  defmodule SessionRootView do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box>
        <live id="child" view={SessionChildView}>
        </live>
      </box>
      """
    end
  end

  defmodule ThemeProbeLeakView do
    use Breeze.View

    def mount(opts, term) do
      {:ok,
       term
       |> put_theme(Theme.builtin(:gruvbox))
       |> assign(parent: Keyword.fetch!(opts, :parent))}
    end

    def render(assigns) do
      ~H"""
      <box>probe</box>
      """
    end

    def handle_event(_, %{"key" => "t"}, term) do
      send(term.assigns.parent, :theme_switch)
      {:noreply, put_theme(term, :system)}
    end

    def handle_event(_, event, term) do
      send(term.assigns.parent, {:leaked_input, event})
      {:noreply, term}
    end

    def handle_info(_, term), do: {:noreply, term}
  end

  test "input router owns the session view supervisor and stops it on hangup" do
    parent = self()

    {:ok, router} =
      start_input_router(
        view: SessionRootView,
        alt_screen: false,
        hide_cursor: false,
        terminal_opts: [adapter: FakeAdapter],
        halt_fun: fn -> send(parent, :halted) end
      )

    router_state = :sys.get_state(router)
    server = router_state.server_pid
    supervisor = router_state.child_view_supervisor

    assert is_nil(router_state.remote_inspector_supervisor)

    server_state =
      wait_until(fn ->
        state = :sys.get_state(server)
        if Map.has_key?(state.children, "child"), do: state
      end)

    root = server_state.view_pid
    child = server_state.children["child"].pid

    assert server_state.child_view_supervisor == supervisor
    refute server_state.owns_child_view_supervisor?
    assert is_nil(server_state.remote_inspector_supervisor)

    supervised_pids =
      supervisor
      |> DynamicSupervisor.which_children()
      |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)

    assert root in supervised_pids
    assert child in supervised_pids

    router_ref = Process.monitor(router)
    send(router, {router_state.reader, {:signal, :hup}})

    assert_receive :halted, 500
    assert_receive {:DOWN, ^router_ref, :process, ^router, :normal}, 500

    wait_until(fn ->
      Enum.all?([supervisor, server, root, child], &(not Process.alive?(&1)))
    end)
  end

  test "stopping the input router also stops its app server" do
    parent = self()

    {:ok, router} =
      start_input_router(
        view: BlockingView,
        start_opts: [parent: parent],
        hide_cursor: false,
        terminal_opts: [adapter: FakeAdapter],
        halt_fun: fn -> send(parent, :halted) end
      )

    server = :sys.get_state(router).server_pid
    server_ref = Process.monitor(server)

    assert :ok = stop_gen_server(router)
    assert_receive :halted, 500
    assert_receive {:DOWN, ^server_ref, :process, ^server, :shutdown}, 500
  end

  test "stop global keys are handled even while the app server is blocked" do
    parent = self()

    {:ok, pid} =
      start_input_router(
        view: BlockingView,
        start_opts: [parent: parent],
        hide_cursor: false,
        terminal_opts: [adapter: FakeAdapter],
        halt_fun: fn -> send(parent, :halted) end,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    ref = Process.monitor(pid)
    reader = :sys.get_state(pid).reader

    send(pid, {reader, {:data, "r"}})
    assert_receive :started, 500

    send(pid, {reader, {:data, "q"}})
    assert_receive :halted, 500
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
  end

  test "input queued during an asynchronous dispatch is handled after it completes" do
    parent = self()
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      start_app_server(
        view: BlockingView,
        start_opts: [parent: parent],
        terminal: terminal
      )

    on_exit(fn -> Process.exit(pid, :shutdown) end)
    view_pid = :sys.get_state(pid).view_pid

    send(pid, {reader, {:data, "r"}})
    assert_receive :started, 500

    send(pid, {reader, {:data, "n"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      not :queue.is_empty(state.input.queued_input)
    end)

    send(view_pid, :unblock)

    assert_receive :finished, 500
    assert_receive :next_handled, 500
  end

  test "ctrl-c always halts regardless of global keybindings" do
    assert_ctrl_c_halts("\x03")
    assert_ctrl_c_halts("\e[99;5u")
    assert_ctrl_c_halts("\e[27;5;99u")
    assert_ctrl_c_halts("\e[27;5;99~")
  end

  test "ctrl-c halts even when a focused implicit captures printable input" do
    parent = self()

    {:ok, pid} =
      start_input_router(
        view: FocusedInputView,
        hide_cursor: false,
        terminal_opts: [adapter: FakeAdapter],
        halt_fun: fn -> send(parent, :halted) end
      )

    ref = Process.monitor(pid)
    state = :sys.get_state(pid)
    reader = state.reader
    server_pid = state.server_pid

    wait_until(fn ->
      match?(
        %{captures_printable_keys: true},
        Breeze.Server.focused_implicit_metadata(server_pid)
      )
    end)

    send(pid, {reader, {:data, "\e[99;5u"}})

    assert_receive :halted, 500
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
  end

  test "ctrl-c is forwarded when a focused implicit captures control keys" do
    parent = self()

    {:ok, pid} =
      start_input_router(
        view: FocusedCaptureView,
        start_opts: [parent: parent],
        hide_cursor: false,
        terminal_opts: [adapter: FakeAdapter],
        halt_fun: fn -> send(parent, :halted) end
      )

    state = :sys.get_state(pid)
    reader = state.reader
    server_pid = state.server_pid

    wait_until(fn ->
      match?(
        %{captures_control_keys: true},
        Breeze.Server.focused_implicit_metadata(server_pid)
      )
    end)

    send(pid, {reader, {:data, "\x03"}})

    assert_receive {:captured, %{"ctrlKey" => true, "key" => "c"}}
    _state = :sys.get_state(pid)
    refute_received :halted

    stop_gen_server(pid)
  end

  test "captured printable chunks are delivered as individual keys without batching opt-in" do
    parent = self()

    {:ok, pid} =
      start_input_router(
        view: FocusedCaptureView,
        start_opts: [parent: parent],
        hide_cursor: false,
        terminal_opts: [adapter: FakeAdapter],
        halt_fun: fn -> send(parent, :halted) end
      )

    state = :sys.get_state(pid)
    reader = state.reader
    server_pid = state.server_pid

    wait_until(fn ->
      match?(
        %{captures_printable_keys: true},
        Breeze.Server.focused_implicit_metadata(server_pid)
      )
    end)

    send(pid, {reader, {:data, "wwa"}})

    for expected <- ["w", "w", "a"] do
      assert_receive {:captured, %{"key" => ^expected} = event}
      refute Map.has_key?(event, "__batched_printable__")
    end

    _state = :sys.get_state(pid)
    refute_received :halted
    stop_gen_server(pid)
  end

  test "tab and shift-tab are forwarded when a focused implicit captures focus keys" do
    parent = self()

    {:ok, pid} =
      start_input_router(
        view: FocusedCaptureView,
        start_opts: [parent: parent],
        hide_cursor: false,
        terminal_opts: [adapter: FakeAdapter],
        halt_fun: fn -> send(parent, :halted) end
      )

    state = :sys.get_state(pid)
    reader = state.reader
    server_pid = state.server_pid

    wait_until(fn ->
      match?(
        %{captures_focus_keys: true},
        Breeze.Server.focused_implicit_metadata(server_pid)
      )
    end)

    send(pid, {reader, {:data, "\t"}})
    assert_receive {:captured, %{"key" => "\t"}}

    send(pid, {reader, {:data, "\e[9;2u"}})
    assert_receive {:captured, %{"key" => "ShiftTab"}}

    _state = :sys.get_state(pid)
    refute_received :halted
    assert :sys.get_state(server_pid).focused == "capture"

    stop_gen_server(pid)
  end

  defp assert_ctrl_c_halts(sequence) do
    parent = self()

    {:ok, pid} =
      start_input_router(
        view: BlockingView,
        start_opts: [parent: parent],
        hide_cursor: false,
        terminal_opts: [adapter: FakeAdapter],
        halt_fun: fn -> send(parent, :halted) end,
        global_keybindings: []
      )

    ref = Process.monitor(pid)
    reader = :sys.get_state(pid).reader

    send(pid, {reader, {:data, sequence}})

    assert_receive :halted, 500
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
  end

  test "alt_screen false skips alternate screen enter and exit while preserving input" do
    parent = self()

    {:ok, pid} =
      start_input_router(
        view: BlockingView,
        start_opts: [parent: parent],
        alt_screen: false,
        hide_cursor: false,
        terminal_opts: [adapter: FakeAdapter, owner: parent],
        halt_fun: fn -> send(parent, :halted) end,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    state = :sys.get_state(pid)
    reader = state.reader

    refute_received {:terminal_write, "\e[?1049h"}

    send(pid, {reader, {:data, "r"}})
    assert_receive :started, 500

    send(pid, {reader, {:data, "q"}})
    assert_receive :halted, 500

    refute_received {:terminal_write, "\e[?1049l"}
  end

  test "alt screen is enabled by default" do
    parent = self()

    {:ok, pid} =
      start_input_router(
        view: BlockingView,
        start_opts: [parent: parent],
        hide_cursor: false,
        terminal_opts: [adapter: FakeAdapter, owner: parent],
        halt_fun: fn -> send(parent, :halted) end,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    assert_receive {:terminal_write, "\e[?1049h"}

    state = :sys.get_state(pid)
    send(pid, {state.reader, {:data, "q"}})

    assert_receive :halted, 500
    assert_receive {:terminal_write, "\e[?1049l"}
  end

  test "enhanced keyboard mode is enabled by default and reset on stop" do
    parent = self()

    {:ok, pid} =
      start_input_router(
        view: BlockingView,
        start_opts: [parent: parent],
        hide_cursor: false,
        terminal_opts: [adapter: FakeAdapter, owner: parent],
        halt_fun: fn -> send(parent, :halted) end,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    assert_receive {:terminal_write, "\e[>1u\e[>4;2m"}

    state = :sys.get_state(pid)
    send(pid, {state.reader, {:data, "q"}})

    assert_receive :halted, 500
    assert_receive {:terminal_write, "\e[<u\e[>4;0m"}
  end

  test "enhanced shift-tab moves focus backward" do
    assert_enhanced_shift_tab_moves_focus_backward("\e[9;2u")
    assert_enhanced_shift_tab_moves_focus_backward("\e[9;2:1u")
    assert_enhanced_shift_tab_moves_focus_backward("\e[1;2Z")
  end

  test "structured shift-tab moves focus backward" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      start_app_server(
        view: FocusCycleView,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    on_exit(fn -> stop_gen_server(pid) end)

    wait_until(fn ->
      :sys.get_state(pid).focused == "one"
    end)

    assert {:noreply, "two", true} =
             Breeze.ChildServer.dispatch_input(
               :sys.get_state(pid).view_pid,
               "\t",
               invalidate: false
             )

    assert {:noreply, "one", true} =
             Breeze.ChildServer.dispatch_input(
               :sys.get_state(pid).view_pid,
               %{"key" => "\t", "shiftKey" => true},
               invalidate: false
             )
  end

  defp assert_enhanced_shift_tab_moves_focus_backward(sequence) do
    parent = self()

    {:ok, pid} =
      start_input_router(
        view: FocusCycleView,
        hide_cursor: false,
        terminal_opts: [adapter: FakeAdapter],
        halt_fun: fn -> send(parent, :halted) end,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    state = :sys.get_state(pid)
    reader = state.reader
    server_pid = state.server_pid

    wait_until(fn ->
      :sys.get_state(server_pid).focused == "one"
    end)

    send(pid, {reader, {:data, "\t"}})

    wait_until(fn ->
      :sys.get_state(server_pid).focused == "two"
    end)

    send(pid, {reader, {:data, sequence}})

    wait_until(fn ->
      :sys.get_state(server_pid).focused == "one"
    end)

    send(pid, {reader, {:data, "q"}})
    assert_receive :halted, 500
  end

  test "enhanced keyboard mode can be disabled" do
    parent = self()

    {:ok, pid} =
      start_input_router(
        view: BlockingView,
        start_opts: [parent: parent],
        enhanced_keyboard: false,
        hide_cursor: false,
        terminal_opts: [adapter: FakeAdapter, owner: parent],
        halt_fun: fn -> send(parent, :halted) end,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    refute_received {:terminal_write, "\e[>1u\e[>4;2m"}

    state = :sys.get_state(pid)
    send(pid, {state.reader, {:data, "q"}})

    assert_receive :halted, 500
    refute_received {:terminal_write, "\e[<u\e[>4;0m"}
  end

  test "injected terminals use terminal.reader without an explicit reader option" do
    parent = self()
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      start_input_router(
        view: BlockingView,
        start_opts: [parent: parent],
        hide_cursor: false,
        terminal: terminal,
        halt_fun: fn -> send(parent, :halted) end,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    ref = Process.monitor(pid)
    reader = terminal.reader

    send(pid, {reader, {:data, "r"}})
    assert_receive :started, 500

    send(pid, {reader, {:data, "q"}})
    assert_receive :halted, 500
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
  end

  test "Server.run blocks until the app stops without halting" do
    parent = self()

    task =
      Task.async(fn ->
        Breeze.Server.run(
          view: BlockingView,
          start_opts: [parent: parent],
          hide_cursor: false,
          terminal_opts: [adapter: FakeAdapter, owner: parent],
          global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
        )
      end)

    assert_receive {:terminal_started, router_pid, reader}, 1_000

    wait_until(fn ->
      case Process.info(task.pid, [:current_function, :monitors]) do
        [
          {:current_function, {Breeze.Server, :run, 1}},
          {:monitors, monitors}
        ] ->
          {:process, router_pid} in monitors

        nil ->
          false

        _other ->
          false
      end
    end)

    refute Task.yield(task, 0)

    send(router_pid, {reader, {:data, "q"}})

    assert Task.await(task) == :ok
  end

  test "stop global keys do not halt when a focused implicit captures printable input" do
    parent = self()

    {:ok, pid} =
      start_input_router(
        view: FocusedInputView,
        hide_cursor: false,
        terminal_opts: [adapter: FakeAdapter],
        halt_fun: fn -> send(parent, :halted) end,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    state = :sys.get_state(pid)
    reader = state.reader
    server_pid = state.server_pid

    wait_until(fn ->
      match?(
        %{captures_printable_keys: true},
        Breeze.Server.focused_implicit_metadata(server_pid)
      )
    end)

    send(pid, {reader, {:data, "q"}})

    wait_until(fn ->
      :sys.get_state(server_pid).frame.base_output =~ "helloq"
    end)

    _state = :sys.get_state(pid)
    refute_received :halted

    stop_gen_server(pid)
  end
end

defmodule Breeze.InputRouterThemeSyncTest do
  use ExUnit.Case, async: true

  import Breeze.TestSupport.ProcessHelpers,
    only: [start_input_router: 1, stop_gen_server: 1]

  import Breeze.TestSupport.WaitUntil

  alias Breeze.ChildServer

  alias Breeze.InputRouterTest.{
    DelayedPaletteAdapter,
    PaletteAdapter,
    SplitPaletteAdapter,
    ThemeProbeLeakView,
    ThemeSwitchView
  }

  test "switching to system theme after startup promotes to probed system mode" do
    parent = self()

    {:ok, pid} =
      start_input_router(
        view: ThemeSwitchView,
        hide_cursor: false,
        terminal_opts: [adapter: PaletteAdapter],
        halt_fun: fn -> send(parent, :halted) end
      )

    state = :sys.get_state(pid)
    reader = state.reader
    server_pid = state.server_pid
    child_pid = :sys.get_state(server_pid).view_pid

    assert ChildServer.metadata(child_pid).theme.mode == :custom

    send(pid, {reader, {:data, "t"}})

    wait_until(
      fn ->
        metadata = ChildServer.metadata(child_pid)

        metadata.theme.mode == :system and
          metadata.theme.variables[:palette_probe_status] == :ready
      end,
      500
    )

    wait_until(
      fn ->
        :sys.get_state(server_pid).frame.base_output =~ "mode=system status=ready"
      end,
      500
    )

    stop_gen_server(pid)
  end

  test "split runtime palette replies are consumed instead of forwarded as input" do
    parent = self()

    {:ok, pid} =
      start_input_router(
        view: ThemeProbeLeakView,
        start_opts: [parent: parent],
        hide_cursor: false,
        terminal_opts: [adapter: SplitPaletteAdapter],
        halt_fun: fn -> send(parent, :halted) end
      )

    state = :sys.get_state(pid)
    reader = state.reader
    server_pid = state.server_pid
    child_pid = :sys.get_state(server_pid).view_pid

    send(pid, {reader, {:data, "t"}})
    assert_receive :theme_switch

    wait_until(
      fn ->
        metadata = ChildServer.metadata(child_pid)

        metadata.theme.mode == :system and
          metadata.theme.variables[:palette_probe_status] == :ready
      end,
      500
    )

    _state = :sys.get_state(pid)
    refute_received {:leaked_input, _event}

    stop_gen_server(pid)
  end

  test "late runtime palette replies are drained instead of forwarded as input" do
    parent = self()

    {:ok, pid} =
      start_input_router(
        view: ThemeProbeLeakView,
        start_opts: [parent: parent],
        hide_cursor: false,
        terminal_opts: [adapter: DelayedPaletteAdapter, owner: parent],
        halt_fun: fn -> send(parent, :halted) end
      )

    state = :sys.get_state(pid)
    reader = state.reader
    server_pid = state.server_pid
    child_pid = :sys.get_state(server_pid).view_pid

    send(pid, {reader, {:data, "t"}})
    assert_receive :theme_switch
    assert_receive {:palette_probe_partial_sent, ^pid}

    probe = :sys.get_state(pid).theme_probe
    send(pid, {:theme_probe_timeout, probe.key, probe.ref})
    _state = :sys.get_state(pid)
    send(pid, DelayedPaletteAdapter.late_reply(reader))

    wait_until(
      fn ->
        metadata = ChildServer.metadata(child_pid)

        metadata.theme.mode == :system and
          metadata.theme.variables[:palette_probe_status] == :ready
      end,
      400
    )

    _state = :sys.get_state(pid)
    refute_received {:leaked_input, _event}

    stop_gen_server(pid)
  end
end
