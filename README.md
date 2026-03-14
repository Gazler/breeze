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
- components
- attributes
- slots
- Scrollable viewports via implicit modifiers (`scroll_y`, `scroll_x`, `scroll`)

## Missing features

- behaviours for all of the modules that expect callbacks
- Whitespace is a bit janky in the template engine
- A decent way to handle logging
- A decent way to handle errors/exceptions
- scrollbars for viewport/list components
- A component library
- handle colour variants

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
    {:breeze, "~> 0.2.0"}
  ]
end
```

## Formatter

Breeze ships with a `mix format` plugin for `~H` templates:

```elixir
# .formatter.exs
[
  plugins: [Breeze.HTMLFormatter],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
```

## Examples

```elixir
Mix.install([{:breeze, "~> 0.2.0"}])

defmodule Demo do
  use Breeze.View

  def mount(_opts, term), do: {:ok, assign(term, counter: 0)}

  def render(assigns) do
    ~H"""
      <box style="text-5 bold">Counter: <%= @counter %></box>
    """
  end

  def handle_event(_, %{"key" => "ArrowUp"}, term), do:
    {:noreply, assign(term, counter: term.assigns.counter + 1)}

  def handle_event(_, %{"key" => "ArrowDown"}, term), do:
    {:noreply, assign(term, counter: term.assigns.counter - 1)}

  def handle_event(_, %{"key" => "q"}, term), do: {:stop, term}
  def handle_event(_, _, term), do: {:noreply, term}
end

Breeze.Server.start_link(view: Demo)
receive do
end

```

More examples are available in the examples directory.

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
