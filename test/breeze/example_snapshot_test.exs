defmodule Breeze.TestSupport.ExampleSnapshotCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      use Breeze.SnapshotAssertions

      import Breeze.TestSupport.WaitUntil

      import Breeze.TestSupport.ProcessHelpers,
        only: [start_app_server: 1, stop_gen_server: 1]

      alias Breeze.TestSupport.ExampleSnapshotAdapter, as: SnapshotAdapter
    end
  end
end

defmodule Breeze.TestSupport.ExampleSnapshotAdapter do
  @moduledoc false

  @behaviour Termite.Terminal.Adapter

  def start(opts) do
    {width, height} = Keyword.get(opts, :size, {80, 24})
    {:ok, %{ref: make_ref(), size: %{width: width, height: height}}}
  end

  def reader(term), do: {:ok, term.ref}
  def write(term, _str), do: {:ok, term}
  def resize(term), do: term.size
end

defmodule Breeze.TestSupport.ExampleSnapshots do
  @moduledoc false

  def docs_modules do
    [
      Access,
      Agent,
      Application,
      Atom,
      Base,
      Behaviour,
      Calendar,
      Code,
      Config,
      Date,
      DateTime,
      Enum,
      Exception,
      File,
      Float,
      GenServer,
      Integer,
      IO,
      Keyword,
      List,
      Macro,
      Map,
      MapSet,
      NaiveDateTime,
      Node,
      OptionParser,
      Path,
      Process,
      Range,
      Record,
      Regex,
      String,
      Supervisor,
      System,
      Task,
      Time,
      Tuple,
      URI,
      Version
    ]
  end
end

defmodule Breeze.ExampleSnapshot.CounterTest do
  use Breeze.TestSupport.ExampleSnapshotCase, async: true

  test "counter example snapshots increment and decrement" do
    session = Breeze.Test.start!(Demo, size: {24, 3})
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_snapshot(Breeze.Test.render!(session), "examples/counter/initial.ansi",
      snapshot_dir: "../__snapshots__"
    )

    assert {:noreply, _focused, true} = Breeze.Test.event(session, nil, %{"key" => "ArrowUp"})

    assert_snapshot(Breeze.Test.render!(session), "examples/counter/incremented.ansi",
      snapshot_dir: "../__snapshots__"
    )

    assert {:noreply, _focused, true} = Breeze.Test.event(session, nil, %{"key" => "ArrowDown"})

    assert_snapshot(Breeze.Test.render!(session), "examples/counter/decremented.ansi",
      snapshot_dir: "../__snapshots__"
    )
  end
end

defmodule Breeze.ExampleSnapshot.ModalConfirmTest do
  use Breeze.TestSupport.ExampleSnapshotCase, async: true

  test "modal example snapshots opening and confirming the modal" do
    session =
      Breeze.Test.start!(ModalExample,
        size: {80, 24},
        theme: Breeze.Theme.builtin(:gruvbox)
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_snapshot(Breeze.Test.render!(session), "examples/modal/initial.ansi",
      snapshot_dir: "../__snapshots__"
    )

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "Enter")

    assert_snapshot(Breeze.Test.render!(session), "examples/modal/open.ansi",
      snapshot_dir: "../__snapshots__"
    )

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "Enter")

    assert_snapshot(Breeze.Test.render!(session), "examples/modal/confirmed.ansi",
      snapshot_dir: "../__snapshots__"
    )
  end
end

defmodule Breeze.ExampleSnapshot.ModalInsetTest do
  use Breeze.TestSupport.ExampleSnapshotCase, async: true

  test "modal example snapshots opening the inset modal" do
    session =
      Breeze.Test.start!(ModalExample,
        size: {80, 24},
        theme: Breeze.Theme.builtin(:gruvbox)
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "3")

    assert_snapshot(Breeze.Test.render!(session), "examples/modal/inset-open.ansi",
      snapshot_dir: "../__snapshots__"
    )
  end
end

defmodule Breeze.ExampleSnapshot.TabsTest do
  use Breeze.TestSupport.ExampleSnapshotCase, async: true

  test "tabs example snapshots horizontal selection changes" do
    session = Breeze.Test.start!(TabsExample, size: {34, 14})
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_snapshot(Breeze.Test.render!(session), "examples/tabs/initial.ansi",
      snapshot_dir: "../__snapshots__"
    )

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "ArrowRight")

    assert_snapshot(Breeze.Test.render!(session), "examples/tabs/next-tab.ansi",
      snapshot_dir: "../__snapshots__"
    )

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "ArrowRight")
    assert {:noreply, _focused, true} = Breeze.Test.input(session, "ArrowRight")
    assert {:noreply, _focused, true} = Breeze.Test.input(session, "ArrowRight")

    assert_snapshot(Breeze.Test.render!(session), "examples/tabs/scrolled-tab.ansi",
      snapshot_dir: "../__snapshots__"
    )
  end
end

defmodule Breeze.ExampleSnapshot.PostingInitialTest do
  use Breeze.TestSupport.ExampleSnapshotCase, async: true

  test "posting example initial snapshot" do
    session = Breeze.Test.start!(Posting, size: {120, 24})
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_snapshot(Breeze.Test.render!(session), "examples/posting/initial.ansi",
      snapshot_dir: "../__snapshots__"
    )
  end
end

defmodule Breeze.ExampleSnapshot.PostingMethodTest do
  use Breeze.TestSupport.ExampleSnapshotCase, async: true

  test "posting example snapshots method dropdown opened through server input decoding" do
    terminal = Termite.Terminal.start(adapter: SnapshotAdapter, size: {120, 24})
    reader = terminal.reader

    {:ok, pid} =
      start_app_server(
        view: Posting,
        terminal: terminal,
        reader: reader,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    on_exit(fn -> stop_gen_server(pid) end)

    send(pid, {reader, {:data, "\x14"}})

    wait_until(fn ->
      state = :sys.get_state(pid)

      state.debug.stats[:last_render_cause] == :input_flush and
        state.frame.base_output =~ "GET" and state.frame.base_output =~ "DELETE"
    end)

    assert_snapshot(:sys.get_state(pid).frame.base_output, "examples/posting/method-open.ansi",
      snapshot_dir: "../__snapshots__"
    )
  end
end

defmodule Breeze.ExampleSnapshot.PostingHelpTest do
  use Breeze.TestSupport.ExampleSnapshotCase, async: true

  test "posting example snapshots help modal centered" do
    session = Breeze.Test.start!(Posting, size: {120, 24})
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert {:noreply, "help", true} = Breeze.Test.input(session, "F1")

    assert_snapshot(Breeze.Test.render!(session), "examples/posting/help-open.ansi",
      snapshot_dir: "../__snapshots__"
    )
  end
end

defmodule Breeze.ExampleSnapshot.AnimatedProgressTest do
  use Breeze.TestSupport.ExampleSnapshotCase, async: true

  test "animated progress example snapshots independent child ticks" do
    terminal = Termite.Terminal.start(adapter: SnapshotAdapter, size: {94, 10})
    reader = terminal.reader

    {:ok, pid} =
      start_app_server(
        view: AnimatedProgressExample,
        start_opts: [animate?: false],
        terminal: terminal,
        reader: reader,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    on_exit(fn -> stop_gen_server(pid) end)

    wait_until(fn ->
      state = :sys.get_state(pid)

      map_size(state.children) == 3 and
        state.frame.base_output =~ "0/20" and
        state.frame.base_output =~ "0/16" and
        state.frame.base_output =~ "0/12"
    end)

    assert_snapshot(
      :sys.get_state(pid).frame.base_output,
      "examples/animated-progress/initial.ansi",
      snapshot_dir: "../__snapshots__"
    )

    state = :sys.get_state(pid)

    for {id, tick_count} <- [
          {"progress_slow", 12},
          {"progress_medium", 13},
          {"progress_fast", 3}
        ],
        _tick <- 1..tick_count do
      child = Map.fetch!(state.children, id)
      assert {:noreply, _focused} = Breeze.ChildServer.dispatch_info(child.pid, :tick, terminal)
    end

    wait_until(fn ->
      state = :sys.get_state(pid)
      output = state.frame.base_output

      state.debug.stats[:last_render_cause] == :child_patch and
        output =~ "12/20" and
        output =~ "13/16" and
        output =~ "3/12"
    end)

    assert_snapshot(
      :sys.get_state(pid).frame.base_output,
      "examples/animated-progress/after-ticks.ansi",
      snapshot_dir: "../__snapshots__"
    )
  end
end

defmodule Breeze.ExampleSnapshot.ResponsiveTest do
  use Breeze.TestSupport.ExampleSnapshotCase, async: true

  test "responsive example progressively adds layout chrome" do
    session = Breeze.Test.start!(Responsive, size: {39, 24})
    on_exit(fn -> Breeze.Test.stop(session) end)

    compact_content = Breeze.Test.render_text!(session)
    assert compact_content =~ "39×24 · base breakpoint"
    assert compact_content =~ "[O] [A] [Q] [N]"
    assert compact_content =~ "Nodes"
    refute compact_content =~ "▁"
    refute compact_content =~ "╭"

    session = Breeze.Test.resize(session, {60, 24})
    medium_content = Breeze.Test.render_text!(session)
    assert medium_content =~ "60×24 · md breakpoint"
    assert medium_content =~ "Overview  Activity  Queue  Nodes"
    assert medium_content =~ "▁"

    session = Breeze.Test.resize(session, {80, 24})
    large_content = Breeze.Test.render_text!(session)
    assert large_content =~ "80×24 · lg breakpoint"
    assert large_content =~ "╭"
    assert large_content =~ "single row"
  end
end

defmodule Breeze.ExampleSnapshot.DocsTest do
  use Breeze.TestSupport.ExampleSnapshotCase, async: true

  test "docs example snapshots stdlib scrolling" do
    session =
      Breeze.Test.start!(Docs,
        size: {80, 14},
        start_opts: [docs: Breeze.TestSupport.ExampleSnapshots.docs_modules()]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_snapshot(Breeze.Test.render!(session), "examples/docs/initial.ansi",
      snapshot_dir: "../__snapshots__"
    )

    for _ <- 1..8 do
      assert {:noreply, _focused, true} = Breeze.Test.input(session, "ArrowDown")
    end

    assert_snapshot(Breeze.Test.render!(session), "examples/docs/scrolled.ansi",
      snapshot_dir: "../__snapshots__"
    )

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "End")

    assert_snapshot(Breeze.Test.render!(session), "examples/docs/end.ansi",
      snapshot_dir: "../__snapshots__"
    )

    assert {:noreply, _focused, true} =
             Breeze.Test.event(session, "change", %{value: "Enum"})

    assert_snapshot(Breeze.Test.render!(session), "examples/docs/function-list.ansi",
      snapshot_dir: "../__snapshots__"
    )

    assert {:noreply, _focused, true} =
             Breeze.Test.event(session, "function", %{value: "map/2"})

    assert_snapshot(Breeze.Test.render!(session), "examples/docs/function-selected.ansi",
      snapshot_dir: "../__snapshots__"
    )

    _ = Breeze.Test.render!(session)
    assert {:noreply, _focused, true} = Breeze.Test.input(session, "\t")
    assert {:noreply, "doc", true} = Breeze.Test.input(session, "\t")
    assert Breeze.Test.focused(session) == "doc"
    assert {:noreply, _focused, true} = Breeze.Test.input(session, "PageDown")

    assert_snapshot(Breeze.Test.render!(session), "examples/docs/function-scrolled.ansi",
      snapshot_dir: "../__snapshots__"
    )
  end
end

defmodule Breeze.ExampleSnapshot.SnakeTest do
  use Breeze.TestSupport.ExampleSnapshotCase, async: true

  test "snake example snapshots deterministic ticks" do
    session =
      Breeze.Test.start!(Snake,
        size: {40, 16},
        start_opts: [seed: {3, 29, 5}, tick_ms: 60_000]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_snapshot(Breeze.Test.render!(session), "examples/snake/initial.ansi",
      snapshot_dir: "../__snapshots__"
    )

    assert {:noreply, _focused, true} =
             Breeze.Test.event(session, nil, %{"key" => "ArrowRight"})

    tick = fn ->
      timer = Breeze.Test.metadata(session).assigns.tick_timer
      assert is_reference(timer)
      assert {:noreply, _focused} = Breeze.Test.info(session, {:timeout, timer, :tick})
    end

    for _ <- 1..10 do
      tick.()
    end

    assert_snapshot(Breeze.Test.render!(session), "examples/snake/after-tick.ansi",
      snapshot_dir: "../__snapshots__"
    )

    assert {:noreply, _focused, true} = Breeze.Test.event(session, nil, %{"key" => "ArrowDown"})

    for _ <- 1..4 do
      tick.()
    end

    assert_snapshot(Breeze.Test.render!(session), "examples/snake/turned.ansi",
      snapshot_dir: "../__snapshots__"
    )
  end
end
