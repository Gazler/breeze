defmodule Breeze.ExampleSnapshotTest do
  use ExUnit.Case, async: true
  use Breeze.SnapshotAssertions
  import Breeze.TestSupport.WaitUntil

  @docs_modules [
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

  defmodule SnapshotAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(opts) do
      {width, height} = Keyword.get(opts, :size, {80, 24})
      {:ok, %{ref: make_ref(), size: %{width: width, height: height}}}
    end

    def reader(term), do: {:ok, term.ref}
    def write(term, _str), do: {:ok, term}
    def resize(term), do: term.size
  end

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

  test "posting example initial snapshot" do
    session = Breeze.Test.start!(Posting, size: {120, 24})
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_snapshot(Breeze.Test.render!(session), "examples/posting/initial.ansi",
      snapshot_dir: "../__snapshots__"
    )
  end

  test "posting example snapshots method dropdown opened through server input decoding" do
    terminal = Termite.Terminal.start(adapter: SnapshotAdapter, size: {120, 24})
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        reader: reader,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    on_exit(fn -> Process.exit(pid, :normal) end)

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

  test "posting example snapshots help modal centered" do
    session = Breeze.Test.start!(Posting, size: {120, 24})
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert {:noreply, "help", true} = Breeze.Test.input(session, "F1")

    assert_snapshot(Breeze.Test.render!(session), "examples/posting/help-open.ansi",
      snapshot_dir: "../__snapshots__"
    )
  end

  test "responsive example progressively adds layout chrome" do
    compact = Breeze.Test.start!(Responsive, size: {39, 24})
    medium = Breeze.Test.start!(Responsive, size: {60, 24})
    large = Breeze.Test.start!(Responsive, size: {80, 24})

    on_exit(fn ->
      Breeze.Test.stop(compact)
      Breeze.Test.stop(medium)
      Breeze.Test.stop(large)
    end)

    compact_content = Breeze.Test.render!(compact)
    assert compact_content =~ "39×24 · base breakpoint"
    assert compact_content =~ "[O] [A] [Q] [N]"
    assert compact_content =~ "Nodes"
    refute compact_content =~ "▁"
    refute compact_content =~ "╭"

    medium_content = Breeze.Test.render!(medium)
    assert medium_content =~ "60×24 · md breakpoint"
    assert medium_content =~ "Overview  Activity  Queue  Nodes"
    assert medium_content =~ "▁"

    large_content = Breeze.Test.render!(large)
    assert large_content =~ "80×24 · lg breakpoint"
    assert large_content =~ "╭"
    assert large_content =~ "single row"
  end

  test "docs example snapshots stdlib scrolling" do
    session =
      Breeze.Test.start!(Docs,
        size: {80, 14},
        start_opts: [docs: @docs_modules]
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
    assert {:focused, "doc"} = {:focused, Breeze.Test.metadata(session).focused}
    assert {:noreply, _focused, true} = Breeze.Test.input(session, "PageDown")

    assert_snapshot(Breeze.Test.render!(session), "examples/docs/function-scrolled.ansi",
      snapshot_dir: "../__snapshots__"
    )
  end

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
