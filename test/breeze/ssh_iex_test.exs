defmodule Breeze.SSHIExTest do
  use ExUnit.Case, async: true
  import Breeze.TestSupport.WaitUntil

  @moduletag capture_log: true

  defmodule Counter do
    use Breeze.View

    def mount(_opts, term) do
      send(Process.whereis(__MODULE__), {:mounted, self(), Process.group_leader()})
      send(Process.whereis(__MODULE__), {:terminal, self(), term.terminal})
      {:ok, assign(term, count: 0)}
    end

    def render(assigns) do
      ~H"""
      <box>SSH count: {@count}</box>
      """
    end

    def handle_event(_, %{"key" => "ArrowUp"}, term),
      do: {:noreply, assign(term, count: term.assigns.count + 1)}

    def handle_event(_, %{"key" => "q"}, term), do: {:stop, term}
    def handle_event(_, _, term), do: {:noreply, term}
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:ssh)
    {:ok, _} = Application.ensure_all_started(:iex)
    dir = Path.join(System.tmp_dir!(), "breeze-ssh-iex-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    key = :public_key.generate_key({:rsa, 2048, 65537})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, key)])
    path = Path.join(dir, "ssh_host_rsa_key")
    File.write!(path, pem)
    File.chmod!(path, 0o600)

    shell =
      if Version.match?(System.version(), ">= 1.17.0") do
        {:iex, :start, [[], {:elixir_utils, :noop, []}]}
      else
        {IEx, :start, [[]]}
      end

    {:ok, daemon} =
      :ssh.daemon({127, 0, 0, 1}, 0,
        system_dir: to_charlist(dir),
        user_dir: to_charlist(dir),
        auth_methods: ~c"password",
        user_passwords: [{~c"demo", ~c"test"}],
        shell: shell
      )

    {:ok, info} = :ssh.daemon_info(daemon)

    on_exit(fn ->
      :ssh.stop_daemon(daemon)
      File.rm_rf!(dir)
    end)

    %{port: info[:port], dir: dir}
  end

  setup do
    Process.register(self(), Counter)
    :ok
  end

  test "plain run uses SSH I/O, restores the prompt, and can run again", context do
    user_drv = Process.whereis(:user_drv)
    original_driver_groups = driver_groups(user_drv)
    {connection, channel} = connect(context)
    command(connection, channel, "Breeze.Server.run(view: #{inspect(Counter)})")
    assert_receive {:mounted, view, group}, 5_000
    assert_receive {:terminal, ^view, terminal}
    {Termite.Terminal.IODevice, adapter} = terminal.adapter
    reader_monitor = Process.monitor(adapter.pid)
    router_monitor = Process.monitor(adapter.owner)
    assert Breeze.InputRouter.IExShellProxy.io_device?(group)
    assert driver_groups(user_drv) == original_driver_groups
    assert read_until(connection, channel, "SSH count: 0") =~ "SSH count: 0"

    :ok = :ssh_connection.send(connection, channel, "\e[A")
    assert read_until(connection, channel, "SSH count: 1") =~ "SSH count: 1"

    :ok = :ssh_connection.send(connection, channel, "q")
    assert read_until(connection, channel, "iex(2)>") =~ ":ok"
    assert_receive {:DOWN, ^reader_monitor, :process, _, :normal}
    assert_receive {:DOWN, ^router_monitor, :process, _, :normal}
    refute Process.alive?(view)

    command(connection, channel, "1 + 1")
    assert read_until(connection, channel, "iex(3)>") =~ "2"
    command(connection, channel, ":io.getopts()[:echo]")
    assert read_until(connection, channel, "iex(4)>") =~ "true"

    command(connection, channel, "Breeze.Server.run(view: #{inspect(Counter)})")
    assert_receive {:mounted, _view, _group}, 5_000
    assert read_until(connection, channel, "SSH count: 0") =~ "SSH count: 0"
    :ok = :ssh_connection.send(connection, channel, "q")
    read_until(connection, channel, "iex(5)>")
  end

  test "SSH sessions are independent and disconnect stops only its app", context do
    {first, first_channel} = connect(context)
    {second, second_channel} = connect(context)

    command(first, first_channel, "Breeze.Server.run(view: #{inspect(Counter)})")
    assert_receive {:mounted, first_view, _}, 5_000
    assert_receive {:terminal, ^first_view, first_terminal}
    {_, first_adapter} = first_terminal.adapter
    router_monitor = Process.monitor(first_adapter.owner)
    reader_monitor = Process.monitor(first_adapter.pid)
    read_until(first, first_channel, "SSH count: 0")

    command(second, second_channel, "Breeze.Server.run(view: #{inspect(Counter)})")
    assert_receive {:mounted, second_view, _}, 5_000
    read_until(second, second_channel, "SSH count: 0")

    :ok = :ssh_connection.send(first, first_channel, "\e[A")
    read_until(first, first_channel, "SSH count: 1")
    monitor = Process.monitor(first_view)
    :ssh.close(first)
    assert_receive {:DOWN, ^monitor, :process, ^first_view, _}, 5_000
    assert_receive {:DOWN, ^router_monitor, :process, _, :normal}, 5_000
    assert_receive {:DOWN, ^reader_monitor, :process, _, :normal}, 5_000
    assert Process.alive?(second_view)

    :ok = :ssh_connection.send(second, second_channel, "\e[A")
    read_until(second, second_channel, "SSH count: 1")
    :ok = :ssh_connection.send(second, second_channel, "q")
    read_until(second, second_channel, "iex(2)>")
  end

  test "SSH window changes update the application dimensions", context do
    {connection, channel} = connect(context)
    command(connection, channel, "Breeze.Server.run(view: #{inspect(Counter)})")
    assert_receive {:mounted, view, _}, 5_000
    assert_receive {:terminal, ^view, terminal}
    {_, adapter} = terminal.adapter
    runtime = Breeze.Server.runtime_pid(adapter.owner)
    read_until(connection, channel, "SSH count: 0")

    :ok = :ssh_connection.window_change(connection, channel, 100, 40)

    wait_until(
      fn ->
        :sys.get_state(runtime).terminal_state.terminal.size.width == 100
      end,
      500
    )

    :ok = :ssh_connection.send(connection, channel, "q")
    read_until(connection, channel, "iex(2)>")
  end

  test "failed startup restores the SSH I/O options", context do
    {connection, channel} = connect(context)
    command(connection, channel, "match?({:error, _}, Breeze.Server.run([]))")
    assert read_until(connection, channel, "iex(2)>") =~ "true"
    command(connection, channel, ":io.getopts()[:echo]")
    assert read_until(connection, channel, "iex(3)>") =~ "true"
  end

  defp driver_groups(user_drv) do
    {_state_name, state} = :sys.get_state(user_drv)
    {elem(state, 7), elem(state, 8)}
  end

  defp connect(context) do
    {:ok, connection} =
      :ssh.connect({127, 0, 0, 1}, context.port,
        user: ~c"demo",
        password: ~c"test",
        silently_accept_hosts: true,
        save_accepted_host: false,
        user_interaction: false,
        user_dir: to_charlist(context.dir)
      )

    on_exit(fn -> :ssh.close(connection) end)
    {:ok, channel} = :ssh_connection.session_channel(connection, 5_000)

    :success =
      :ssh_connection.ptty_alloc(connection, channel,
        term: ~c"xterm-256color",
        width: 80,
        height: 24
      )

    :ok = :ssh_connection.shell(connection, channel)
    read_until(connection, channel, "iex(1)>")
    {connection, channel}
  end

  defp command(connection, channel, text),
    do: :ssh_connection.send(connection, channel, text <> "\n")

  defp read_until(connection, channel, text, output \\ "") do
    if String.contains?(output, text) do
      output
    else
      receive do
        {:ssh_cm, ^connection, {:data, ^channel, _, data}} ->
          read_until(connection, channel, text, output <> data)
      after
        5_000 -> flunk("Expected #{inspect(text)} in SSH output: #{inspect(output)}")
      end
    end
  end
end
