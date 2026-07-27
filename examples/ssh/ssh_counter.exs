if Code.ensure_loaded?(Mix.ProjectStack) and Process.whereis(Mix.ProjectStack) do
  raise """
  `examples/ssh_counter.exs` must be run with `elixir`, not `mix`.

  Run:
    BREEZE_SSH_PORT=2230 elixir examples/ssh_counter.exs
  """
end

project_root = Path.expand("../..", __DIR__)

Mix.install([
  {:breeze, path: project_root},
  {:termite, github: "gazler/termite", override: true},
  {:termite_ssh, github: "gazler/termite_ssh"}
])

try do
  Mix.Tasks.Termite.Ssh.GenHostKey.run([])
rescue
  _ -> nil
end

defmodule SSHCounter do
  use Breeze.View
  import Breeze.Blocks

  def mount(opts, term) do
    {:ok,
     term
     |> assign(
       counter: 0,
       username: Keyword.get(opts, :username, "guest")
     )
     |> put_local_keybindings([
       {"ArrowUp", "Increment"},
       {"ArrowDown", "Decrement"},
       {"q", "Quit"}
     ])}
  end

  def render(assigns) do
    ~H"""
    <box class="grid grid-cols-1 grid-rows-2 w-screen h-screen">
      <box>
        <box class="p-1">
          <box class="font-bold">Breeze over SSH</box>
          <box>User: {@username}</box>
          <box>Counter: {@counter}</box>
        </box>
      </box>
      <box class="h-1 bg-panel overflow-hidden">
        <.keybinding_bar keybindings={@breeze.keybindings}/>
      </box>
    </box>
    """
  end

  def handle_event(_, %{"key" => "ArrowUp"}, term) do
    {:noreply, assign(term, counter: term.assigns.counter + 1)}
  end

  def handle_event(_, %{"key" => "ArrowDown"}, term) do
    {:noreply, assign(term, counter: term.assigns.counter - 1)}
  end

  def handle_event(_, _, term), do: {:noreply, term}
end

defmodule SSHCounterEntrypoint do
  def start_link(opts) do
    session = Keyword.fetch!(opts, :session)

    Breeze.Server.start_link(
      view: SSHCounter,
      start_opts: [username: session.username],
      terminal_opts: Termite.SSH.Session.terminal_opts(session),
      halt_fun: fn -> :ok end,
      global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
    )
  end
end

port = System.get_env("BREEZE_SSH_PORT", "2222") |> String.to_integer()
username = System.get_env("BREEZE_SSH_USER", "demo")
password = System.get_env("BREEZE_SSH_PASSWORD", "demo")

system_dir = System.get_env("BREEZE_SSH_SYSTEM_DIR") || Path.expand("../../priv/ssh/", __DIR__)

case Termite.SSH.start_link(
       port: port,
       auth: [{username, password}],
       system_dir: system_dir,
       entrypoint: {SSHCounterEntrypoint, []}
     ) do
  {:ok, _daemon} ->
    :ok

  {:error, :eaddrinuse} ->
    raise """
    SSH example could not start because port #{port} is already in use.

    Try:
      BREEZE_SSH_PORT=2230 elixir examples/ssh_counter.exs
    """

  {:error, reason} ->
    raise "SSH example failed to start: #{inspect(reason)}"
end

IO.puts("""
Starting Breeze SSH example on localhost:#{port}

Connect with:
  ssh -p #{port} #{username}@localhost

Password:
  #{password}
""")

Process.sleep(:infinity)
