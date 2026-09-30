defmodule Breeze.ImplicitReloadSafetyTest do
  use ExUnit.Case, async: false

  defmodule View do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box id="logo" implicit={Breeze.ImplicitReloadSafetyTest.Logo} class="width-10 height-3">
      </box>
      """
    end
  end

  def restore(module, binary, owner) do
    send(owner, :reload_synchronized)
    {:module, ^module} = :code.load_binary(module, ~c"reload_fixture.ex", binary)
  end

  for owner <- [:child, :server] do
    @owner owner
    test "#{owner} implicit click survives an unloaded module during reload" do
      [{module, binary}] =
        Code.compile_string("""
        defmodule Breeze.ImplicitReloadSafetyTest.Logo do
          def init(_, _, state), do: {:ok, state}
          def handle_modifiers(_, _, _), do: []
          def handle_event(_, _, state), do: {:noreply, Map.put(state, :clicked, true), consumed: true}
        end
        """)

      terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
      reload = {__MODULE__, :restore, [module, binary, self()]}
      pid = start_view(@owner, terminal, reload)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
        :code.purge(module)
        :code.delete(module)
      end)

      assert {:ok, _, _} = Breeze.ChildServer.render(pid, terminal: terminal, reload: reload)
      :code.purge(module)
      :code.delete(module)
      input = %{"mouse" => %{"action" => "press", "button" => "left", "x" => 1, "y" => 1}}
      assert {:noreply, _, true} = Breeze.ChildServer.dispatch_input(pid, input)
      assert_receive :reload_synchronized
      assert Process.alive?(pid)
    end
  end

  defmodule Adapter do
    @behaviour Termite.Terminal.Adapter
    def start(_opts), do: {:ok, %{ref: make_ref(), size: %{width: 80, height: 24}}}
    def reader(term), do: {:ok, term.ref}
    def write(term, _str), do: {:ok, term}
    def resize(term), do: term.size
  end

  defp start_view(:child, terminal, reload) do
    {:ok, pid} = Breeze.ChildServer.start(view: View, terminal: terminal, reload: reload)
    pid
  end

  defp start_view(:server, _terminal, reload) do
    server =
      start_supervised!(%{
        id: :reload_server,
        start:
          {Breeze.Server, :start_app_link,
           [
             [
               view: View,
               terminal: Termite.Terminal.start(adapter: Adapter),
               reload: reload
             ]
           ]}
      })

    :sys.get_state(server).view_pid
  end
end
