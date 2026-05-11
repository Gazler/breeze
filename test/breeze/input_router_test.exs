defmodule Breeze.InputRouterTest do
  use ExUnit.Case, async: true
  import Breeze.TestSupport.WaitUntil

  alias Breeze.ChildServer
  alias Breeze.Theme

  defmodule FakeAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(opts) do
      {:ok, %{ref: make_ref(), size: %{width: 80, height: 24}, owner: Keyword.get(opts, :owner)}}
    end

    def reader(term), do: {:ok, term.ref}

    def write(%{owner: owner} = term, str) when is_pid(owner) do
      send(owner, {:terminal_write, str})
      {:ok, term}
    end

    def write(term, _str), do: {:ok, term}
    def resize(term), do: term.size
  end

  defmodule RecordingAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(opts) do
      ref = make_ref()
      owner = Keyword.fetch!(opts, :owner)
      send(owner, {:terminal_started, self(), ref})
      {:ok, %{ref: ref, owner: owner, size: %{width: 80, height: 24}}}
    end

    def reader(term), do: {:ok, term.ref}
    def resize(term), do: term.size

    def write(term, str) do
      send(term.owner, {:terminal_write, str})
      {:ok, term}
    end
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
      Process.sleep(200)
      send(term.assigns.parent, :finished)
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

  test "stop global keys are handled even while the app server is blocked" do
    parent = self()

    {:ok, pid} =
      Breeze.InputRouter.start_link(
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
    assert_receive :started

    send(pid, {reader, {:data, "q"}})
    assert_receive :halted
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end

  test "alt_screen false skips alternate screen enter and exit while preserving input" do
    parent = self()

    {:ok, pid} =
      Breeze.InputRouter.start_link(
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
    assert_receive :started

    send(pid, {reader, {:data, "q"}})
    assert_receive :halted

    refute_received {:terminal_write, "\e[?1049l"}
  end

  test "alt screen is enabled by default" do
    parent = self()

    {:ok, pid} =
      Breeze.InputRouter.start_link(
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

    assert_receive :halted
    assert_receive {:terminal_write, "\e[?1049l"}
  end

  test "enhanced keyboard mode is enabled by default and reset on stop" do
    parent = self()

    {:ok, pid} =
      Breeze.InputRouter.start_link(
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

    assert_receive :halted
    assert_receive {:terminal_write, "\e[<u\e[>4;0m"}
  end

  test "enhanced keyboard mode can be disabled" do
    parent = self()

    {:ok, pid} =
      Breeze.InputRouter.start_link(
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

    assert_receive :halted
    refute_received {:terminal_write, "\e[<u\e[>4;0m"}
  end

  test "injected terminals use terminal.reader without an explicit reader option" do
    parent = self()
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      Breeze.InputRouter.start_link(
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
    assert_receive :started

    send(pid, {reader, {:data, "q"}})
    assert_receive :halted
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end

  test "enters the alternate screen by default" do
    parent = self()

    {:ok, pid} =
      Breeze.InputRouter.start_link(
        view: BlockingView,
        start_opts: [parent: parent],
        hide_cursor: false,
        terminal_opts: [adapter: RecordingAdapter, owner: parent],
        halt_fun: fn -> send(parent, :halted) end,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    assert_receive {:terminal_started, ^pid, reader}

    assert wait_until(fn ->
             drain_terminal_writes()
             |> IO.iodata_to_binary()
             |> String.contains?("\e[?1049h")
           end)

    send(pid, {reader, {:data, "q"}})
    assert_receive :halted
  end

  test "alt_screen false does not enter or exit the alternate screen" do
    parent = self()

    {:ok, pid} =
      Breeze.InputRouter.start_link(
        view: BlockingView,
        start_opts: [parent: parent],
        alt_screen: false,
        hide_cursor: false,
        terminal_opts: [adapter: RecordingAdapter, owner: parent],
        halt_fun: fn -> send(parent, :halted) end,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    ref = Process.monitor(pid)
    assert_receive {:terminal_started, ^pid, reader}

    send(pid, {reader, {:data, "q"}})
    assert_receive :halted
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

    payload =
      drain_terminal_writes()
      |> IO.iodata_to_binary()

    refute String.contains?(payload, "\e[?1049h")
    refute String.contains?(payload, "\e[?1049l")
  end

  test "stop global keys do not halt when a focused implicit captures printable input" do
    parent = self()

    {:ok, pid} =
      Breeze.InputRouter.start_link(
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

    refute_receive :halted, 50

    wait_until(fn ->
      :sys.get_state(server_pid).frame.base_output =~ "helloq"
    end)

    Process.exit(pid, :normal)
  end

  test "switching to system theme after startup promotes to probed system mode" do
    parent = self()

    {:ok, pid} =
      Breeze.InputRouter.start_link(
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

    wait_until(fn ->
      metadata = ChildServer.metadata(child_pid)
      metadata.theme.mode == :system and metadata.theme.variables[:palette_probe_status] == :ready
    end)

    wait_until(fn ->
      :sys.get_state(server_pid).frame.base_output =~ "mode=system status=ready"
    end)

    Process.exit(pid, :normal)
  end

  defp drain_terminal_writes(writes \\ []) do
    receive do
      {:terminal_write, str} -> drain_terminal_writes([str | writes])
    after
      10 -> Enum.reverse(writes)
    end
  end
end
