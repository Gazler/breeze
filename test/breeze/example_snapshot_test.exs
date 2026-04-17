defmodule Breeze.ExampleSnapshotTest do
  use ExUnit.Case, async: false
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

  setup_all do
    Application.put_env(:breeze, :example_mode, :load_only)
    Application.put_env(:breeze, :example_user_host, "gazler@gazler-arch")

    for file <- ~w(counter.exs docs.exs modal.exs posting.exs snake.exs tabs.exs) do
      Code.require_file(Path.expand("../../examples/#{file}", __DIR__))
    end

    on_exit(fn ->
      Application.delete_env(:breeze, :example_mode)
      Application.delete_env(:breeze, :example_user_host)
    end)

    :ok
  end

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

      state.debug_stats[:last_render_cause] == :child_invalidated and
        state.base_output =~ "GET" and state.base_output =~ "DELETE"
    end)

    assert_snapshot(:sys.get_state(pid).base_output, "examples/posting/method-open.ansi",
      snapshot_dir: "../__snapshots__"
    )
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
        start_opts: [seed: {3, 29, 5}, tick_ms: nil]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_snapshot(Breeze.Test.render!(session), "examples/snake/initial.ansi",
      snapshot_dir: "../__snapshots__"
    )

    for _ <- 1..14 do
      assert {:noreply, _focused} = Breeze.Test.info(session, :tick)
    end

    assert_snapshot(Breeze.Test.render!(session), "examples/snake/after-tick.ansi",
      snapshot_dir: "../__snapshots__"
    )

    assert {:noreply, _focused, true} = Breeze.Test.event(session, nil, %{"key" => "ArrowDown"})

    for _ <- 1..4 do
      assert {:noreply, _focused} = Breeze.Test.info(session, :tick)
    end

    assert_snapshot(Breeze.Test.render!(session), "examples/snake/turned.ansi",
      snapshot_dir: "../__snapshots__"
    )
  end
end
