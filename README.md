# Breeze

An experimental TUI library with a LiveView-inspired API without using 3rd party
NIFs.

Breeze is built on top of [Termite](https://github.com/Gazler/termite) and
[BackBreeze](https://github.com/Gazler/back_breeze)

## Should I use this?

**This library is highly experimental and incomplete. It provides an example of
how a TUI based on LiveView could work.**

I mainly built it for writing snake, which is in the examples directory.

## Features:

- LiveView style API
- mount/2
- handle_event/3
- function components
- attributes
- slots
- Scrollable viewports via implicit modifiers (`scroll_y`, `scroll_x`, `scroll`)
- Built-in blocks for common UI patterns (`list`, `dropdown`, `tabs`,
  `markdown`, `scroll`, `panel`, `modal`)

## Does this actually use LiveView?

No. Breeze now ships with its own `~H` sigil and template runtime.

The syntax is intentionally similar to HEEx (`@assigns`, function components,
slots, `:for`, `:if`), but it does not depend on `phoenix_live_view`.

## Installation

Breeze can be installed by adding `breeze` to your list of dependencies in
`mix.exs`:

```elixir
def deps do
  [
    {:breeze, "~> 0.3.0"}
  ]
end
```

API docs, including previews for the built-in blocks, are published with ExDoc.

## Formatter

Breeze ships with a `mix format` plugin for `~H` templates:

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
Mix.install([{:breeze, "~> 0.3.0"}])

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
    <box style="grid grid-cols-1 grid-rows-2 width-screen height-screen">
      <box>
        <box style="text-5 bold">Counter: {@counter}</box>
      </box>
      <box style="height-1 bg-panel overflow-hidden">
        <.keybinding_bar keybindings={@breeze.keybindings}/>
      </box>
    </box>
    """
  end

  def handle_event(_, %{"key" => "ArrowUp"}, term), do:
    {:noreply, assign(term, counter: term.assigns.counter + 1)}

  def handle_event(_, %{"key" => "ArrowDown"}, term), do:
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

More examples are available in the examples directory.

## SSH

Breeze apps can also be served over SSH. Each connecting client gets its own
terminal session backed by `Termite.SSH`:

```elixir
:application.ensure_all_started(:ssh)

defmodule DemoEntrypoint do
  def start_link(opts) do
    session = Keyword.fetch!(opts, :session)

    Breeze.Server.start_link(
      view: Demo,
      terminal_opts: Termite.SSH.Session.terminal_opts(session),
      halt_fun: fn -> :ok end
    )
  end
end

{:ok, _daemon} = Termite.SSH.start_link(
  port: 2222,
  auth: [{"alice", "secret"}],
  entrypoint: {DemoEntrypoint, []}
)
```

Then connect with a normal SSH client:

```bash
ssh -p 2222 alice@localhost
```

There is also a runnable example:

```bash
mix run examples/ssh_counter.exs
```

For a fuller demo based on the posting example:

```bash
mix run examples/ssh_posting.exs
```

The authenticated username is injected into `mount/2` via `start_opts` as
`opts[:username]`.

## Testing

Breeze ships with `Breeze.Test` for deterministic view tests:

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

The rendered content keeps raw terminal escape sequences intact, so projects can
build their own snapshot assertions on top when needed.
