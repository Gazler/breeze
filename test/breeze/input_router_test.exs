defmodule Breeze.InputRouterTest do
  use ExUnit.Case, async: true

  alias Breeze.Theme

  defmodule FakeAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(_opts) do
      {:ok, %{ref: make_ref(), size: %{width: 80, height: 24}}}
    end

    def reader(term), do: {:ok, term.ref}
    def write(term, _str), do: {:ok, term}
    def resize(term), do: term.size
  end

  defmodule RecordingAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(opts) do
      {:ok,
       %{
         ref: make_ref(),
         size: %{width: 80, height: 24},
         owner: Keyword.fetch!(opts, :owner)
       }}
    end

    def reader(term), do: {:ok, term.ref}

    def write(term, str) do
      send(term.owner, {:terminal_write, str})
      {:ok, term}
    end

    def resize(term), do: term.size
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

  defmodule ToggleView do
    use Breeze.View

    def mount(_opts, term) do
      {:ok, term |> put_theme(Theme.system16()) |> assign(mode: :system16)}
    end

    def render(assigns) do
      ~H"""
      <box class="text-primary">Theme: {@mode}</box>
      """
    end

    def handle_event(_, %{"key" => "t"}, term) do
      theme =
        Theme.new(
          defaults: %{
            foreground_color: "#839496",
            background_color: "#002b36",
            border_color: "#586e75"
          },
          palette: %{primary: "#268bd2"}
        )

      {:noreply, term |> put_theme(theme) |> assign(mode: :custom)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
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

  test "shutdown waits for server teardown writes before halting" do
    parent = self()

    {:ok, pid} =
      Breeze.InputRouter.start_link(
        view: ToggleView,
        hide_cursor: false,
        terminal_opts: [adapter: RecordingAdapter, owner: parent],
        halt_fun: fn -> send(parent, :halted) end,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    ref = Process.monitor(pid)
    reader = :sys.get_state(pid).reader

    drain_terminal_writes()

    send(pid, {reader, {:data, "t"}})

    assert wait_until(fn ->
             writes = drain_terminal_writes()
             if IO.iodata_to_binary(writes) =~ "\e]11;#002B36\a", do: writes, else: false
           end)

    send(pid, {reader, {:data, "q"}})

    writes =
      wait_until(fn ->
        writes = drain_terminal_writes()
        if writes == [], do: false, else: writes
      end)

    output = IO.iodata_to_binary(writes)

    assert output =~ "\e]111\a"
    assert_receive :halted
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end

  defp drain_terminal_writes(writes \\ []) do
    receive do
      {:terminal_write, str} -> drain_terminal_writes([str | writes])
    after
      10 -> Enum.reverse(writes)
    end
  end

  defp wait_until(fun, attempts \\ 20)

  defp wait_until(fun, attempts) when attempts > 0 do
    case fun.() do
      false ->
        Process.sleep(10)
        wait_until(fun, attempts - 1)

      value ->
        value
    end
  end

  defp wait_until(_fun, 0), do: false
end
