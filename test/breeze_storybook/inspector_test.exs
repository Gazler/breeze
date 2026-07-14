defmodule Breeze.Storybook.InspectorTest do
  use ExUnit.Case, async: true

  import Breeze.TestSupport.ProcessHelpers, only: [stop_gen_server: 1]
  import Breeze.TestSupport.WaitUntil

  defmodule RecordingAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(opts) do
      {:ok,
       %{
         ref: make_ref(),
         size: %{width: 80, height: 24},
         owner: Keyword.fetch!(opts, :owner)
       }}
    end

    def reader(term), do: {:ok, term.ref}

    def write(term, str) do
      send(term.owner, {:terminal_write, str})
      {:ok, term}
    end

    def resize(term), do: term.size
  end

  test "F4 toggles the inspector in the storybook server" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Breeze.Storybook,
        terminal: terminal,
        inspector: [remote: false]
      )

    on_exit(fn -> stop_gen_server(pid) end)

    refute :sys.get_state(pid).inspector_state.visible?

    send(pid, {terminal.reader, {:data, "\e[S"}})

    wait_until(fn ->
      :sys.get_state(pid).inspector_state.visible?
    end)
  end
end
