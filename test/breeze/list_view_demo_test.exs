defmodule Breeze.ListViewDemoTest do
  use ExUnit.Case, async: true
  alias Breeze.Test

  test "switches directly between default, virtual and lazy lists with a 20k total and a bounded cache" do
    session =
      Test.start!(ListViewDemo,
        size: {90, 30},
        global_keybindings: [
          {"d", "Default list", &ListViewDemo.switch_list/2},
          {"v", "Virtual list", &ListViewDemo.switch_list/2},
          {"l", "Lazy list", &ListViewDemo.switch_list/2}
        ]
      )

    on_exit(fn -> Test.stop(session) end)
    assert Test.render_text!(session) =~ "Default list"
    assert Test.render_text!(session) =~ "d Default list  v Virtual list  l Lazy list"
    Test.input(session, "v")
    assert Test.render_text!(session) =~ "Virtual list (20000 items)"
    Test.input(session, "v")
    assert Test.render_text!(session) =~ "Virtual list (20000 items)"
    Test.input(session, "l")
    assert Test.render_text!(session) =~ "Lazy list (20000 items)"
    assert Test.render_text!(session) =~ "Cached: 500 / 20000 | Page reads: 5"
    assigns = Test.metadata(session).assigns
    assert length(assigns.lazy.items) == 400
    assert Enum.sort(Map.keys(assigns.lazy.pages)) == [0, 1, 2, 3, 199]
    assert assigns.lazy.page_reads == 5
    assert_cache_size(session, assigns.lazy.pages)
    assert Test.element!(session, "lazy-list").content_height == 20_000
    Test.input(session, "End")
    assert Test.render_text!(session) =~ "Item 20000"
    assigns = Test.metadata(session).assigns
    assert assigns.lazy.selected_index == 19_999
    assert Test.render_text!(session) =~ "Cached: 500 / 20000 | Page reads: 8"
    assert assigns.lazy.page_reads == 8
    assert length(assigns.lazy.items) == 400
    Test.input(session, "Home")
    Test.render!(session)
    Test.wheel(session, "lazy-list", :down, repeat: 10_000)
    assert Test.render_text!(session) =~ "Item 10001"
    assigns = Test.metadata(session).assigns
    assert length(assigns.lazy.items) == 700
    assert Enum.sort(Map.keys(assigns.lazy.pages)) == [0] ++ Enum.to_list(97..103) ++ [199]
    assert Enum.sum(Enum.map(assigns.lazy.pages, fn {_, rows} -> length(rows) end)) == 900
    assert Test.render_text!(session) =~ "Cached: 900 / 20000 | Page reads: 18"
    assert assigns.lazy.page_reads == 18
    assert_cache_size(session, assigns.lazy.pages)
    Test.input(session, "d")
    assert Test.render_text!(session) =~ "Default list"
    Test.input(session, "l")
    assert Test.render_text!(session) =~ "Item 10001"
    assert Test.metadata(session).assigns.lazy.page_reads == 18
    Test.input(session, "End")
    Test.render!(session)
    session = Test.resize(session, {90, 50})
    grown = Test.render_text!(session)
    visible = Test.element!(session, "lazy-list").viewport_height
    assert grown =~ "Item #{20_000 - visible + 1}"
    assert grown =~ "Item 20000"
  end

  defp assert_cache_size(session, pages) do
    screen = Test.render_text!(session)
    assert [_, size] = Regex.run(~r/Cache: (\d+\.\d) KB/, screen)
    bytes = :erts_debug.flat_size(pages) * :erlang.system_info(:wordsize)
    assert_in_delta String.to_float(size), bytes / 1024, 0.05
  end
end
