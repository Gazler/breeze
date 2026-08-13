defmodule Breeze.ExampleTest do
  use ExUnit.Case, async: false

  defmodule FakeAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(opts) do
      {:ok,
       %{
         ref: make_ref(),
         size: %{width: 80, height: 24},
         owner: Keyword.fetch!(opts, :owner)
       }}
    end

    def reader(terminal), do: {:ok, terminal.ref}
    def resize(terminal), do: terminal.size

    def write(terminal, content) do
      send(terminal.owner, {:terminal_write, content})
      {:ok, terminal}
    end
  end

  defmodule View do
    use Breeze.View

    def render(assigns), do: ~H"<box>example</box>"
  end

  defmodule CrashingView do
    use Breeze.View

    def mount(_opts, _term), do: raise("view startup failed")
    def render(assigns), do: ~H"<box>unreachable</box>"
  end

  setup do
    previous_example_mode = Application.fetch_env(:breeze, :example_mode)
    Application.delete_env(:breeze, :example_mode)

    on_exit(fn ->
      case previous_example_mode do
        {:ok, mode} -> Application.put_env(:breeze, :example_mode, mode)
        :error -> Application.delete_env(:breeze, :example_mode)
      end
    end)

    :ok
  end

  test "raises a startup error after restoring the terminal" do
    parent = self()

    assert_raise ArgumentError, ~r/live reload watcher .* could not be loaded/, fn ->
      Breeze.Example.run(
        [
          view: View,
          reload: [force?: true, watcher_module: __MODULE__.MissingWatcher],
          logger: false,
          hide_cursor: false,
          terminal_opts: [adapter: FakeAdapter, owner: parent],
          internal: [at_exit_register: fn _callback -> :ok end]
        ],
        keep_alive: 0
      )
    end

    assert_receive {:terminal_write, "\e[<u\e[>4;0m"}
    assert_receive {:terminal_write, "\e[?1049l"}
  end

  test "restores the terminal for startup exceptions unrelated to live reload" do
    parent = self()

    assert_raise RuntimeError, "view startup failed", fn ->
      Breeze.Example.run(
        [
          view: CrashingView,
          reload: false,
          logger: false,
          hide_cursor: false,
          terminal_opts: [adapter: FakeAdapter, owner: parent],
          internal: [at_exit_register: fn _callback -> :ok end]
        ],
        keep_alive: 0
      )
    end

    assert_receive {:terminal_write, "\e[<u\e[>4;0m"}
    assert_receive {:terminal_write, "\e[?1049l"}
  end
end
