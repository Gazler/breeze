defmodule Breeze.InputRouter.IExShellProxyTest do
  use ExUnit.Case, async: true

  alias Breeze.InputRouter.IExShellProxy

  defmodule FakeUserDrv do
    use GenServer

    def start_link(owner) do
      user_group = owner
      previous_group = owner

      data =
        Tuple.duplicate(nil, 9)
        |> put_elem(7, user_group)
        |> put_elem(8, previous_group)

      GenServer.start_link(__MODULE__, {:fake_user_drv, data})
    end

    def start_link_with_state(state) do
      GenServer.start_link(__MODULE__, state)
    end

    @impl true
    def init(state), do: {:ok, state}
  end

  test "proxies the group leader node user_drv and restores it on stop" do
    parent = self()
    original_group_leader = Process.group_leader()
    {:ok, user_drv} = FakeUserDrv.start_link(parent)

    input_mode_fun = fn node, mode ->
      send(parent, {:input_mode, node, mode})
      :ok
    end

    user_drv_lookup = fn node ->
      send(parent, {:lookup, node})
      user_drv
    end

    {:ok, proxy} =
      IExShellProxy.start_link(parent,
        input_mode_fun: input_mode_fun,
        user_drv_lookup: user_drv_lookup
      )

    try do
      assert_receive {:lookup, node}
      assert node == node(original_group_leader)
      assert_receive {:input_mode, user_drv_node, :raw}
      assert user_drv_node == node(user_drv)
      assert Process.group_leader() == proxy.pid

      {_state_name, data} = :sys.get_state(user_drv)
      assert elem(data, 8) == proxy.pid

      send(proxy.pid, {user_drv, {:data, "x"}})
      assert_receive {:data, "x"}

      proxy_ref = Process.monitor(proxy.pid)

      assert :ok = IExShellProxy.stop(proxy)
      assert_receive {:input_mode, ^user_drv_node, :cooked}
      assert_receive {^user_drv, :activate}
      assert Process.group_leader() == original_group_leader
      assert_receive {:DOWN, ^proxy_ref, :process, _pid, _reason}

      {_state_name, data} = :sys.get_state(user_drv)
      assert elem(data, 8) == parent
      refute Process.alive?(proxy.pid)
    after
      Process.group_leader(self(), original_group_leader)

      if Process.alive?(proxy.pid) do
        IExShellProxy.stop(proxy)
      end
    end
  end

  test "does not switch input mode when user_drv state cannot be inspected" do
    parent = self()
    original_group_leader = Process.group_leader()
    {:ok, user_drv} = FakeUserDrv.start_link_with_state(:unexpected_state)

    input_mode_fun = fn node, mode ->
      send(parent, {:input_mode, node, mode})
      :ok
    end

    user_drv_lookup = fn _node -> user_drv end

    assert :error =
             IExShellProxy.start_link(parent,
               input_mode_fun: input_mode_fun,
               user_drv_lookup: user_drv_lookup
             )

    refute_received {:input_mode, _, _}
    assert Process.group_leader() == original_group_leader
  end
end
