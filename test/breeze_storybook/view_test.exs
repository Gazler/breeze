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
end
