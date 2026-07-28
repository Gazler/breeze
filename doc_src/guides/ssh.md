# Serve a Breeze App over SSH

An SSH listener lets people run a Breeze application without installing the
project or attaching to the terminal that started it. Each connection gets an
independent `Breeze.Server`, while the application keeps its normal view,
renderer, and event lifecycle.

This guide adds [`Termite.SSH`](https://hexdocs.pm/termite_ssh/Termite.SSH.html)
to Task Pad and verifies the complete connection locally. It skips
authentication on a loopback-only listener. That is convenient for a local
exercise, but it is deliberately not a production setup.

## Add the SSH transport

Add `termite_ssh` to `mix.exs` alongside Breeze:

```elixir
defp deps do
  [
    {:breeze, "~> 0.4.0"},
    {:ecto_sql, "~> 3.14"},
    {:ecto_sqlite3, "~> 0.24.1"},
    {:phoenix_pubsub, "~> 2.2"},
    {:termite_ssh, "~> 0.1.0"}
  ]
end
```

Fetch the dependency:

```bash
mix deps.get
```

## Add a session entrypoint

Create `lib/task_pad/ssh_entrypoint.ex`:

```elixir
defmodule TaskPad.SSHEntrypoint do
  def start_link(opts) do
    session = Keyword.fetch!(opts, :session)

    Breeze.Server.start_link(
      view: TaskPad.View,
      start_opts: [username: session.username],
      terminal_opts: Termite.SSH.Session.terminal_opts(session),
      theme: Breeze.Theme.builtin(:gruvbox),
      mouse: true,
      halt_fun: fn -> :ok end,
      global_keybindings: [
        {"F3", "Cycle theme", &Breeze.View.cycle_theme/2},
        {"F10", "Disconnect", fn _event, term -> {:stop, term} end}
      ]
    )
  end
end
```

`Termite.SSH` adds the SSH session to the entrypoint options. Its
`terminal_opts` route input, output, resize, and disconnect events through the
same public `Breeze.Server.start_link/1` lifecycle used by a local terminal.

`halt_fun` is a no-op because ending one view should close only that SSH
session, not halt the VM that owns every connection. Passing `username` through
`start_opts` is optional, but makes it available to `mount/2` as
`opts[:username]`.

## Configure a local listener

Create `config/runtime.exs` so the listener can be enabled without baking a
machine-specific path into the release:

```elixir
import Config

if System.get_env("BREEZE_SSH_SERVER") == "true" do
  system_dir = System.fetch_env!("BREEZE_SSH_SYSTEM_DIR")
  port = System.get_env("BREEZE_SSH_PORT", "2222") |> String.to_integer()

  config :task_pad, :ssh_options,
    ip: {127, 0, 0, 1},
    port: port,
    system_dir: system_dir,
    auth: :none,
    allow_insecure_auth: true,
    entrypoint: {TaskPad.SSHEntrypoint, []},
    max_sessions: 10
end
```

`termite_ssh` 0.1.0 rejects `auth: :none` unless
`allow_insecure_auth: true` is explicit. The name is intentional: every client
can connect without proving its identity. This example limits that risk by
binding only to `127.0.0.1`.

## Select SSH or the local terminal

When SSH is disabled, Task Pad should keep starting its one local
`Breeze.Server`. When SSH options exist, `Termite.SSH` owns the listener and
starts one server through the entrypoint for each connection.

Replace `breeze_children/0` in `TaskPad.Application` with these
transport-aware helpers, retaining the repo, PubSub, and other existing
children:

```elixir
defp breeze_children do
  case Application.get_env(:task_pad, :ssh_options) do
    nil -> local_breeze_children()
    ssh_options -> [{Termite.SSH, ssh_options}]
  end
end

defp local_breeze_children do
  if start_server?() do
    [
      Supervisor.child_spec(
        {Breeze.Server,
         view: TaskPad.View,
         theme: Breeze.Theme.builtin(:gruvbox),
         mouse: true,
         inspector: Application.get_env(:task_pad, :inspector, false),
         logger: Application.get_env(:task_pad, :logger, false),
         global_keybindings: [
           {"F3", "Cycle theme", &Breeze.View.cycle_theme/2},
           {"F10", "Quit", fn _event, term -> {:stop, term} end}
         ]},
        restart: :temporary
      )
    ]
  else
    []
  end
end
```

Keep the existing `start_server?/0` helper. The SSH transport remains at the
application boundary; views do not need SSH-specific render or event code.

## Generate a development host key

Every SSH server needs a stable key that identifies the host. Generate a PEM
RSA key for local development:

```bash
mkdir -p priv/ssh
ssh-keygen -q -t rsa -b 2048 -m PEM -N "" -f priv/ssh/ssh_host_rsa_key
```

Keep the generated private key and its local public half out of version
control:

```gitignore
# .gitignore
/priv/ssh/ssh_host_*_key
/priv/ssh/ssh_host_*_key.pub
```

## Start and connect

Start the loopback listener:

```bash
BREEZE_SSH_SERVER=true \
BREEZE_SSH_SYSTEM_DIR="$PWD/priv/ssh" \
mix run --no-halt
```

Open two more terminal windows and run this command in each one. No
authentication prompt is expected:

```bash
ssh \
  -o PubkeyAuthentication=no \
  -o PasswordAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  -p 2222 \
  taskpad@localhost
```

With Task Pad open in both terminals, add or toggle a task in one of them. The
other terminal should update immediately: each SSH connection has its own
`Breeze.Server`, while both sessions share the Ecto context and receive the
same PubSub broadcasts.

Press `F10` in each terminal to disconnect its session. The listener remains
available for another client until the application process stops.

Before exposing the listener beyond loopback, replace `auth: :none` with
`Termite.SSH` public-key or callback authentication and remove
`allow_insecure_auth: true`. The separate [Fly.io deployment guide](fly_io.md)
does that while packaging the application as a release.
