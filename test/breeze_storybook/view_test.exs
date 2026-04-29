defmodule Breeze.Storybook.ViewTest do
  use ExUnit.Case, async: true
  import Breeze.TestSupport.WaitUntil

  defmodule FakeAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(_opts), do: {:ok, %{ref: make_ref(), size: %{width: 80, height: 24}}}
    def reader(term), do: {:ok, term.ref}
    def write(term, _str), do: {:ok, term}
    def resize(term), do: term.size
  end

  defmodule RecordingAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(opts) do
      {:ok,
       %{
         ref: make_ref(),
         size: %{width: 80, height: 24},
         owner: Keyword.fetch!(opts, :owner)
       }}
    end

    def reader(term), do: {:ok, term.ref}

    def write(term, str) do
      send(term.owner, {:terminal_write, str})
      {:ok, term}
    end

    def resize(term), do: term.size
  end

  test "dropdown story renders a single visible closed indicator" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook.View, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/, box.content, "")
    lines = String.split(plain_content, "\n")

    assert Enum.any?(lines, &(String.contains?(&1, "POST") and String.contains?(&1, "▼")))
  end

  test "storybook can boot from a single story file" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} =
      Breeze.ChildServer.start(
        view: Breeze.Storybook.View,
        terminal: terminal,
        start_opts: [directory: "storybook", file: "dropdown.story.exs"]
      )

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    state = :sys.get_state(pid)

    assert Enum.map(state.assigns.stories, & &1.id) == ["dropdown"]
    assert state.assigns.current_story_id == "dropdown"
  end

  test "dropdown story does not duplicate the trigger row in the preview" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook.View, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")

    assert plain_content
           |> String.split("\n")
           |> Enum.count(&(String.contains?(&1, "POST") and String.contains?(&1, "▼"))) == 1
  end

  test "dropdown story keeps the selected value after choosing an item" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook.View, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")

    assert {:noreply, "storybook-preview::storybook-dropdown", true} =
             Breeze.ChildServer.set_focus(
               pid,
               "storybook-preview::storybook-dropdown"
             )

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "storybook-preview::storybook-dropdown", true} =
             Breeze.ChildServer.dispatch_input(pid, "Enter")

    assert {:noreply, "storybook-preview::storybook-dropdown", true} =
             Breeze.ChildServer.dispatch_input(pid, "ArrowDown")

    assert {:noreply, "storybook-preview::storybook-dropdown", true} =
             Breeze.ChildServer.dispatch_input(pid, "Enter")

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")

    assert plain_content
           |> String.split("\n")
           |> Enum.any?(&(String.contains?(&1, "PUT") and String.contains?(&1, "▼")))
  end

  test "input story cursor layout stays aligned with the rendered input row" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook.View, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    child = :sys.get_state(pid).children["storybook-preview"].pid

    assert {:noreply, "storybook-input-active", true} =
             Breeze.ChildServer.set_focus(child, "storybook-input-active")

    assert {:ok, _acc, box, decorations} =
             Breeze.ChildServer.render_snapshot(child, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")

    rendered_input_row =
      plain_content
      |> String.split("\n")
      |> Enum.find_index(&String.contains?(&1, "dev@example.com"))

    input_decoration = Enum.find(decorations, &(&1.id == "storybook-input-active"))

    assert rendered_input_row == input_decoration.layout.top
  end

  test "input story placeholder cursor layout stays aligned with the rendered placeholder row" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook.View, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    child = :sys.get_state(pid).children["storybook-preview"].pid

    assert {:noreply, "storybook-input-placeholder", true} =
             Breeze.ChildServer.set_focus(child, "storybook-input-placeholder")

    assert {:ok, _acc, box, decorations} =
             Breeze.ChildServer.render_snapshot(child, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")

    rendered_input_row =
      plain_content
      |> String.split("\n")
      |> Enum.find_index(&String.contains?(&1, "Email address"))

    input_decoration = Enum.find(decorations, &(&1.id == "storybook-input-placeholder"))

    assert rendered_input_row == input_decoration.layout.top
  end

  test "input story updates its value through delegated story events" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook.View, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "storybook-preview::storybook-input-active", true} =
             Breeze.ChildServer.set_focus(
               pid,
               "storybook-preview::storybook-input-active"
             )

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "storybook-preview::storybook-input-active", true} =
             Breeze.ChildServer.dispatch_input(pid, "!")

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "dev@example.com!"
  end

  test "modal story opens the real modal from its trigger" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook.View, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "storybook-preview::storybook-modal-trigger", true} =
             Breeze.ChildServer.set_focus(
               pid,
               "storybook-preview::storybook-modal-trigger"
             )

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "storybook-preview::storybook-modal-trigger", true} =
             Breeze.ChildServer.dispatch_input(pid, "Enter")

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")

    assert plain_content =~ "Confirm Action"
    assert plain_content =~ "Confirm Action"
    assert plain_content =~ "Escape closes it normally."
  end

  test "preview panel highlights when a focused element lives inside the preview child" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook.View, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "storybook-preview::storybook-button-primary", true} =
             Breeze.ChildServer.set_focus(
               pid,
               "storybook-preview::storybook-button-primary"
             )

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert box.content =~ ~r/\e\[[0-9;]*38;5;4m╭─/
    assert box.content =~ "Preview: Button"
  end

  test "storybook nav renders the selected marker and label without overlap" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook.View, terminal: terminal)

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")

    assert plain_content =~ ">Button"
  end

  test "F2 toggles the debug pane" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook.View, terminal: terminal)

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    refute plain_content =~ "Debug"

    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "F2")

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "Debug"
  end

  test "list story renders variant tabs below the description and switches variants" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook.View, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "Muted"
    assert plain_content =~ "Accent"
    assert plain_content =~ "variant=\"muted\""

    assert {:noreply, "storybook-variant-tabs", true} =
             Breeze.ChildServer.set_focus(pid, "storybook-variant-tabs")

    assert {:noreply, "storybook-variant-tabs", true} =
             Breeze.ChildServer.dispatch_input(pid, "ArrowRight")

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "Preview: List / Accent"
    assert plain_content =~ "variant=\"accent\""
  end

  test "list story variant tabs wrap left cleanly without collapsing to the trailing tab" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook.View, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "storybook-variant-tabs", true} =
             Breeze.ChildServer.set_focus(pid, "storybook-variant-tabs")

    assert {:noreply, "storybook-variant-tabs", true} =
             Breeze.ChildServer.dispatch_input(pid, "ArrowLeft")

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "Preview: List / Accent"
    assert plain_content =~ " Muted  Accent "
  end

  test "Ctrl+Up and Ctrl+Down navigate stories regardless of current focus" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook.View, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "storybook-preview::storybook-button-primary", true} =
             Breeze.ChildServer.set_focus(pid, "storybook-preview::storybook-button-primary")

    assert {:noreply, "storybook-nav", true} =
             Breeze.ChildServer.dispatch_input(pid, %{"ctrlKey" => true, "key" => "ArrowDown"})

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "Preview: Dropdown"

    assert {:noreply, "storybook-nav", true} =
             Breeze.ChildServer.dispatch_input(pid, %{"ctrlKey" => true, "key" => "ArrowUp"})

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "Preview: Button"
  end

  test "Ctrl+H/L and Ctrl+Left/Right navigate variants regardless of current focus" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook.View, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "storybook-preview::storybook-list-muted", true} =
             Breeze.ChildServer.set_focus(pid, "storybook-preview::storybook-list-muted")

    assert {:noreply, "storybook-variant-tabs", true} =
             Breeze.ChildServer.dispatch_input(pid, %{"ctrlKey" => true, "key" => "ArrowRight"})

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "Preview: List / Accent"

    assert {:noreply, "storybook-variant-tabs", true} =
             Breeze.ChildServer.dispatch_input(pid, %{"ctrlKey" => true, "key" => "h"})

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "Preview: List / Muted"

    assert {:noreply, "storybook-variant-tabs", true} =
             Breeze.ChildServer.dispatch_input(pid, %{"ctrlKey" => true, "key" => "l"})

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "Preview: List / Accent"

    assert {:noreply, "storybook-variant-tabs", true} =
             Breeze.ChildServer.dispatch_input(pid, %{"ctrlKey" => true, "key" => "ArrowLeft"})

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "Preview: List / Muted"
  end

  test "ctrl-arrow story navigation does not duplicate the input cursor overlay" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Breeze.Storybook.View,
        terminal: terminal,
        reader: reader
      )

    view_pid = :sys.get_state(pid).view_pid

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(view_pid, terminal: terminal)

    assert {:noreply, "storybook-nav", true} =
             Breeze.ChildServer.dispatch_input(view_pid, "ArrowDown")

    assert {:noreply, "storybook-nav", true} =
             Breeze.ChildServer.dispatch_input(view_pid, "ArrowDown")

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(view_pid, terminal: terminal)

    assert {:noreply, "storybook-preview::storybook-input-active", true} =
             Breeze.ChildServer.set_focus(view_pid, "storybook-preview::storybook-input-active")

    send(pid, {:child_invalidated, "storybook-preview"})

    wait_until(fn ->
      length(:sys.get_state(pid).last_overlays) == 1
    end)

    assert {:noreply, "storybook-nav", true} =
             Breeze.ChildServer.dispatch_input(view_pid, %{
               "ctrlKey" => true,
               "key" => "ArrowDown"
             })

    wait_until(fn ->
      :sys.get_state(pid).focused == "storybook-nav" and
        :sys.get_state(pid).last_overlays == []
    end)
  end

  test "preview panel highlights for the dropdown story when the dropdown is focused" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook.View, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "storybook-preview::storybook-dropdown", true} =
             Breeze.ChildServer.set_focus(
               pid,
               "storybook-preview::storybook-dropdown"
             )

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert box.content =~ ~r/\e\[[0-9;]*38;5;4m╭─/
    assert box.content =~ "Preview: Dropdown"
  end

  test "preview panel highlights for the scroll story when the scroll region is focused" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook.View, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "storybook-preview::storybook-scroll", true} =
             Breeze.ChildServer.set_focus(
               pid,
               "storybook-preview::storybook-scroll"
             )

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert box.content =~ ~r/\e\[[0-9;]*38;5;4m╭─/
    assert box.content =~ "Preview: Scroll"
  end

  test "storybook preview child patches clear the full viewport height when the dropdown collapses" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Breeze.Storybook.View,
        terminal: terminal
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

    view_pid = :sys.get_state(pid).view_pid
    reader = terminal.reader

    assert {:noreply, "storybook-nav", true} =
             Breeze.ChildServer.dispatch_event(view_pid, "select_story", %{value: "dropdown"})

    wait_until(fn ->
      :sys.get_state(view_pid).assigns.current_story_id == "dropdown"
    end)

    wait_until(fn ->
      Map.has_key?(:sys.get_state(pid).children, "storybook-preview")
    end)

    preview_pid = :sys.get_state(pid).children["storybook-preview"].pid
    viewport = :sys.get_state(pid).rendered_elements["storybook-preview"]

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(preview_pid, terminal: terminal)

    drain_terminal_writes()

    assert {:noreply, "storybook-preview::storybook-dropdown", true} =
             Breeze.ChildServer.set_focus(view_pid, "storybook-preview::storybook-dropdown")

    send(pid, {reader, {:data, "\r"}})
    _writes = await_terminal_writes()

    send(pid, {reader, {:data, "\r"}})

    writes =
      wait_until(fn ->
        writes = drain_terminal_writes()
        if writes == [], do: false, else: writes
      end)

    assert redraw_or_full_viewport_patch?(writes, viewport)
    assert Enum.any?(writes, &String.contains?(&1, "\e[48;5;0m"))
  end

  test "storybook preview child patches clear the full viewport height when preview tabs switch" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Breeze.Storybook.View,
        terminal: terminal
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

    view_pid = :sys.get_state(pid).view_pid

    assert {:noreply, "storybook-nav", true} =
             Breeze.ChildServer.dispatch_event(view_pid, "select_story", %{value: "tabs"})

    wait_until(fn ->
      :sys.get_state(view_pid).assigns.current_story_id == "tabs"
    end)

    wait_until(
      fn ->
        Map.has_key?(:sys.get_state(pid).children, "storybook-preview")
      end,
      100
    )

    preview_pid = :sys.get_state(pid).children["storybook-preview"].pid
    viewport = :sys.get_state(pid).rendered_elements["storybook-preview"]

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(preview_pid, terminal: terminal)

    assert {:noreply, "storybook-tabs", _} =
             Breeze.ChildServer.set_focus(preview_pid, "storybook-tabs")

    drain_terminal_writes()

    assert {:noreply, "storybook-tabs", true} =
             Breeze.ChildServer.dispatch_input(preview_pid, "ArrowRight")

    writes =
      wait_until(fn ->
        writes = drain_terminal_writes()
        if writes == [], do: false, else: writes
      end)

    assert patched_rows(writes, viewport.left + 1) ==
             Enum.to_list((viewport.top + 1)..(viewport.top + viewport.height))
  end

  test "storybook preview child patches clear the full viewport height when the list selection changes" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Breeze.Storybook.View,
        terminal: terminal
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

    view_pid = :sys.get_state(pid).view_pid

    assert {:noreply, "storybook-nav", true} =
             Breeze.ChildServer.dispatch_event(view_pid, "select_story", %{value: "list"})

    wait_until(fn ->
      :sys.get_state(view_pid).assigns.current_story_id == "list"
    end)

    wait_until(fn ->
      Map.has_key?(:sys.get_state(pid).children, "storybook-preview")
    end)

    preview_pid = :sys.get_state(pid).children["storybook-preview"].pid
    viewport = :sys.get_state(pid).rendered_elements["storybook-preview"]

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(preview_pid, terminal: terminal)

    assert {:noreply, "storybook-list-muted", _} =
             Breeze.ChildServer.set_focus(preview_pid, "storybook-list-muted")

    drain_terminal_writes()

    assert {:noreply, "storybook-list-muted", true} =
             Breeze.ChildServer.dispatch_input(preview_pid, "ArrowDown")

    writes =
      wait_until(fn ->
        writes = drain_terminal_writes()
        if writes == [], do: false, else: writes
      end)

    assert redraw_or_full_viewport_patch?(writes, viewport)
  end

  test "storybook preview child patches clear the full viewport height when the scroll position changes" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Breeze.Storybook.View,
        terminal: terminal
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

    view_pid = :sys.get_state(pid).view_pid

    assert {:noreply, "storybook-nav", true} =
             Breeze.ChildServer.dispatch_event(view_pid, "select_story", %{value: "scroll"})

    wait_until(fn ->
      :sys.get_state(view_pid).assigns.current_story_id == "scroll"
    end)

    wait_until(fn ->
      Map.has_key?(:sys.get_state(pid).children, "storybook-preview")
    end)

    preview_pid = :sys.get_state(pid).children["storybook-preview"].pid
    viewport = :sys.get_state(pid).rendered_elements["storybook-preview"]

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(preview_pid, terminal: terminal)

    assert {:noreply, "storybook-scroll", _} =
             Breeze.ChildServer.set_focus(preview_pid, "storybook-scroll")

    drain_terminal_writes()

    assert {:noreply, "storybook-scroll", true} =
             Breeze.ChildServer.dispatch_input(preview_pid, "ArrowDown")

    writes =
      wait_until(fn ->
        writes = drain_terminal_writes()
        if writes == [], do: false, else: writes
      end)

    assert redraw_or_full_viewport_patch?(writes, viewport)
  end

  test "tabbing out of a focused story preview control patches the preview instead of redrawing the frame" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Breeze.Storybook.View,
        terminal: terminal
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

    view_pid = :sys.get_state(pid).view_pid

    assert {:noreply, "storybook-nav", true} =
             Breeze.ChildServer.dispatch_event(view_pid, "select_story", %{value: "tabs"})

    wait_until(fn ->
      :sys.get_state(view_pid).assigns.current_story_id == "tabs"
    end)

    wait_until(fn ->
      Map.has_key?(:sys.get_state(pid).children, "storybook-preview")
    end)

    preview_pid = :sys.get_state(pid).children["storybook-preview"].pid
    viewport = :sys.get_state(pid).rendered_elements["storybook-preview"]
    reader = terminal.reader

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(preview_pid, terminal: terminal)

    assert {:noreply, "storybook-tabs", _} =
             Breeze.ChildServer.set_focus(preview_pid, "storybook-tabs")

    drain_terminal_writes()

    assert {:noreply, "storybook-tabs", true} =
             Breeze.ChildServer.dispatch_input(preview_pid, "ArrowRight")

    await_terminal_writes()
    drain_terminal_writes()

    send(pid, {reader, {:data, "\t"}})

    writes =
      wait_until(fn ->
        writes = drain_terminal_writes()
        if writes == [], do: false, else: writes
      end)

    refute Enum.any?(writes, &String.contains?(&1, "\e[2J\e[H"))

    assert patched_rows(writes, viewport.left + 1) ==
             Enum.to_list((viewport.top + 1)..(viewport.top + viewport.height))
  end

  defp drain_terminal_writes(writes \\ []) do
    receive do
      {:terminal_write, str} -> drain_terminal_writes([str | writes])
    after
      10 -> Enum.reverse(writes)
    end
  end

  defp patched_rows(writes, column) do
    pattern = ~r/\e\[(\d+);#{column}H/

    writes
    |> IO.iodata_to_binary()
    |> then(&Regex.scan(pattern, &1, capture: :all_but_first))
    |> Enum.map(fn [row] -> String.to_integer(row) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp redraw_or_full_viewport_patch?(writes, viewport) do
    payload = IO.iodata_to_binary(writes)

    String.contains?(payload, "\e[2J\e[H") or
      patched_rows(writes, viewport.left + 1) ==
        Enum.to_list((viewport.top + 1)..(viewport.top + viewport.height))
  end

  defp await_terminal_writes(acc \\ []) do
    receive do
      {:terminal_write, str} -> drain_terminal_writes([str | acc])
    after
      200 -> flunk("expected terminal writes")
    end
  end
end
