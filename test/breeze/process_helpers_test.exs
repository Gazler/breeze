defmodule Breeze.TestSupport.ProcessHelpersTest do
  use ExUnit.Case, async: true

  import Breeze.TestSupport.ProcessHelpers, only: [stop_gen_server: 1]

  defmodule ShutdownOnTerminate do
    use GenServer

    def start, do: GenServer.start(__MODULE__, nil)

    @impl true
    def init(nil), do: {:ok, nil}

    @impl true
    def terminate(_reason, _state), do: exit(:shutdown)
  end

  @tag capture_log: true
  test "stop_gen_server tolerates shutdown nested through sys terminate" do
    {:ok, pid} = ShutdownOnTerminate.start()

    assert :ok = stop_gen_server(pid)
    refute Process.alive?(pid)
  end
end
