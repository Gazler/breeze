# Breeze

Breeze is an experimental TUI library with a LiveView-inspired API, built
without third-party NIFs.

Breeze is built on top of [Termite](https://github.com/Gazler/termite) and
[BackBreeze](https://github.com/Gazler/back_breeze).

## Project status

**Breeze is experimental and still evolving.** It provides a practical
foundation for building terminal interfaces with familiar LiveView-style
patterns.

The project began as the engine for the Snake game included in the
[examples directory](https://github.com/Gazler/breeze/tree/master/examples).

## Features

- LiveView-style API
- `mount/2`
- `handle_event/3`
- Function components
- Attributes
- Slots
- Scrollable viewports through implicit modifiers (`scroll_y`, `scroll_x`,
  `scroll`)
- Minimum-width breakpoints for responsive terminal layouts
- Built-in blocks for common interface patterns (`list`, `dropdown`, `tabs`,
  `markdown`, `scroll`, `panel`, `modal`)

## Template runtime

Breeze ships with its own `~H` sigil and template runtime, with no dependency on
`phoenix_live_view`.

Its syntax is intentionally familiar to HEEx users, including `@assigns`,
function components, slots, `:for`, and `:if`.

## Installation

Add `breeze` to the dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:breeze, "~> 0.5.0"}
  ]
end
```

The ExDoc documentation includes API references and previews of the built-in
blocks.

## Formatter

Breeze includes a `mix format` plugin for `~H` templates:

```elixir
# .formatter.exs
[
  plugins: [Breeze.HTMLFormatter],
  import_deps: [:breeze],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
```

## Examples

```elixir
Mix.install([{:breeze, "~> 0.5.0"}])

defmodule Demo do
  use Breeze.View
  import Breeze.Blocks

  def mount(_opts, term) do
    {:ok,
     term
     |> assign(counter: 0)
     |> put_local_keybindings([
       {"ArrowUp", "Increment"},
       {"ArrowDown", "Decrement"}
     ])}
  end

  def render(assigns) do
    ~H"""
    <box class="grid grid-cols-1 grid-rows-2 w-screen h-screen">
      <box class="text-5 font-bold">Counter: {@counter}</box>
      <box class="h-1 bg-panel overflow-hidden">
        <.keybinding_bar keybindings={@breeze.keybindings}/>
      </box>
    </box>
    """
  end

  def handle_event(:input, %{"key" => "ArrowUp"}, term), do:
    {:noreply, assign(term, counter: term.assigns.counter + 1)}

  def handle_event(:input, %{"key" => "ArrowDown"}, term), do:
    {:noreply, assign(term, counter: term.assigns.counter - 1)}

  def handle_event(_, _, term), do: {:noreply, term}
end

Breeze.Example.run(
  [
    view: Demo,
    global_keybindings: [{"q", "Quit", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
```

Explore more applications in the
[examples directory](https://github.com/Gazler/breeze/tree/master/examples).

## Storybook

Place stories in `storybook/*.story.exs`, then launch the interactive browser
from your project:

```bash
mix breeze.storybook
```

Use `--directory` to load another story directory or `--file` to open a single
story. The task inherits the project's development reload, inspector, error,
logger, and `:storybook_theme` configuration. Use `--theme`, `--[no-]reload`,
or `--[no-]inspector` to override the corresponding settings.

## SSH

Breeze applications can run over SSH. Each client receives an independent
terminal session backed by `Termite.SSH`:

```elixir
:application.ensure_all_started(:ssh)

defmodule DemoEntrypoint do
  def start_link(opts) do
    session = Keyword.fetch!(opts, :session)

    Breeze.Server.start_link(
      view: Demo,
      start_opts: [username: session.username],
      terminal_opts: Termite.SSH.Session.terminal_opts(session),
      halt_fun: fn -> :ok end
    )
  end
end

{:ok, _daemon} = Termite.SSH.start_link(
  port: 2222,
  auth: [{"alice", "secret"}],
  allow_insecure_auth: true,
  system_dir: "priv/ssh",
  entrypoint: {DemoEntrypoint, []}
)
```

Connect with any standard SSH client:

```bash
ssh -p 2222 alice@localhost
```

Run the included SSH counter example with:

```bash
elixir examples/ssh/ssh_counter.exs
```

For a more complete demonstration based on the posting example, run:

```bash
elixir examples/ssh/ssh_posting.exs
```

The authenticated username is injected into `mount/2` via `start_opts` as
`opts[:username]`.

For a supervised local listener, see
[Serve a Breeze App over SSH](doc_src/guides/ssh.md). When it is ready to share,
[deploy the SSH application to Fly.io](doc_src/guides/fly_io.md).

## Testing

Use `Breeze.Test` to write deterministic view tests:

```elixir
defmodule MyApp.CounterTest do
  use ExUnit.Case, async: true

  test "counter snapshot" do
    session = Breeze.Test.start!(MyApp.CounterView, size: {30, 5})
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert Breeze.Test.render!(session) =~ "Counter: 0"

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "ArrowUp")
    assert Breeze.Test.render!(session) =~ "Counter: 1"
  end
end
```

Rendered content preserves raw terminal escape sequences, making it
straightforward to add project-specific snapshot assertions.
