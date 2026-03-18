if Code.ensure_loaded?(Mix.ProjectStack) and Process.whereis(Mix.ProjectStack) do
  raise """
  `examples/ssh_posting.exs` must be run with `elixir`, not `mix`.

  Run:
    BREEZE_SSH_PORT=2230 elixir examples/ssh_posting.exs
  """
end

Mix.install([
  {:breeze, path: "../breeze"},
  {:termite, github: "gazler/termite", override: true},
  {:termite_ssh, github: "gazler/termite_ssh"}
])

try do
  Mix.Tasks.Termite.Ssh.GenHostKey.run([])
rescue
  _ -> nil
end

Application.put_env(:breeze, :example_mode, :load_only)
Code.require_file("../posting.exs", __DIR__)
Application.delete_env(:breeze, :example_mode)

defmodule SSHPostingEntrypoint do
  def start_link(opts) do
    session = Keyword.fetch!(opts, :session)

    Breeze.Server.start_link(
      view: Posting,
      start_opts: [username: session.username],
      terminal_opts: Termite.SSH.Session.terminal_opts(session),
      hide_cursor: true,
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
       entrypoint: {SSHPostingEntrypoint, []}
     ) do
  {:ok, _daemon} ->
    :ok

  {:error, :eaddrinuse} ->
    raise """
    SSH posting example could not start because port #{port} is already in use.

    Try:
      BREEZE_SSH_PORT=2230 elixir examples/ssh_posting.exs
    """

  {:error, reason} ->
    raise "SSH posting example failed to start: #{inspect(reason)}"
end

IO.puts("""
Starting Breeze Posting over SSH on localhost:#{port}

Connect with:
  ssh -p #{port} #{username}@localhost

Password:
  #{password}
""")

Process.sleep(:infinity)
