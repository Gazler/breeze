# Build a Simple Breeze App

In this guide, we will build a small Breeze application in the same style you may
recognize from Phoenix LiveView. We will initialize state in `mount/2`, render
from assigns, react to events in `handle_event/3`, and test the view without
starting an interactive terminal.

The example app is **Task Pad**, a tiny todo list. It is intentionally small, but
it covers the pieces most Breeze applications need: assigns, `~H` templates,
inputs, lists, focus, keybindings, events, themes, and tests.

## Create a Mix project

We start by generating a supervised Mix application:

```bash
mix new task_pad --sup
cd task_pad
```

Then we add Breeze to `mix.exs`:

```elixir
defp deps do
  [
    {:breeze, "~> 0.5.0"}
  ]
end
```

`0.5.0` is the version this guide targets.

Then we fetch dependencies:

```bash
mix deps.get
```

## Add the data layer

We keep application rules out of the terminal view. We will create
`lib/task_pad/in_memory_tasks.ex` to own the task list state and transformations:

```elixir
defmodule TaskPad.InMemoryTasks do
  @filters ["all", "open", "done"]

  def new do
    %{
      tasks: [
        %{id: "1", title: "Read the Breeze README", done?: true},
        %{id: "2", title: "Build a small terminal app", done?: false}
      ],
      next_id: 3
    }
  end

  def add(state, title) do
    title = String.trim(title)

    if title == "" do
      state
    else
      task = %{id: Integer.to_string(state.next_id), title: title, done?: false}
      %{state | tasks: state.tasks ++ [task], next_id: state.next_id + 1}
    end
  end

  def toggle(state, nil), do: state

  def toggle(state, task_id) do
    tasks =
      Enum.map(state.tasks, fn
        %{id: ^task_id} = task -> %{task | done?: !task.done?}
        task -> task
      end)

    %{state | tasks: tasks}
  end

  def clear_done(state), do: %{state | tasks: Enum.reject(state.tasks, & &1.done?)}

  def visible(state, filter) do
    case filter do
      "open" -> Enum.reject(state.tasks, & &1.done?)
      "done" -> Enum.filter(state.tasks, & &1.done?)
      _ -> state.tasks
    end
  end

  def valid_filter?(filter), do: filter in @filters

  def selected_visible_id(nil, []), do: nil

  def selected_visible_id(selected_id, tasks) do
    if Enum.any?(tasks, &(&1.id == selected_id)) do
      selected_id
    else
      case tasks do
        [%{id: id} | _] -> id
        [] -> nil
      end
    end
  end

  def status_text(state) do
    done = Enum.count(state.tasks, & &1.done?)
    total = length(state.tasks)
    "#{done}/#{total} done"
  end
end
```

For a real app, this module is where we add persistence, validation, or calls to
a database-backed context. The Breeze view stays focused on input, focus, and
rendering.

## Add the view

Next we create `lib/task_pad/view.ex`. Breeze's API is LiveView-inspired, but it
does not depend on Phoenix LiveView.

```elixir
defmodule TaskPad.View do
  use Breeze.View
  import Breeze.Blocks

  def mount(_opts, term) do
    {:ok,
     term
     |> focus("new-task")
     |> assign(
       tasks_state: TaskPad.InMemoryTasks.new(),
       new_task: "",
       filter: "all",
       selected_task_id: "1"
     )}
  end
end
```

`term` is the Breeze view state. We assign values to it, choose the focused
element, and return `{:ok, term}`.

## Render from assigns

`render/1` returns a Breeze `~H` template. The template syntax is intentionally
close to HEEx: we use `@assigns`, function components, slots, `:if`, and `:for`.
`assign/2` also accepts the plain map passed to `render/1`; values added there
exist only for that render and are not written back to the view process. That is
the right place for projections such as the visible task list and empty-state
message.

```elixir
def render(assigns) do
  assigns =
    assign(assigns,
      visible_tasks: TaskPad.InMemoryTasks.visible(assigns.tasks_state, assigns.filter),
      empty_message: empty_message(assigns.filter)
    )

  ~H"""
  <box class="grid grid-cols-1 grid-rows-2 w-screen h-screen bg">
    <box class="h-4 pl-2 pr-2 pt-1">
      <box class="inline w-full">
        <box class="font-bold text-primary">Task Pad</box>
        <box class="text-muted">  A small Breeze app</box>
        <box class="w-full text-right text-muted">
          {TaskPad.InMemoryTasks.status_text(@tasks_state)}
        </box>
      </box>
      <.tabs
        id="filters"
        selected={@filter}
        br-change="filter_changed"
        panel={false}
        variant="underline"
        class="w-full pt-1"
      >
        <:tab value="all" label="All"/>
        <:tab value="open" label="Open"/>
        <:tab value="done" label="Done"/>
      </.tabs>
    </box>

    <box class="h-full pl-2 pr-2">
      <box class="h-3">
        <box class="text-muted">New task</box>
        <.input
          id="new-task"
          input-value={@new_task}
          input-placeholder="Type a task and press Enter"
          br-change="new_task_changed"
          class="w-full"
        >
          {@new_task}
        </.input>
      </box>

      <box class="h-full pt-1">
        <.list
          :if={@visible_tasks != []}
          id="tasks"
          br-change="task_selected"
          list-selected={selected_visible_id(@selected_task_id, @visible_tasks)}
          class="h-full w-full"
          item_class="w-full"
        >
          <:item :for={task <- @visible_tasks} value={task.id}>
            {task_label(task)}
          </:item>
        </.list>

        <box :if={@visible_tasks == []} class="border h-full w-full text-muted">
          {@empty_message}
        </box>
      </box>
    </box>
  </box>
  """
end
```

The built-in blocks handle the terminal-specific behavior. The input captures
typing while focused. The tabs handle left and right navigation and emit a
change event when the active filter changes. The list handles selection with
arrow keys and emits a change event when the selected item changes.

A list retains its own selection, so most applications do not need to copy that
state into an assign. Task Pad deliberately makes the selection controlled:
`selected_task_id` lets event handlers toggle the selected task, while
`list-selected` lets adding, filtering, and clearing tasks choose which entry
remains selected.

For larger collections, add `virtual` to `<.list>`. This keeps the rendered
tree bounded to the visible rows plus overscan, but it is not pagination:
Breeze still holds and processes the full item collection. Virtual rows should
have a predictable, fixed height. The optimized plain-text path renders one
terminal row per item and truncates long labels instead of wrapping them;
custom variants, item styling, or nested markup use structured windowing
instead.

## Handle events

Components emit named events through `br-change`, and keyboard input arrives as a
regular Breeze event.

```elixir
def handle_event("new_task_changed", %{value: value}, term) do
  {:noreply, assign(term, new_task: value)}
end

def handle_event("task_selected", %{value: task_id}, term) do
  {:noreply, assign(term, selected_task_id: task_id)}
end

def handle_event("filter_changed", %{value: filter}, term) do
  {:noreply, set_filter(term, filter)}
end

def handle_event(_, %{"key" => "Enter"}, %{focused: "new-task"} = term) do
  {:noreply, add_task(term)}
end

def handle_event(_, %{"key" => key}, %{focused: "tasks"} = term)
    when key in ["Enter", " "] do
  {:noreply, toggle_selected_task(term)}
end

def handle_event(_, %{"key" => "a"}, term), do: {:noreply, focus(term, "new-task")}
def handle_event(_, %{"key" => "c"}, term), do: {:noreply, clear_done(term)}
def handle_event(_, _, term), do: {:noreply, term}
```

The helper functions are ordinary Elixir. We keep state changes small and
explicit:

```elixir
defp add_task(term) do
  title = String.trim(term.assigns.new_task)

  if title == "" do
    term
  else
    tasks_state = TaskPad.InMemoryTasks.add(term.assigns.tasks_state, title)
    selected_task_id = Integer.to_string(term.assigns.tasks_state.next_id)

    assign(term,
      tasks_state: tasks_state,
      new_task: "",
      selected_task_id: selected_task_id,
      filter: "all"
    )
    |> focus("tasks")
  end
end

defp toggle_selected_task(term) do
  selected_id = selected_visible_id(term.assigns.selected_task_id, visible_tasks(term))
  tasks_state = TaskPad.InMemoryTasks.toggle(term.assigns.tasks_state, selected_id)

  assign(term, tasks_state: tasks_state, selected_task_id: selected_id)
end

defp clear_done(term) do
  tasks_state = TaskPad.InMemoryTasks.clear_done(term.assigns.tasks_state)
  visible_tasks = TaskPad.InMemoryTasks.visible(tasks_state, term.assigns.filter)
  selected_id =
    TaskPad.InMemoryTasks.selected_visible_id(term.assigns.selected_task_id, visible_tasks)

  assign(term, tasks_state: tasks_state, selected_task_id: selected_id)
end

defp set_filter(term, filter) do
  if TaskPad.InMemoryTasks.valid_filter?(filter) do
    visible_tasks = TaskPad.InMemoryTasks.visible(term.assigns.tasks_state, filter)
    selected_id =
      TaskPad.InMemoryTasks.selected_visible_id(term.assigns.selected_task_id, visible_tasks)

    assign(term, filter: filter, selected_task_id: selected_id)
  else
    term
  end
end

defp visible_tasks(term) do
  TaskPad.InMemoryTasks.visible(term.assigns.tasks_state, term.assigns.filter)
end

defp selected_visible_id(selected_id, tasks) do
  TaskPad.InMemoryTasks.selected_visible_id(selected_id, tasks)
end

defp task_label(%{done?: true, title: title}), do: "[x] " <> title
defp task_label(%{done?: false, title: title}), do: "[ ] " <> title

defp empty_message("open"), do: "No open tasks"
defp empty_message("done"), do: "No completed tasks"
defp empty_message(_), do: "No tasks yet"
```

At this checkpoint, format and compile the application before adding more UI:

```bash
mix format
mix compile
```

## Add keybinding hints

The app already handles keys in `handle_event/3`, but users need a visible
reminder. We add local keybindings in `mount/2`:

```elixir
term
|> focus("new-task")
|> put_local_keybindings([
  {"Enter", "Add/toggle"},
  {"a", "New task"},
  {"c", "Clear done"}
])
|> assign(...)
```

Local keybindings describe actions that belong to this view. Breeze merges them
into `@breeze.keybindings`, which we can render with the built-in keybinding bar:

```heex
<box class="grid grid-cols-1 grid-rows-3 w-screen h-screen bg">
  ...

  <box class="h-1 w-full bg-panel overflow-hidden">
    <.keybinding_bar keybindings={@breeze.keybindings}/>
  </box>
</box>
```

The bar is only UI. The event handlers still decide what each key does.

## Use a built-in theme

Breeze ships with built-in themes. We start with one named theme:

```elixir
theme: Breeze.Theme.builtin(:gruvbox)
```

The template already uses semantic classes such as `bg`, `bg-panel`,
`text-primary`, and `text-muted`. Those tokens resolve through the active theme,
so changing the theme changes the app without rewriting the view.

Built-in theme names include `:system16`, `:system`, `:greenscreen`, `:nebula`,
`:catppuccin`, `:dracula`, `:commander`, `:gruvbox`, `:nord`,
`:solarized_light`, and `:solarized_dark`. To define a project-specific palette
later, we can use `Breeze.Theme`.

## Start the app

We update `lib/task_pad/application.ex` to start Breeze under the application
supervision tree:

```elixir
defmodule TaskPad.Application do
  use Application

  @impl true
  def start(_type, _args) do
    breeze_opts = [
      view: TaskPad.View,
      theme: Breeze.Theme.builtin(:gruvbox),
      mouse: true,
      global_keybindings: [
        {"F3", "Cycle theme", &Breeze.View.cycle_theme/2},
        {"F10", "Quit", fn _event, term -> {:stop, term} end}
      ]
    ]

    children =
      if start_server?() do
        [
          Supervisor.child_spec({Breeze.Server, breeze_opts},
            restart: :temporary,
            significant: true
          )
        ]
      else
        []
      end

    Supervisor.start_link(children,
      strategy: :one_for_one,
      auto_shutdown: :any_significant,
      name: TaskPad.Supervisor
    )
  end

  @impl true
  def stop(_state) do
    System.stop(0)
    :ok
  end

  defp start_server? do
    Application.get_env(:task_pad, :start_server, default_start_server?())
  end

  defp default_start_server? do
    if Code.ensure_loaded?(Mix) do
      Mix.env() != :test
    else
      true
    end
  end
end
```

`global_keybindings` are configured on `Breeze.Server`, not in the view. Breeze
checks them before normal focused view and component event routing, so they are a
good fit for application-level controls such as quitting or cycling themes. We
use `F10` for quitting so the command never competes with printable input.

The `restart: :temporary` child specification matters for an interactive
session: returning `{:stop, term}` ends that session normally, restores its
terminal, and leaves the application VM and sibling children running. A
permanent child would ask the supervisor to start the terminal session again.

A significant child is used to shutdown the beam when the child is stopped.
This may not be something we want in all environments, but is useful for 
local development.

The `start_server?/0` guard keeps the interactive server out of `mix test`,
where we use `Breeze.Test` to exercise the view directly.

We run the application with:

```bash
mix run --no-halt
```

Without `--no-halt`, Mix exits as soon as the run task completes. Breeze
restores the terminal during that exit, but the supervised application does
not remain running.

## Test it

`Breeze.Test` renders a view at a fixed terminal size and dispatches input
without launching an interactive terminal.

```elixir
defmodule TaskPad.ViewTest do
  use ExUnit.Case, async: true

  test "adds and completes a task" do
    session =
      Breeze.Test.start!(TaskPad.View,
        size: {80, 18},
        theme: Breeze.Theme.builtin(:gruvbox)
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert Breeze.Test.render_text!(session) =~ "Task Pad"

    for key <- String.graphemes("Write tests") do
      assert {:noreply, "new-task", true} = Breeze.Test.input(session, key)
    end

    assert {:noreply, "tasks", true} = Breeze.Test.input(session, "Enter")
    assert Breeze.Test.render_text!(session) =~ "Write tests"

    assert {:noreply, "tasks", true} = Breeze.Test.input(session, "Enter")
    assert Breeze.Test.render_text!(session) =~ "[x] Write tests"
  end
end
```

That gives us the basic Breeze loop: state in assigns, UI from `render/1`, events
through `handle_event/3`, built-in themes, and deterministic tests around the
terminal output.
