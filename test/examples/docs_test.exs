defmodule DocsTest do
  use ExUnit.Case, async: false

  setup_all do
    Application.put_env(:breeze, :example_mode, :load_only)
    Code.require_file("examples/docs.exs")

    on_exit(fn ->
      Application.delete_env(:breeze, :example_mode)
    end)

    :ok
  end

  test "function list hides generated double-underscore docs entries" do
    session = Breeze.Test.start!(Docs, size: {80, 14}, start_opts: [docs: [URI]])
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert {:noreply, _focused, true} = Breeze.Test.event(session, "change", %{value: "URI"})

    rendered =
      session
      |> Breeze.Test.render!()
      |> visible()

    refute rendered =~ "__struct__"
    assert rendered =~ "append_path/2"
  end

  defp visible(content) do
    String.replace(content, ~r/\e\[[0-9;]*m/u, "")
  end
end
