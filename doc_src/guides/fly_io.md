# Deploy a Breeze SSH App to Fly.io

Now we have our application, we want to show it to the world. This guide shows
how to deploy it to [Fly.io](https://fly.io) using the
[`Termite.SSH`](https://hexdocs.pm/termite_ssh/Termite.SSH.html) adapter.

Task Pad already accepts SSH connections locally. We will replace its local
unauthenticated listener with password authentication, build an Elixir release,
persist its SQLite database and SSH host identity, and expose the listener as a
raw TCP service.

Two Fly platform details shape the deployment:

* Fly Proxy exposes the application as raw TCP over the dedicated IPv6 address
  Fly assigns to the app. This guide does not allocate IPv4.
* Fly Machines have ephemeral root filesystems. A volume stores Task Pad's
  SQLite database, while a secret-backed file gives every replacement Machine
  the same SSH host identity.

The public listener uses a password callback. Do not expose a plaintext
credential list, `auth: :none`, or `allow_insecure_auth: true` on Fly.

## Configure production SSH and persistence

Replace the local SSH block in `config/runtime.exs` with deployment-aware
configuration:

```elixir
import Config

if config_env() == :prod do
  database_path = System.get_env("TASK_PAD_DATABASE_PATH", "/data/task_pad.db")

  config :task_pad, TaskPad.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "5"))
end

if System.get_env("BREEZE_SSH_SERVER") == "true" do
  password = System.fetch_env!("BREEZE_SSH_PASSWORD")
  system_dir = System.fetch_env!("BREEZE_SSH_SYSTEM_DIR")
  port = System.get_env("BREEZE_SSH_PORT", "2222") |> String.to_integer()

  ip =
    case System.get_env("BREEZE_SSH_IP", "loopback") do
      "loopback" -> {127, 0, 0, 1}
      "any" -> {0, 0, 0, 0}
      value -> raise "invalid BREEZE_SSH_IP: #{inspect(value)}"
    end

  password_verifier = fn _username, supplied_password, _peer, state ->
    expected_digest = :crypto.hash(:sha256, password)
    supplied_digest = :crypto.hash(:sha256, supplied_password)

    {:crypto.hash_equals(expected_digest, supplied_digest), state}
  end

  config :task_pad, :ssh_options,
    ip: ip,
    port: port,
    system_dir: system_dir,
    auth: {:password, password_verifier},
    entrypoint: {TaskPad.SSHEntrypoint, []},
    max_sessions: 100
end
```

The `system_dir` must contain a server private key named like
`ssh_host_rsa_key`.

The verifier accepts the shared password for any SSH username. `Termite.SSH`
still records the client-supplied name in `session.username`, and the entrypoint
passes it to the view as `opts[:username]`. Hashing both values before
`:crypto.hash_equals/2` keeps the comparison constant-time.

SSH keys are a secure alternative, but their authorized public keys must be
provided to the application out-of-band, such as through a configured file or
a dynamic verifier. This guide uses one password secret to keep provisioning
small.

Fly sets `BREEZE_SSH_IP=any` because Fly Proxy must reach the listener over the
Machine network. Leaving the local loopback bind in place produces a deployment
that starts successfully but cannot accept public connections.

## Add a release migration helper

Create `lib/task_pad/release.ex`:

```elixir
defmodule TaskPad.Release do
  @app :task_pad

  def migrate do
    Application.load(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _fun_return, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end
end
```

The container entrypoint will call this before starting the application. Ecto
migrations are idempotent, so a replacement Machine can run the command against
the existing volume safely. This guide deploys one Machine; coordinate
migrations separately before scaling to multiple writers.

## Add the container entrypoint

Fly creates the configured host-key file and mounts the volume as root during
boot. Add `deploy/docker-entrypoint.sh` to restrict key permissions, make the
data directory writable by the release user, run migrations, and then drop
from root to `nobody`:

```sh
#!/bin/sh
set -eu

if [ -d /data ]; then
  chown nobody:root /data
  chmod 750 /data
fi

if [ -e /app/ssh_host_rsa_key ]; then
  chown nobody:root /app/ssh_host_rsa_key
  chmod 600 /app/ssh_host_rsa_key
fi

if [ "${1:-}" = "/app/bin/task_pad" ] && [ "${2:-}" = "start" ]; then
  gosu nobody /app/bin/task_pad eval "TaskPad.Release.migrate()"
fi

exec gosu nobody "$@"
```

Make it executable:

```bash
chmod +x deploy/docker-entrypoint.sh
```

## Build an Elixir release image

This Dockerfile uses Elixir 1.20 on OTP 29. Keep the Elixir, OTP, and Debian
snapshot values aligned with a published
[`hexpm/elixir` image](https://hub.docker.com/r/hexpm/elixir/tags) when updating
their patch versions:

```dockerfile
ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=29.0.3
ARG DEBIAN_VERSION=bookworm-20260623-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY config config
RUN mix deps.compile

COPY . .
RUN mix deps.get --only prod
RUN mix compile
RUN mix release

FROM ${RUNNER_IMAGE} AS runner

ENV LANG=C.UTF-8

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends \
    ca-certificates gosu libncurses6 libsctp1 libstdc++6 openssl \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder --chown=nobody:root /app/_build/prod/rel/task_pad ./
COPY --chmod=755 deploy/docker-entrypoint.sh /usr/local/bin/docker-entrypoint

ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]
CMD ["/app/bin/task_pad", "start"]
```

The release name and copied directory default to the Mix application name. If
the project defines a different release name, update the release command, copy
path, and entrypoint migration check together.

Add `.dockerignore` so local build output, databases, and keys never enter the
build context:

```text
_build
deps
.git
test
*.db*
priv/ssh
deploy/ssh_host_*_key
```

Build the image locally if Docker is available:

```bash
docker build -t task-pad .
```

## Create the Fly application

Install `flyctl`, authenticate, and create the application without deploying
yet:

```bash
fly auth login
fly launch --no-deploy --ha=false --no-public-ips
```

Keep `--no-deploy` on this command. At this point, Fly should create and
configure the application without deploying or starting a Machine. If an
interrupted launch leaves the local terminal behaving strangely, restore it
with `stty sane; reset`. `--no-public-ips` also makes address allocation
explicit so the application receives only the IPv6 address added below.

Keep the generated application name and preferred region, then replace the
generated HTTP service in `fly.toml` with a volume mount and raw TCP service.
This example maps public port 22 to the release's port 2222:

```toml
app = "replace-with-your-app-name"
primary_region = "lhr"

[build]

[env]
  BREEZE_SSH_SERVER = "true"
  BREEZE_SSH_IP = "any"
  BREEZE_SSH_PORT = "2222"
  BREEZE_SSH_SYSTEM_DIR = "/app"
  TASK_PAD_DATABASE_PATH = "/data/task_pad.db"

[mounts]
  source = "task_pad_data"
  destination = "/data"

[[files]]
  guest_path = "/app/ssh_host_rsa_key"
  secret_name = "BREEZE_SSH_HOST_KEY"

[[services]]
  protocol = "tcp"
  internal_port = 2222
  auto_stop_machines = "stop"
  auto_start_machines = true
  min_machines_running = 0

  [[services.ports]]
    port = 22

[[vm]]
  memory = "512mb"
  cpu_kind = "shared"
  cpus = 1
```

There are no `http` or `tls` handlers on port 22. Fly Proxy forwards the SSH
TCP stream unchanged. Autostop reduces idle Machine usage; the first connection
after a stop can take longer while Fly starts the Machine.

The 512 MiB allocation leaves headroom for OTP, SSH session state, SQLite, and
transient rendering work. A 256 MiB Machine can run out of memory when multiple
terminals are connected even while the persistent render caches remain small.

## Provision the host key and password

Create a host key for this deployment. Keep its private half out of Git and
back it up somewhere protected; Fly secrets cannot be read back after they are
set:

```bash
mkdir -p deploy
ssh-keygen -q -t rsa -b 3072 -m PEM -N "" -f deploy/ssh_host_rsa_key
```

Never commit `deploy/ssh_host_rsa_key`.

Store the host private key in Fly's encrypted secret store. A secret-backed
file value must be Base64 encoded:

```bash
fly secrets set \
  BREEZE_SSH_HOST_KEY="$(base64 < deploy/ssh_host_rsa_key)" \
  --stage
```

Choose a long random password, save it in a password manager, and stage it as a
second Fly secret:

```bash
fly secrets set \
  BREEZE_SSH_PASSWORD="replace-with-a-long-random-password" \
  --stage
```

The `[[files]]` entry decodes the host-key secret into the filename expected by
OTP SSH. Replacement Machines therefore present the same host identity, while
the password is available only through the Machine environment.

## Create the volume

Create the SQLite volume in the same region as the Machine:

```bash
fly volumes create task_pad_data --region lhr --size 1
```

A Fly Volume belongs to one Machine in one region. This guide deliberately
uses one Machine and `--ha=false`. Scaling SQLite behind multiple Machines
requires a deliberate single-writer topology, one volume per Machine, or a
shared database service.

For off-Machine backups, [Litestream](https://litestream.io/) can continuously
replicate this SQLite database to object storage.

## Deploy over IPv6

Allocate a dedicated Anycast IPv6 address. Public IP allocations are managed
separately from `fly.toml`, and this command does not allocate an IPv4 address:

```bash
fly ips allocate-v6
fly ips list
```

Deploy one Machine:

```bash
fly deploy --ha=false
```

Check the assigned address, migration, startup, and listener errors with:

```bash
fly ips list
fly status
fly logs
```

Connect through the public service, forcing the IPv6 path. Port 22 is external,
so no `-p` option is needed:

```bash
ssh -6 alice@replace-with-your-app-name.fly.dev
```

The client must have a working IPv6 route. If the hostname resolves but SSH
reports `Network is unreachable`, the Fly address and DNS are configured but
the client network cannot reach IPv6. Use an IPv6-capable network or allocate
the dedicated IPv4 address described below.

Replace `alice` with the name the application should see. Everyone shares the
same password, so the name identifies a session but does not prove a separate
user identity.

If IPv4-only clients need access later, `fly ips allocate-v4` adds a billed
dedicated IPv4 address. After it is allocated, connect without the `-6` option.

## Update access and deploy again

To rotate the shared password, stage a new `BREEZE_SSH_PASSWORD` and deploy. To
rotate the host identity, create and back up a new host key, update
`BREEZE_SSH_HOST_KEY`, and deploy. Clients will correctly report that the server
identity changed; coordinate the new fingerprint before asking them to replace
a `known_hosts` entry.

The host key remains stable across Machine replacement because it comes from
the app secret. Task data remains on the attached volume.

## Production checklist

Before sharing the endpoint:

* keep callback authentication enabled; do not deploy `auth: :none`, a
  plaintext credential list, or `allow_insecure_auth: true`
* use a long random password and add cross-connection rate limiting before
  exposing a high-value application
* retain a protected backup of the host private key and record its fingerprint
* keep the inspector disabled and send production logs to Fly's stdout/stderr
  path or another durable collector
* choose `max_sessions`, SSH timeouts, and Fly Machine resources for the
  expected workload
* use `fly logs` and `ssh -vvv` to separate application, network, and client
  authentication failures

`Termite.SSH` exposes only the terminal application channel. Command execution,
SFTP, and SSH TCP forwarding are disabled. Fly's `fly ssh console` command is a
separate administrative path controlled by Fly access.
