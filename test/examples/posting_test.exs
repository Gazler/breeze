defmodule PostingTest do
  use ExUnit.Case, async: true

  setup_all do
    System.put_env("BREEZE_EXAMPLE_NO_START", "1")
    Code.require_file("examples/posting.exs")
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

  defp visible(content) do
    String.replace(content, ~r/\e\[[0-9;]*m/u, "")
  end
end
