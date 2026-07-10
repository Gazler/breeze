# Persist and Sync Task Pad

The first guide keeps Task Pad state inside one view. This guide moves tasks into
SQLite with Ecto and uses Phoenix.PubSub to notify every running Breeze view when
data changes. The view keeps only UI state: input text, the active filter, and
the selected task id.

## Add Dependencies

Add Ecto, SQLite, and PubSub to `mix.exs`:

```elixir
defp deps do
  [
    {:breeze, "~> 0.4.0"},
    {:ecto_sql, "~> 3.14"},
    {:ecto_sqlite3, "~> 0.24.1"},
    {:phoenix_pubsub, "~> 2.2"}
  ]
end
```

Fetch the dependencies:

```bash
mix deps.get
```

## Configure Ecto

Create `lib/task_pad/repo.ex`:

```elixir
defmodule TaskPad.Repo do
  use Ecto.Repo,
    otp_app: :task_pad,
    adapter: Ecto.Adapters.SQLite3
end
```

Configure it in `config/config.exs`. Keep the development tool defaults from
the debugging guide:

```elixir
import Config

config :task_pad,
  ecto_repos: [TaskPad.Repo],
  inspector: false,
  logger: false

config :task_pad, TaskPad.Repo,
  database: Path.expand("../task_pad_dev.db", __DIR__),
  pool_size: 5

import_config "#{config_env()}.exs"
```

Use an isolated database and the SQL sandbox in `config/test.exs`:

```elixir
import Config

config :task_pad, TaskPad.Repo,
  database: Path.expand("../task_pad_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :task_pad, :start_server, false
```

## Create the Schema

Create `lib/task_pad/tasks/task.ex`:

```elixir
defmodule TaskPad.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tasks" do
    field :title, :string
    field :done?, :boolean, source: :done, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :done?])
    |> validate_required([:title])
    |> update_change(:title, &String.trim/1)
    |> validate_length(:title, min: 1)
  end
end
```

Generate a migration:

```bash
mix ecto.gen.migration create_tasks
```

Define the table in the generated file:

```elixir
defmodule TaskPad.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :title, :text, null: false
      add :done, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end
  end
end
```

Create and migrate the development database:

```bash
mix ecto.create
mix ecto.migrate
```

Prepare the test database as well:

```bash
MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate
```

## Supervise Shared Services

Start the repo and PubSub before the Breeze server:

```elixir
defmodule TaskPad.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        TaskPad.Repo,
        {Phoenix.PubSub, name: TaskPad.PubSub}
      ] ++ breeze_children()

    Supervisor.start_link(children, strategy: :one_for_one, name: TaskPad.Supervisor)
  end

  defp breeze_children do
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

  defp start_server? do
    Application.get_env(:task_pad, :start_server, default_start_server?())
  end

  defp default_start_server? do
    if Code.ensure_loaded?(Mix), do: Mix.env() != :test, else: true
  end
end
```

The environment-specific inspector flag is configuration; the application
module does not need to know which Mix environment is running.

## Replace the In-Memory Model

Replace `TaskPad.InMemoryTasks` with an Ecto-backed `TaskPad.Tasks` context. The
important boundary is that successful writes broadcast after SQLite commits:

```elixir
defmodule TaskPad.Tasks do
  import Ecto.Query

  alias TaskPad.Repo
  alias TaskPad.Tasks.Task

  @topic "tasks"

  def subscribe do
    Phoenix.PubSub.subscribe(TaskPad.PubSub, @topic)
  end

  def list(filter) do
    Task
    |> filtered(filter)
    |> order_by([task], asc: task.id)
    |> Repo.all()
  end

  def all do
    Task
    |> order_by([task], asc: task.id)
    |> Repo.all()
  end

  def add(title) do
    %Task{}
    |> Task.changeset(%{title: title})
    |> Repo.insert()
    |> broadcast_from()
  end

  def toggle(nil), do: {:error, :no_selection}

  def toggle(id) do
    with {id, ""} <- Integer.parse(to_string(id)),
         %Task{} = task <- Repo.get(Task, id) do
      task
      |> Task.changeset(%{done?: !task.done?})
      |> Repo.update()
      |> broadcast_from()
    else
      _ -> {:error, :invalid_selection}
    end
  end

  def clear_done do
    Repo.delete_all(from task in Task, where: task.done?)
    broadcast_from({:ok, :cleared})
  end

  def valid_filter?(filter), do: filter in ["all", "open", "done"]

  def selected_visible_id(selected_id, tasks) do
    selected_id =
      case Integer.parse(to_string(selected_id)) do
        {id, ""} -> id
        _ -> nil
      end

    if Enum.any?(tasks, &(&1.id == selected_id)) do
      Integer.to_string(selected_id)
    else
      case tasks do
        [%Task{id: id} | _] -> Integer.to_string(id)
        [] -> nil
      end
    end
  end

  def status_text(tasks) do
    done = Enum.count(tasks, & &1.done?)
    "#{done}/#{length(tasks)} done"
  end

  defp filtered(query, "open"), do: where(query, [task], not task.done?)
  defp filtered(query, "done"), do: where(query, [task], task.done?)
  defp filtered(query, _filter), do: query

  defp broadcast_from({:ok, result} = response) do
    Phoenix.PubSub.broadcast_from(
      TaskPad.PubSub,
      self(),
      @topic,
      {:tasks_changed, result}
    )

    response
  end

  defp broadcast_from(other), do: other
end
```

`broadcast_from/4` excludes the calling view. That view reloads immediately
after its write; every other subscribed view reloads when it receives the
message. This avoids making the initiating view perform the same database reads
twice.

## Subscribe from the View

The view now loads tasks from the context and subscribes during `mount/2`:

```elixir
def mount(_opts, term) do
  :ok = TaskPad.Tasks.subscribe()

  {:ok,
   term
   |> focus("new-task")
   |> put_local_keybindings([
     {"Enter", "Add/toggle"},
     {"a", "New task"},
     {"n", "Connect peer"},
     {"c", "Clear done"}
   ])
   |> assign(
     tasks: TaskPad.Tasks.all(),
     visible_tasks: TaskPad.Tasks.list("all"),
     new_task: "",
     filter: "all",
     selected_task_id: nil,
     status: nil
   )
   |> normalize_selection()}
end
```

Remote changes arrive as ordinary view messages:

```elixir
def handle_info({:tasks_changed, _result}, term) do
  {:noreply, reload_tasks(term)}
end

def handle_info(_, term), do: {:noreply, term}
```

Local event handlers check write results and reload once:

```elixir
def handle_event(_, %{"key" => "Enter"}, %{focused: "new-task"} = term) do
  case TaskPad.Tasks.add(term.assigns.new_task) do
    {:ok, task} ->
      {:noreply,
       term
       |> assign(
         new_task: "",
         filter: "all",
         selected_task_id: to_string(task.id),
         status: nil
       )
       |> focus("tasks")
       |> reload_tasks()}

    {:error, _changeset} ->
      {:noreply, assign(term, status: "Task title cannot be empty")}
  end
end

def handle_event(_, %{"key" => key}, %{focused: "tasks"} = term)
    when key in ["Enter", " "] do
  _ = TaskPad.Tasks.toggle(term.assigns.selected_task_id)
  {:noreply, reload_tasks(term)}
end
```

Keep selection normalization in one helper so filtering, deletion, and remote
updates follow the same rule:

```elixir
defp reload_tasks(term) do
  term
  |> assign(
    tasks: TaskPad.Tasks.all(),
    visible_tasks: TaskPad.Tasks.list(term.assigns.filter)
  )
  |> normalize_selection()
end

defp normalize_selection(term) do
  selected_id =
    TaskPad.Tasks.selected_visible_id(
      term.assigns.selected_task_id,
      term.assigns.visible_tasks
    )

  assign(term, selected_task_id: selected_id)
end
```

The final render function reads `@tasks` and `@visible_tasks`; it no longer
derives domain state from a map owned by the view.

## Discover a Local Peer

EPMD already knows which named Erlang nodes are running on the local machine.
`:net_adm.names/0` returns their short names as charlists, so we can build the
available peer names as strings instead of compiling the machine's hostname
into a static allowlist.

Both Task Pad nodes use the `term` prefix. Discover those nodes, remove the
current node, and connect the first available peer:

```elixir
defmodule TaskPad.Peers do
  @prefix "term"

  def connect(current_node \\ node()) do
    with {:ok, [peer | _]} <- available(current_node),
         true <- Node.connect(String.to_atom(peer)) do
      {:ok, peer}
    else
      {:ok, []} -> {:error, :no_peer}
      false -> {:error, :connection_failed}
      :ignored -> {:error, :distribution_not_started}
      {:error, reason} -> {:error, reason}
    end
  end

  def available(current_node \\ node()) do
    current = Atom.to_string(current_node)

    with {:ok, host} <- node_host(current),
         {:ok, names} <- :net_adm.names() do
      peers =
        names
        |> Enum.map(fn {name, _port} -> "#{name}@#{host}" end)
        |> Enum.filter(&String.starts_with?(&1, @prefix))
        |> Enum.reject(&(&1 == current))
        |> Enum.sort()

      {:ok, peers}
    end
  end

  defp node_host(current) do
    case String.split(current, "@", parts: 2) do
      [_name, "nohost"] -> {:error, :distribution_not_started}
      [_name, host] -> {:ok, host}
    end
  end
end
```

`Node.connect/1` still requires an atom, so the selected EPMD result is converted
at the connection boundary. This is suitable for a trusted local development
machine with the constrained `term` prefix. A production system should use
trusted service discovery that returns a bounded peer set; atoms are not
garbage-collected.

Connect from the existing `n` event:

```elixir
def handle_event(_, %{"key" => "n"}, term) do
  status =
    case TaskPad.Peers.connect() do
      {:ok, peer} -> "Connected to #{peer}"
      {:error, :no_peer} -> "No other Task Pad node found"
      {:error, :distribution_not_started} -> "Start Task Pad with --sname"
      {:error, _reason} -> "Could not connect to peer"
    end

  {:noreply, assign(term, status: status)}
end
```

## Run Two Instances

Start both instances with short names. Erlang adds the local hostname to each
name, and EPMD makes both names discoverable:

```bash
elixir --sname term1 -S mix run --no-halt
```

```bash
elixir --sname term2 -S mix run --no-halt
```

Both VMs normally share the Erlang cookie when they run as the same OS user.
Press `n` in either task list to connect the peer. Once connected, Phoenix.PubSub
delivers broadcasts between the nodes, and both repos access the same SQLite
file.

SQLite is appropriate for this local demonstration. For independently deployed
nodes, use a shared database service rather than a filesystem path that happens
to be common to two local processes.

## Test Synchronization

Use a shared SQL sandbox owner so both child view processes can access the test
connection:

```elixir
defmodule TaskPad.SyncTest do
  use ExUnit.Case, async: false

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TaskPad.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(TaskPad.Repo, {:shared, self()})
    TaskPad.Repo.delete_all(TaskPad.Tasks.Task)
    :ok
  end

  test "two views stay in sync" do
    first = Breeze.Test.start!(TaskPad.View, size: {80, 18})
    second = Breeze.Test.start!(TaskPad.View, size: {80, 18})

    on_exit(fn ->
      Breeze.Test.stop(first)
      Breeze.Test.stop(second)
    end)

    assert Breeze.Test.render!(first) =~ "Task Pad"
    assert Breeze.Test.render!(second) =~ "Task Pad"

    for key <- String.graphemes("Shared task") do
      assert {:noreply, "new-task", true} = Breeze.Test.input(first, key)
    end

    assert {:noreply, "tasks", true} = Breeze.Test.input(first, "Enter")
    assert_eventually(fn -> Breeze.Test.render!(second) =~ "Shared task" end)
  end

  defp assert_eventually(fun, attempts \\ 50)

  defp assert_eventually(_fun, 0) do
    flunk("condition did not become true")
  end

  defp assert_eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      assert_eventually(fun, attempts - 1)
    end
  end
end
```

The explicit zero-attempt clause preserves a useful assertion failure instead
of ending in an unrelated `FunctionClauseError`.
