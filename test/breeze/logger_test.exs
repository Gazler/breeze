defmodule Breeze.LoggerTest do
  use ExUnit.Case, async: false

  alias Breeze.ChildServer
  alias Breeze.Renderer
  require Logger

  setup do
    {:ok, _pid} = Breeze.LoggerCollector.ensure_started()
    :ok = Breeze.LoggerCollector.clear()
    :ok
  end

  test "collector captures Logger events" do
    :ok = Breeze.LoggerCollector.subscribe(self())
    assert_receive {:logger_snapshot, []}

    message = "collector-log-#{System.unique_integer([:positive])}"
    Logger.warning(message)
    Logger.flush()

    assert_receive {:logger_entry, %{level: :warning, line: line}}, 1_000
    assert line =~ message
  end

  test "collector normalizes unicode logger chardata before rendering" do
    {:ok, collector} = Breeze.LoggerCollector.ensure_started()
    :ok = Breeze.LoggerCollector.subscribe(self())
    assert_receive {:logger_snapshot, []}

    event = %{level: :info, msg: {:string, [181, ?s]}, meta: %{}}
    Breeze.LoggerHandler.log(event, %{config: %{collector: collector}})

    assert_receive {:logger_entry, %{level: :info, line: line}}, 1_000
    assert String.valid?(line)
    assert line =~ "µs"
  end

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

  test "logger height applies to the scroll viewport" do
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

    assert logger_viewport(acc).style.height == 6
    assert box.height == 8
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
             ChildServer.dispatch_event(pid, :ignore_me, %{"key" => "k"})

    {:ok, acc, _box} = ChildServer.render(pid, focused: "logger", implicit_state: %{})
    assert logger_viewport(acc).scroll == {15, 0}
  end

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
             ChildServer.dispatch_event(pid, :ignore_me, %{"key" => "c"})

    wait_until(fn ->
      {:ok, _acc, box} = ChildServer.render(pid, focused: "logger", implicit_state: %{})
      box.content =~ "Press c to clear." and not (box.content =~ "clear-me-")
    end)
  end

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
             ChildServer.dispatch_event(pid, :ignore_me, %{"key" => "c"})

    {:ok, _acc, box} = ChildServer.render(pid, focused: "logger", implicit_state: %{})
    assert box.content =~ "dont-clear-me-"
    refute box.content =~ "Press c to clear."
  end

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
             ChildServer.dispatch_event(pid, :ignore_me, %{"key" => "k"})

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
