defmodule Breeze.CodeReloaderTest do
  use ExUnit.Case, async: true

  defmodule FakeWatcher do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    def subscribe(pid) do
      GenServer.call(pid, {:subscribe, self()})
    end

    def trigger(pid, path, events \\ [:modified]) do
      GenServer.call(pid, {:trigger, path, events})
    end

    @impl true
    def init(opts) do
      {:ok, %{dirs: Keyword.fetch!(opts, :dirs), subscriber: nil}}
    end

    @impl true
    def handle_call({:subscribe, subscriber}, _from, state) do
      {:reply, :ok, %{state | subscriber: subscriber}}
    end

    def handle_call({:trigger, path, events}, _from, %{subscriber: subscriber} = state) do
      send(subscriber, {:file_event, self(), {path, events}})
      {:reply, :ok, state}
    end
  end

  test "reload compilation suppresses example startup side effects" do
    dir =
      Path.join(System.tmp_dir!(), "breeze-code-reloader-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    path = Path.join(dir, "example_reload_test.exs")

    on_exit(fn -> File.rm_rf!(dir) end)

    File.write!(path, """
    defmodule ReloadCompileExample do
    end

    Breeze.Example.run([])
    """)

    previous = Code.compiler_options()
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      assert [{ReloadCompileExample, _bytecode}] =
               Breeze.ReloadContext.with_compile(fn -> Code.compile_file(path) end)
    after
      Code.compiler_options(previous)
    end
  end

  test "uses file watcher events when a watcher module is available" do
    parent = self()

    dir =
      Path.join(
        System.tmp_dir!(),
        "breeze-code-reloader-watch-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    path = Path.join(dir, "watched.ex")
    File.write!(path, "initial\n")

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, pid} =
      Breeze.CodeReloader.start_link(
        server_pid: self(),
        paths: [dir],
        watcher_module: FakeWatcher,
        compile_fun: fn files ->
          send(parent, {:compiled_files, files})
          :ok
        end
      )

    watcher_pid = :sys.get_state(pid).watcher_pid
    assert is_pid(watcher_pid)

    File.write!(path, "changed now\n")
    :ok = FakeWatcher.trigger(watcher_pid, path)

    assert_receive {:compiled_files, files}, 1_000
    assert files == [path]
    assert_receive {:reload, :code_changed, ^files}, 1_000
  end

  test "does not pass missing default-style paths to the watcher" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "breeze-code-reloader-existing-paths-#{System.unique_integer([:positive])}"
      )

    lib = Path.join(dir, "lib")
    File.mkdir_p!(lib)

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, pid} =
      Breeze.CodeReloader.start_link(
        server_pid: self(),
        paths: [lib, Path.join(dir, "examples"), Path.join(dir, "storybook")],
        watcher_module: FakeWatcher
      )

    watcher_pid = :sys.get_state(pid).watcher_pid

    assert %{dirs: [^lib]} = :sys.get_state(watcher_pid)
  end

  test "explains how to resolve an unavailable watcher module" do
    Process.flag(:trap_exit, true)

    assert {:error, {%ArgumentError{message: message}, _stacktrace}} =
             Breeze.CodeReloader.start_link(
               server_pid: self(),
               watcher_module: __MODULE__.UnavailableWatcher
             )

    assert message =~ "could not be loaded"
    assert message =~ "direct dependency"
    assert message =~ "reload: false"
  end

  test "reports a loaded watcher with an unsupported API" do
    Process.flag(:trap_exit, true)

    assert {:error, {%ArgumentError{message: message}, _stacktrace}} =
             Breeze.CodeReloader.start_link(
               server_pid: self(),
               watcher_module: String
             )

    assert message =~ "must export start_link/1 and subscribe/1"
  end
end
