defmodule Breeze.ReloadSafetyTest do
  use ExUnit.Case, async: true

  def sync(pid), do: send(pid, :synced)

  defmodule MissingView do
    use Breeze.View
    def mount(_opts, term), do: {:ok, term}
    def render(_assigns), do: raise(UndefinedFunctionError)
  end

  defmodule Adapter do
    @behaviour Termite.Terminal.Adapter
    def start(_opts), do: {:ok, %{ref: make_ref(), size: %{width: 80, height: 24}}}
    def reader(term), do: {:ok, term.ref}
    def write(term, _str), do: {:ok, term}
    def resize(term), do: term.size
  end

  test "server accepts an MFA without starting a watcher and forwards it to rendering" do
    terminal = Termite.Terminal.start(adapter: Adapter)

    pid =
      start_supervised!(%{
        id: make_ref(),
        start:
          {Breeze.Server, :start_app_link,
           [[view: MissingView, terminal: terminal, reload: {__MODULE__, :sync, [self()]}]]}
      })

    assert_receive :synced
    state = :sys.get_state(pid)
    assert state.reloader_pid == nil
    assert state.crash.reason.__struct__ == UndefinedFunctionError
  end

  test "child rendering does not leak the synchronization hook to other calls" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    pid = start_supervised!({Breeze.ChildServer, view: MissingView, terminal: terminal})

    assert {:crash, _} =
             Breeze.ChildServer.render(pid,
               terminal: terminal,
               reload: {__MODULE__, :sync, [self()]}
             )

    assert_received :synced
    assert {:crash, _} = Breeze.ChildServer.render(pid, terminal: terminal)
    refute_received :synced
  end

  test "undefined calls synchronize and retry only once" do
    reload = {__MODULE__, :sync, [self()]}
    {:ok, count} = Agent.start_link(fn -> 0 end)

    assert :ok ==
             Breeze.CodeReloader.call(
               fn ->
                 case Agent.get_and_update(count, &{&1, &1 + 1}) do
                   0 ->
                     raise UndefinedFunctionError,
                       module: __MODULE__,
                       function: :missing,
                       arity: 0

                   _ ->
                     :ok
                 end
               end,
               reload
             )

    assert_received :synced

    assert_raise UndefinedFunctionError, fn ->
      Breeze.CodeReloader.call(fn -> raise UndefinedFunctionError end, reload)
    end

    assert_received :synced
    refute_received :synced
    Agent.stop(count)
  end

  test "disabled synchronization and unrelated errors do not retry" do
    assert_raise UndefinedFunctionError, fn ->
      Breeze.CodeReloader.call(fn -> raise UndefinedFunctionError end, nil)
    end

    reload = {__MODULE__, :sync, [self()]}

    assert_raise RuntimeError, "boom", fn ->
      Breeze.CodeReloader.call(fn -> raise "boom" end, reload)
    end

    refute_received :synced
  end
end
