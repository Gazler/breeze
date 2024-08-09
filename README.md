# Breeze

An experimental TUI library based on LiveView without using 3rd party NIFs.

Breeze is built on top of [Termite](https://github.com/Gazler/termite) and [BackBreeze](https://github.com/Gazler/back_breeze)

## Should I use this?

**This library is highly experimental and incomplete. It provides an example of how a TUI
based on LiveView could work.**

I mainly built it for writing snake, which is in the examples directory.

## Features:

 * LiveView style API
  * mount/2
  * handle_event/3
  * components
  * attributes
  * slots

## Missing features

 * behaviours for all of the modules that expect callbacks
 * Whitespace is a bit janky in the Heex
 * A decent way to handle logging
 * A decent way to handle errors/exceptions
 * viewports/sizing calculations allowing for scrollable regions
  * this requires modifications to how BackBreeze renders boxes
 * A component library
 * handle colour variants

## Does this actually use LiveView?

Breeze *sort of* uses LiveView. LiveView is a required dependency for now as Heex is used to handle
rendering. Currently the way LiveView is used is very inefficient as we have to do multiple passes
to convert the Heex to BackBreeze boxes for rendering. If this experiment is successful, it is
likely that the Heex sections of LiveView will be ported to this project and modified in
a way that makes sense.

## Installation

Breeze can be installed by adding `breeze` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:breeze, "~> 0.2.0"}
  ]
end
```

## Examples

```elixir
Mix.install([{:breeze, "~> 0.2.0"}]

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
