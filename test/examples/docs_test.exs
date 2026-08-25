defmodule DocsTest do
  use ExUnit.Case, async: true

  test "function list hides generated double-underscore docs entries" do
    session = Breeze.Test.start!(Docs, size: {80, 14}, start_opts: [docs: [URI]])
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert {:noreply, _focused, true} = Breeze.Test.event(session, "change", %{value: "URI"})

    rendered = Breeze.Test.render_text!(session)

    refute rendered =~ "__struct__"
    assert rendered =~ "append_path/2"
  end
end
