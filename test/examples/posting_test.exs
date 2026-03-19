defmodule PostingTest do
  use ExUnit.Case, async: false

  setup_all do
    Application.put_env(:breeze, :example_mode, :load_only)
    Code.require_file("examples/posting.exs")

    on_exit(fn ->
      Application.delete_env(:breeze, :example_mode)
    end)

    :ok
  end

  test "F1 opens help modal and focuses it, Escape closes and restores url focus" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Posting, terminal: terminal)

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert visible(box.content) =~ "https://jsonplaceholder.typicode.com/posts"
    assert %{focused: "url"} = Breeze.ChildServer.metadata(pid)

    assert {:noreply, "help", true} = Breeze.ChildServer.dispatch_input(pid, "F1")

    assert {:ok, _acc, help_box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert visible(help_box.content) =~ "Keyboard Shortcuts"
    assert visible(help_box.content) =~ "Close this dialog"
    assert %{focused: "help"} = Breeze.ChildServer.metadata(pid)

    assert {:noreply, "url", true} = Breeze.ChildServer.dispatch_input(pid, "Escape")

    assert {:ok, _acc, closed_box} = Breeze.ChildServer.render(pid, terminal: terminal)
    refute visible(closed_box.content) =~ "Keyboard Shortcuts"
    assert %{focused: "url"} = Breeze.ChildServer.metadata(pid)
  end

  test "Ctrl-T opens the method dropdown" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Posting, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "method", true} = Breeze.ChildServer.dispatch_input(pid, "\x14")

    assert {:ok, _acc, open_box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert visible(open_box.content) =~ "GET"
    assert visible(open_box.content) =~ "DELETE"
    assert %{focused: "method"} = Breeze.ChildServer.metadata(pid)
  end

  defmodule FakeAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(_opts) do
      {:ok, %{ref: make_ref(), size: %{width: 80, height: 24}}}
    end

    def reader(term), do: {:ok, term.ref}
    def write(term, _str), do: {:ok, term}
    def resize(term), do: term.size
  end

  test "server input flush loop settles after a focus change" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    send(pid, {reader, {:data, "\t"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      not state.input_flush_scheduled? and state.queued_input == []
    end)

    state = :sys.get_state(pid)

    refute state.input_flush_scheduled?
    assert state.queued_input == []

    Process.exit(pid, :normal)
  end

  defp visible(content) do
    String.replace(content, ~r/\e\[[0-9;]*m/u, "")
  end

  defp wait_until(fun, attempts \\ 20)

  defp wait_until(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      wait_until(fun, attempts - 1)
    end
  end

  defp wait_until(_fun, 0), do: flunk("condition not met")
end
