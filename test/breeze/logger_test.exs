defmodule Breeze.LoggerTest do
  use ExUnit.Case, async: false

  alias Breeze.ChildServer
  alias Breeze.Renderer
  require Logger

  defmodule EmptyView do
    use Breeze.View

    def render(assigns), do: ~H"<box>logger lifecycle</box>"
  end

  defmodule FakeAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(_opts), do: {:ok, %{ref: make_ref(), size: %{width: 40, height: 8}}}
    def reader(term), do: {:ok, term.ref}
    def write(term, _str), do: {:ok, term}
    def resize(term), do: term.size
  end

  setup do
    owner = self()
    existing_collector = Process.whereis(Breeze.Logger.Collector)
    {:ok, collector} = Breeze.Logger.Collector.ensure_started()
    :ok = Breeze.Logger.Collector.configure(owner, :attach)
    :ok = Breeze.Logger.Collector.clear()

    on_exit(fn ->
      _ = Breeze.Logger.Collector.release(owner)

      if is_nil(existing_collector) and Process.alive?(collector) do
        GenServer.stop(collector, :normal)
      end
    end)

    %{collector: collector}
  end

  test "server reuses a collector owned by the caller supervision hierarchy", %{
    collector: collector
  } do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, server} =
      Breeze.Server.start_app_link(view: EmptyView, terminal: terminal, logger: :attach)

    assert Process.whereis(Breeze.Logger.Collector) == collector
    GenServer.stop(server, :normal)
    assert Process.alive?(collector)
  end

  test "server starts and stops an ephemeral collector when none is supervised", %{
    collector: collector
  } do
    GenServer.stop(collector, :normal)
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, server} =
      Breeze.Server.start_app_link(view: EmptyView, terminal: terminal, logger: :attach)

    ephemeral = Process.whereis(Breeze.Logger.Collector)
    assert is_pid(ephemeral)
    assert %{configured?: true, modes: [:attach]} = Breeze.Logger.Collector.status()

    GenServer.stop(server, :normal)
    wait_until(fn -> is_nil(Process.whereis(Breeze.Logger.Collector)) end)
    refute Process.alive?(ephemeral)
  end

  test "server retries configuration when an ephemeral collector is stopping", %{
    collector: collector
  } do
    GenServer.stop(collector, :normal)

    stopping_collector =
      spawn(fn ->
        receive do
          {:"$gen_call", from, {:configure, _owner, _config}} ->
            Process.unregister(Breeze.Logger.Collector)
            GenServer.reply(from, {:error, :not_started})
        end
      end)

    true = Process.register(stopping_collector, Breeze.Logger.Collector)
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    assert {:ok, server} =
             Breeze.Server.start_app_link(
               view: EmptyView,
               terminal: terminal,
               logger: :attach
             )

    active_collector = Process.whereis(Breeze.Logger.Collector)
    assert is_pid(active_collector)
    refute active_collector == stopping_collector

    GenServer.stop(server, :normal)
    wait_until(fn -> is_nil(Process.whereis(Breeze.Logger.Collector)) end)
  end

  test "collector calls tolerate a process shutting down", %{collector: collector} do
    GenServer.stop(collector, :normal)
    parent = self()

    shutting_down_collector =
      spawn(fn ->
        Process.register(self(), Breeze.Logger.Collector)
        send(parent, :collector_registered)

        receive do
          {:"$gen_call", _from, {:release, _owner}} -> exit(:shutdown)
        end
      end)

    ref = Process.monitor(shutting_down_collector)
    assert_receive :collector_registered

    assert {:error, :not_started} = Breeze.Logger.Collector.release(self())
    assert_receive {:DOWN, ^ref, :process, ^shutting_down_collector, :shutdown}
  end

  test "attach capture preserves the default logger handler" do
    assert {:ok, before_config} = :logger.get_handler_config(:default)

    assert %{handler_installed?: true, replacing_default?: false, modes: [:attach]} =
             Breeze.Logger.Collector.status()

    assert {:ok, after_config} = :logger.get_handler_config(:default)
    assert after_config == before_config
  end

  test "collector retains the newest entries in oldest-first order", %{collector: collector} do
    assert :ok = Breeze.Logger.Collector.configure(self(), mode: :attach, max_entries: 3)

    for index <- 1..5 do
      GenServer.cast(collector, {:log, %{level: :info, line: "entry-#{index}"}})
    end

    assert Enum.map(Breeze.Logger.Collector.entries(), & &1.line) ==
             ["entry-3", "entry-4", "entry-5"]
  end

  @tag capture_log: true
  test "Breeze.IO.inspect pretty-prints through the logger and returns its input" do
    value = %{alpha: Enum.to_list(1..5), beta: %{enabled: true}}

    assert Breeze.IO.inspect(value, label: "state", width: 20) == value

    wait_until(fn ->
      Enum.any?(Breeze.Logger.Collector.entries(), fn entry ->
        plain = BackBreeze.Utils.strip_escape_chars(entry.line)
        entry.level == :info and plain =~ "state: %{\n" and plain =~ "alpha: ["
      end)
    end)

    entry =
      Enum.find(Breeze.Logger.Collector.entries(), fn entry ->
        BackBreeze.Utils.strip_escape_chars(entry.line) =~ "state: %{\n"
      end)

    assert entry.line =~ "\e["
  end

  @tag capture_log: true
  test "Breeze.IO.puts routes output through the logger" do
    assert :ok = Breeze.IO.puts(["logger", " ", "output"])

    wait_until(fn ->
      Enum.any?(Breeze.Logger.Collector.entries(), fn entry ->
        entry.level == :info and entry.line =~ "logger output"
      end)
    end)
  end

  test "replace capture restores the exact default handler configuration" do
    assert {:ok, original_config} = :logger.get_handler_config(:default)

    assert :ok = Breeze.Logger.Collector.configure(self(), mode: :replace, max_entries: 25)
    assert {:ok, %{level: :none}} = :logger.get_handler_config(:default)

    assert %{
             handler_installed?: true,
             replacing_default?: true,
             max_entries: 25,
             modes: [:replace]
           } = Breeze.Logger.Collector.status()

    assert :ok = Breeze.Logger.Collector.configure(self(), :attach)
    assert {:ok, restored_config} = :logger.get_handler_config(:default)
    assert restored_config == original_config
  end

  test "mounting the logger view does not change logger handler configuration" do
    before_status = Breeze.Logger.Collector.status()
    assert {:ok, before_default} = :logger.get_handler_config(:default)

    {:ok, _pid} = ChildServer.start(view: Breeze.Logger, start_opts: [])

    assert Breeze.Logger.Collector.status() == before_status
    assert :logger.get_handler_config(:default) == {:ok, before_default}
  end

  @tag capture_log: true
  test "collector captures Logger events" do
    :ok = Breeze.Logger.Collector.subscribe(self())
    assert_receive {:logger_snapshot, []}

    message = "collector-log-#{System.unique_integer([:positive])}"
    Logger.warning(message)
    Logger.flush()

    assert_receive {:logger_entry, %{level: :warning, line: line}}, 1_000
    assert line =~ message
  end

  test "collector normalizes unicode logger chardata before rendering" do
    {:ok, collector} = Breeze.Logger.Collector.ensure_started()
    :ok = Breeze.Logger.Collector.subscribe(self())
    assert_receive {:logger_snapshot, []}

    event = %{level: :info, msg: {:string, [181, ?s]}, meta: %{}}
    Breeze.Logger.Handler.log(event, %{config: %{collector: collector}})

    assert_receive {:logger_entry, %{level: :info, line: line}}, 1_000
    assert String.valid?(line)
    assert line =~ "µs"
  end

  @tag capture_log: true
  test "logger view renders recent log lines" do
    {:ok, pid} = ChildServer.start(view: Breeze.Logger, start_opts: [max_lines: 2])
    wait_until(fn -> true end)

    first = "logger-view-first-#{System.unique_integer([:positive])}"
    second = "logger-view-second-#{System.unique_integer([:positive])}"
    third = "logger-view-third-#{System.unique_integer([:positive])}"

    Logger.info(first)
    Logger.error(second)
    Logger.warning(third)
    Logger.flush()

    wait_until(fn ->
      {:ok, _acc, box} = ChildServer.render(pid, focused: nil, implicit_state: %{})
      box.content =~ second and box.content =~ third
    end)

    {:ok, _acc, box} = ChildServer.render(pid, focused: nil, implicit_state: %{})

    refute box.content =~ first
    assert box.content =~ second
    assert box.content =~ third
  end

  test "logger height applies to the whole component" do
    {acc, box} =
      Renderer.render(
        Breeze.Logger,
        %{
          title: "Logs",
          helper_text: "Help",
          min_level: :debug,
          width: 40,
          height: 6,
          lines: []
        },
        focused: "logger",
        implicit_state: %{}
      )

    assert logger_viewport(acc).style.height == 4
    assert box.height == 6
  end

  test "logger full height uses the terminal height" do
    {acc, box} =
      Renderer.render(
        Breeze.Logger,
        %{
          title: "Logs",
          helper_text: "Help",
          min_level: :debug,
          width: 40,
          height: :full,
          terminal_height: 12,
          lines: []
        },
        focused: "logger",
        implicit_state: %{}
      )

    assert logger_viewport(acc).style.height == 10
    assert box.height == 12
  end

  test "logger wraps long lines to the available width" do
    lines = [
      %{level: :info, line: "alpha beta gamma delta", style: "text-6"}
    ]

    {_acc, box} =
      Renderer.render(
        Breeze.Logger,
        %{
          title: "Logs",
          helper_text: "Help",
          min_level: :debug,
          width: 12,
          height: 8,
          lines: lines
        },
        focused: "logger",
        implicit_state: %{}
      )

    assert box.content =~ "alpha beta"
    assert box.content =~ "gamma"
    assert box.content =~ "delta"
  end

  test "logger view applies scroll offsets from the scroll implicit" do
    lines =
      for index <- 1..12 do
        %{level: :info, line: "line-#{index}", style: "text-6"}
      end

    {acc, _box} =
      Renderer.render(
        Breeze.Logger,
        %{title: "Logs", min_level: :debug, width: 40, height: 6, lines: lines},
        focused: "logger",
        implicit_state: %{"logger" => {Breeze.Implicit.Scroll, %{offset_y: 3}}}
      )

    assert logger_viewport(acc).scroll == {3, 0}
  end

  test "child views apply scroll implicit key events" do
    lines =
      for index <- 1..20 do
        %{level: :info, line: "scroll-line-#{index}", style: "text-6"}
      end

    {:ok, pid} = ChildServer.start(view: Breeze.Logger, start_opts: [height: 6, max_lines: 20])
    {:ok, _acc, _box} = ChildServer.render(pid, focused: "logger", implicit_state: %{})
    :sys.replace_state(pid, fn term -> Breeze.View.assign(term, lines: lines) end)
    {:ok, acc, _box} = ChildServer.render(pid, focused: "logger", implicit_state: %{})
    bottom_scroll = logger_viewport(acc).scroll
    assert elem(bottom_scroll, 0) > 0
    assert elem(bottom_scroll, 1) == 0

    assert {:noreply, "logger", true} =
             ChildServer.dispatch_event(pid, :input, %{"key" => "k"})

    {:ok, acc, _box} = ChildServer.render(pid, focused: "logger", implicit_state: %{})
    assert logger_viewport(acc).scroll == {17, 0}
  end

  @tag capture_log: true
  test "focused logger still receives non-scroll keys" do
    {:ok, pid} = ChildServer.start(view: Breeze.Logger, start_opts: [height: 6, max_lines: 20])
    {:ok, _acc, _box} = ChildServer.render(pid, focused: "logger", implicit_state: %{})

    Logger.info("clear-me-#{System.unique_integer([:positive])}")
    Logger.flush()

    wait_until(fn ->
      {:ok, _acc, box} = ChildServer.render(pid, focused: "logger", implicit_state: %{})
      box.content =~ "clear-me-"
    end)

    assert {:noreply, "logger", true} =
             ChildServer.dispatch_event(pid, :input, %{"key" => "c"})

    wait_until(fn ->
      {:ok, _acc, box} = ChildServer.render(pid, focused: "logger", implicit_state: %{})
      box.content =~ "Press c to clear." and not (box.content =~ "clear-me-")
    end)
  end

  @tag capture_log: true
  test "logger can disable the clear shortcut" do
    {:ok, pid} =
      ChildServer.start(
        view: Breeze.Logger,
        start_opts: [height: 6, max_lines: 20, clear_key: nil]
      )

    {:ok, _acc, _box} = ChildServer.render(pid, focused: "logger", implicit_state: %{})

    Logger.info("dont-clear-me-#{System.unique_integer([:positive])}")
    Logger.flush()

    wait_until(fn ->
      {:ok, _acc, box} = ChildServer.render(pid, focused: "logger", implicit_state: %{})
      box.content =~ "dont-clear-me-"
    end)

    assert {:noreply, "logger", false} =
             ChildServer.dispatch_event(pid, :input, %{"key" => "c"})

    {:ok, _acc, box} = ChildServer.render(pid, focused: "logger", implicit_state: %{})
    assert box.content =~ "dont-clear-me-"
    refute box.content =~ "Press c to clear."
  end

  @tag capture_log: true
  test "logger autoscrolls while pinned to the bottom" do
    lines =
      for index <- 1..8 do
        %{level: :info, line: "line-#{index}", style: "text-6"}
      end

    {:ok, pid} = ChildServer.start(view: Breeze.Logger, start_opts: [height: 6, max_lines: 20])
    :sys.replace_state(pid, fn term -> Breeze.View.assign(term, lines: lines) end)
    {:ok, acc, _box} = ChildServer.render(pid, focused: "logger", implicit_state: %{})
    bottom_scroll = logger_viewport(acc).scroll

    Logger.info("autofollow-#{System.unique_integer([:positive])}")
    Logger.flush()

    wait_until(fn ->
      {:ok, acc, _box} = ChildServer.render(pid, focused: "logger", implicit_state: %{})
      logger_viewport(acc).scroll == {elem(bottom_scroll, 0) + 1, 0}
    end)
  end

  @tag capture_log: true
  test "logger stops autoscrolling after the user scrolls away" do
    lines =
      for index <- 1..8 do
        %{level: :info, line: "manual-line-#{index}", style: "text-6"}
      end

    {:ok, pid} = ChildServer.start(view: Breeze.Logger, start_opts: [height: 6, max_lines: 20])
    :sys.replace_state(pid, fn term -> Breeze.View.assign(term, lines: lines) end)
    {:ok, acc, _box} = ChildServer.render(pid, focused: "logger", implicit_state: %{})
    bottom_scroll = logger_viewport(acc).scroll

    assert {:noreply, "logger", true} =
             ChildServer.dispatch_event(pid, :input, %{"key" => "k"})

    Logger.info("no-autofollow-#{System.unique_integer([:positive])}")
    Logger.flush()

    wait_until(fn ->
      {:ok, acc, _box} = ChildServer.render(pid, focused: "logger", implicit_state: %{})
      logger_viewport(acc).scroll == {elem(bottom_scroll, 0) - 1, 0}
    end)
  end

  defp wait_until(fun, attempts \\ 20)

  defp wait_until(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      wait_until(fun, attempts - 1)
    end
  end

  defp wait_until(_fun, 0), do: flunk("condition not met")

  defp logger_viewport(acc), do: Map.fetch!(acc.boxes, "logger")
end
