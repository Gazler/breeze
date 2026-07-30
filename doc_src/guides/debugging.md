# Debug a Breeze App

The first guide builds a small local application. Before we add persistence and
multiple nodes, we need a good way to see what the UI is doing.

In this guide, we use the Breeze remote inspector to:

* inspect rendered elements, focus, layout, theme values, and implicit component
  state
* capture Logger output and view it in the inspector's Logs tab instead of
  writing directly over the application UI

These are development-only tools. They help us understand an interactive
terminal app while we build it, but we should not enable the inspector in
production or expose it in an environment we do not control. Inspector logs are
also not a replacement for production log storage or monitoring.

## Enable Inspector Snapshots

Inspector collection should be an environment decision. Set a safe default in
`config/config.exs` and override it in `config/dev.exs`:

```elixir
# config/config.exs
import Config

config :task_pad,
  inspector: false,
  logger: false

import_config "#{config_env()}.exs"
```

```elixir
# config/dev.exs
import Config

config :task_pad,
  inspector: true,
  logger: :replace
```

Because `config/config.exs` imports an environment file, also create
`config/test.exs` and `config/prod.exs` containing `import Config`. The
persistence guide adds the test database settings later.

Then pass that setting to the app server:

```elixir
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
```

When enabled, Breeze collects inspection snapshots for the running UI. The
inspector can then show the rendered tree, element bounds, focus state, theme
values, and implicit component state for controls such as inputs, lists, tabs,
and scroll regions. Keep the setting `false` outside trusted development
environments.

## Run the Remote Inspector

The inspected app and the inspector UI can run in separate terminals. The app
starts as a named node:

```bash
elixir --sname task_pad -S mix run --no-halt
```

In another terminal, we run the inspector:

```bash
mix breeze.inspector --connect task_pad
```

The Mix task compiles the project, starts Breeze and its dependency applications
without starting `TaskPad.Application`, starts distribution as `:inspector`,
connects to `task_pad@current-host`, and opens the inspector UI. If distributed
Erlang is not running yet, the task reports the `epmd -daemon` command needed to
start it.

When the app and inspector are on the same host, Breeze tries to connect app
nodes to the `inspector@host` node automatically. This can work even when the
app itself was not started with `--sname`, because enabling inspector support
lets Breeze start distribution for the app process when it needs to publish
snapshots. If a connection is not established, we can connect the nodes manually
with `Node.connect/1` from either side.

## Use the Inspector

The remote inspector groups information into tabs. We use it to answer concrete
questions while building the UI:

* Tree: what did our `~H` template render?
* Element: where is the selected element on screen, and what attributes does it
  have?
* Theme: which semantic colors and styles are active?
* Implicit: what state does a component own, such as list selection, tab
  selection, scroll offsets, or input cursor position?
* Logs: what has the application written through Elixir's `Logger`?

This is useful when a list is not selecting the row we expect, a tab is not
emitting the value we expect, or a class is not resolving the way we think it
should.

## Read Logs in the Remote Inspector

Terminal applications need special care with logs. The default Logger terminal
handler writes to stdout or stderr, which is the same terminal Breeze is
rendering into. If logs write there directly, they render through the UI and
corrupt the screen.

When remote inspection is enabled, Breeze starts its log collector and streams
captured entries to the remote inspector. We set `logger: :replace` in
`config/dev.exs` so Breeze temporarily silences the default terminal handler
while the app server is running. The production default remains `false`, so
production keeps the logging setup chosen for that environment.

Open the remote inspector and select the **Logs** tab. It shows recent Logger
entries for the selected application node and follows new entries as they
arrive. Debug-level entries are captured too, so Ecto query logs appear there
without adding a logger live view to Task Pad.

Keeping the logger in the remote inspector means the debugging UI does not
participate in the application's layout, focus handling, or keybindings. It
also starts capturing when the server starts, so we do not need to preload a
logger view to retain entries emitted before opening the Logs tab.

## Keep Inspector Logs Out of Production Paths

The remote inspector is an interactive debugging tool. We should not rely on it
as the only log destination in production or in any environment where logs need
to persist after the inspector or application exits.

`:replace` is appropriate here because Breeze owns the development terminal. If
another process or group leader owns the real output path, use that environment's
normal logging system instead.

For production, we keep durable logging separate: files, journald, OpenTelemetry,
or whatever collector the host environment expects. During development, the
remote inspector keeps logs visible without adding debugging behavior to the
application UI.
