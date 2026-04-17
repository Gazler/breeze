defmodule Breeze.Storybook.SnapshotTest do
  use ExUnit.Case, async: false
  use Breeze.SnapshotAssertions

  alias Breeze.ChildServer

  defp start_storybook!(file, opts \\ []) do
    session =
      Breeze.Test.start!(Breeze.Storybook.View,
        size: Keyword.get(opts, :size, {120, 24}),
        theme: Keyword.get(opts, :theme, Breeze.Theme.builtin(:gruvbox)),
        start_opts: [directory: "storybook", file: file]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)
    session
  end

  defp set_focus!(session, focused) do
    assert {:noreply, ^focused, true} = ChildServer.set_focus(session.pid, focused)
  end

  test "dropdown story snapshots closed and open states" do
    session = start_storybook!("dropdown.story.exs")

    assert_snapshot(Breeze.Test.render!(session), "storybook/dropdown/initial.ansi",
      snapshot_dir: "../__snapshots__"
    )

    focused = "storybook-preview::storybook-dropdown"
    set_focus!(session, focused)
    assert {:noreply, ^focused, true} = Breeze.Test.input(session, "Enter")

    assert_snapshot(Breeze.Test.render!(session), "storybook/dropdown/open.ansi",
      snapshot_dir: "../__snapshots__"
    )
  end

  test "tabs story snapshots active tab change and blur" do
    session = start_storybook!("tabs.story.exs")

    assert_snapshot(Breeze.Test.render!(session), "storybook/tabs/initial.ansi",
      snapshot_dir: "../__snapshots__"
    )

    focused = "storybook-preview::storybook-tabs"
    set_focus!(session, focused)
    assert {:noreply, ^focused, true} = Breeze.Test.input(session, "ArrowRight")

    assert_snapshot(Breeze.Test.render!(session), "storybook/tabs/next-tab.ansi",
      snapshot_dir: "../__snapshots__"
    )

    assert {:noreply, nil, true} = Breeze.Test.input(session, "\t")

    assert_snapshot(Breeze.Test.render!(session), "storybook/tabs/blurred.ansi",
      snapshot_dir: "../__snapshots__"
    )
  end

  test "list story snapshots selection change" do
    session = start_storybook!("list.story.exs")

    focused = "storybook-preview::storybook-list-muted"
    set_focus!(session, focused)
    assert {:noreply, ^focused, _consumed} = Breeze.Test.input(session, "ArrowDown")

    assert_snapshot(Breeze.Test.render!(session), "storybook/list/selected-next.ansi",
      snapshot_dir: "../__snapshots__"
    )
  end

  test "scroll story snapshots scroll movement" do
    session = start_storybook!("scroll.story.exs")

    focused = "storybook-preview::storybook-scroll"
    set_focus!(session, focused)
    assert {:noreply, ^focused, _consumed} = Breeze.Test.input(session, "ArrowDown")

    assert_snapshot(Breeze.Test.render!(session), "storybook/scroll/scrolled.ansi",
      snapshot_dir: "../__snapshots__"
    )
  end
end
