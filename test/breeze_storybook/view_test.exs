defmodule Breeze.Storybook.RenderingTest do
  use Breeze.TestSupport.StorybookCase, async: true

  test "dropdown story renders a single visible closed indicator" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook, terminal: terminal)

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
        view: Breeze.Storybook,
        terminal: terminal,
        start_opts: [directory: "storybook", file: "dropdown.story.exs"]
      )

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    state = :sys.get_state(pid)

    assert Enum.map(state.assigns.stories, & &1.id) == ["dropdown"]
    assert state.assigns.current_story_id == "dropdown"
  end

  test "story details wrap long sources and notes to the panel width" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 40}}

    {:ok, pid} =
      Breeze.ChildServer.start(
        view: Breeze.Storybook,
        terminal: terminal,
        start_opts: [directory: "storybook", file: "tabs.story.exs"]
      )

    assert {:ok, acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert Map.fetch!(acc.boxes, "storybook-detail-source").height > 1
    assert Map.fetch!(acc.boxes, "storybook-detail-note-0").height > 1
    assert Map.fetch!(acc.boxes, "storybook-detail-note-1").height > 1

    lines = box.content |> then(&Regex.replace(~r/\e\[[0-9;]*m/u, &1, "")) |> String.split("\n")
    source_label_row = Enum.find_index(lines, &String.contains?(&1, "Source:"))
    source_content_row = Enum.find_index(lines, &String.contains?(&1, "<.tabs"))

    assert source_content_row == source_label_row + 1
  end

  test "dropdown story does not duplicate the trigger row in the preview" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook, terminal: terminal)

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
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook, terminal: terminal)

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
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    select_story!(pid, "input")
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
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    select_story!(pid, "input")
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
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    select_story!(pid, "input")
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

  test "textarea story placeholder cursor layout stays aligned with the rendered placeholder row" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} =
      Breeze.ChildServer.start(
        view: Breeze.Storybook,
        terminal: terminal,
        start_opts: [directory: "storybook", file: "textarea.story.exs"]
      )

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    child = :sys.get_state(pid).children["storybook-preview"].pid

    assert {:noreply, "storybook-textarea-placeholder", true} =
             Breeze.ChildServer.set_focus(child, "storybook-textarea-placeholder")

    assert {:ok, _acc, box, decorations} =
             Breeze.ChildServer.render_snapshot(child, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")

    rendered_row =
      plain_content
      |> String.split("\n")
      |> Enum.find_index(&String.contains?(&1, "Ask anything"))

    textarea_decoration = Enum.find(decorations, &(&1.id == "storybook-textarea-placeholder"))

    assert rendered_row == textarea_decoration.layout.top + 1
  end

  test "textarea story grows after inserting a newline" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} =
      Breeze.ChildServer.start(
        view: Breeze.Storybook,
        terminal: terminal,
        start_opts: [directory: "storybook", file: "textarea.story.exs"]
      )

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "storybook-preview::storybook-textarea-active", true} =
             Breeze.ChildServer.set_focus(pid, "storybook-preview::storybook-textarea-active")

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    child = :sys.get_state(pid).children["storybook-preview"].pid

    initial_height =
      child
      |> :sys.get_state()
      |> Map.get(:assigns)
      |> Map.get(:message)
      |> String.split("\n", trim: false)
      |> length()

    assert {:noreply, "storybook-preview::storybook-textarea-active", true} =
             Breeze.ChildServer.dispatch_input(pid, "Enter")

    assert {:noreply, "storybook-preview::storybook-textarea-active", true} =
             Breeze.ChildServer.dispatch_input(pid, "N")

    updated_child_state = :sys.get_state(child)

    updated_height =
      updated_child_state.assigns.message |> String.split("\n", trim: false) |> length()

    assert updated_height == initial_height + 1
    assert updated_child_state.assigns.message =~ "\nN"

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "Keep migration notes short."
    assert plain_content =~ "N"
  end

  test "modal story opens the real modal from its trigger" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    select_story!(pid, "modal")
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
end

defmodule Breeze.Storybook.LayoutTest do
  use Breeze.TestSupport.StorybookCase, async: true

  test "preview panel highlights when a focused element lives inside the preview child" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook, terminal: terminal)

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
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")

    assert plain_content =~ ">Button"
  end

  test "F2 toggles the debug pane" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    refute plain_content =~ "Debug"

    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "F2")

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "Debug"
  end

  test "F3 cycles the storybook theme" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} =
      Breeze.ChildServer.start(
        view: Breeze.Storybook,
        terminal: terminal,
        theme: Breeze.Theme.builtin(:gruvbox)
      )

    assert Breeze.ChildServer.metadata(pid).theme.name == "gruvbox-dark"
    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    child = :sys.get_state(pid).children["storybook-preview"].pid
    assert Breeze.ChildServer.metadata(child).theme.name == "gruvbox-dark"

    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "F3")

    metadata = Breeze.ChildServer.metadata(pid)
    assert metadata.theme.name == "nord"
    assert metadata.assigns.breeze.theme.name == :nord

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert Breeze.ChildServer.metadata(child).theme.name == "nord"
  end

  test "F3 cycles the storybook theme while focus is inside the preview" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} =
      Breeze.ChildServer.start(
        view: Breeze.Storybook,
        terminal: terminal,
        theme: Breeze.Theme.builtin(:gruvbox)
      )

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "storybook-preview::storybook-button-primary", true} =
             Breeze.ChildServer.set_focus(pid, "storybook-preview::storybook-button-primary")

    assert {:noreply, "storybook-preview::storybook-button-primary", true} =
             Breeze.ChildServer.dispatch_input(pid, "F3")

    assert Breeze.ChildServer.metadata(pid).theme.name == "nord"
  end

  test "server lets storybook F3 run before focused preview live child input" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Breeze.Storybook,
        terminal: terminal,
        theme: Breeze.Theme.builtin(:gruvbox)
      )

    on_exit(fn -> stop_server(pid) end)

    view_pid = :sys.get_state(pid).view_pid

    wait_until(fn ->
      Map.has_key?(:sys.get_state(pid).children, "storybook-preview")
    end)

    assert {:noreply, "storybook-preview::storybook-button-primary", true} =
             Breeze.ChildServer.set_focus(view_pid, "storybook-preview::storybook-button-primary")

    send(pid, :child_invalidated)

    wait_until(fn ->
      :sys.get_state(pid).focused == "storybook-preview::storybook-button-primary"
    end)

    send(pid, {terminal.reader, {:data, "\e[13~"}})

    wait_until(fn ->
      Breeze.ChildServer.metadata(view_pid).theme.name == "nord"
    end)
  end

  test "list story renders variant tabs below the description and switches variants" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    select_story!(pid, "list")
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
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    select_story!(pid, "list")
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

  test "list story mouse wheel scrolls the preview list without changing selection" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    select_story!(pid, "list")
    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    child = :sys.get_state(pid).children["storybook-preview"].pid

    {Breeze.Implicit.List, before_list} =
      :sys.get_state(child).implicit_state["storybook-list-muted"]

    preview_bounds = Breeze.ChildServer.layout_snapshot(pid).mouse_targets["storybook-preview"]

    assert {:noreply, "storybook-nav", true} =
             Breeze.ChildServer.dispatch_input(pid, %{
               "mouse" => %{
                 button: :wheel_down,
                 action: :press,
                 x: preview_bounds.left + div(preview_bounds.width, 2) + 1,
                 y: preview_bounds.top + 3,
                 modifiers: []
               }
             })

    {Breeze.Implicit.List, after_list} =
      :sys.get_state(child).implicit_state["storybook-list-muted"]

    {Breeze.Implicit.List, nav} = :sys.get_state(pid).implicit_state["storybook-nav"]

    assert after_list.offset == before_list.offset + 1
    assert after_list.selected == before_list.selected
    assert after_list.selected_index == before_list.selected_index
    assert nav.selected == "list"
    assert :sys.get_state(pid).assigns.current_story_id == "list"
    assert Breeze.ChildServer.metadata(pid).focused == "storybook-nav"
  end

  test "table story mouse wheel scrolls the preview table without changing selection" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    select_story!(pid, "table")
    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    child = :sys.get_state(pid).children["storybook-preview"].pid
    {Breeze.Implicit.List, before_table} = :sys.get_state(child).implicit_state["storybook-table"]
    preview_bounds = Breeze.ChildServer.layout_snapshot(pid).mouse_targets["storybook-preview"]

    assert {:noreply, "storybook-nav", true} =
             Breeze.ChildServer.dispatch_input(pid, %{
               "mouse" => %{
                 button: :wheel_down,
                 action: :press,
                 x: preview_bounds.left + div(preview_bounds.width, 2) + 1,
                 y: preview_bounds.top + 4,
                 modifiers: []
               }
             })

    {Breeze.Implicit.List, after_table} = :sys.get_state(child).implicit_state["storybook-table"]

    assert after_table.offset == before_table.offset + 1
    assert after_table.selected == before_table.selected
    assert after_table.selected_index == before_table.selected_index
    assert :sys.get_state(child).assigns.selected_city == "delhi"
    assert :sys.get_state(pid).assigns.current_story_id == "table"
  end
end

defmodule Breeze.Storybook.NavigationTest do
  use Breeze.TestSupport.StorybookCase, async: true

  test "Ctrl+Up and Ctrl+Down navigate stories regardless of current focus" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook, terminal: terminal)

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
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    select_story!(pid, "list")
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
        view: Breeze.Storybook,
        terminal: terminal,
        reader: reader
      )

    view_pid = :sys.get_state(pid).view_pid

    on_exit(fn -> stop_server(pid) end)

    wait_until(fn ->
      :sys.get_state(view_pid).assigns.current_story_id == "button"
    end)

    send(pid, {reader, {:data, "\e[B"}})

    wait_until(fn ->
      :sys.get_state(view_pid).assigns.current_story_id == "dropdown"
    end)

    send(pid, {reader, {:data, "\e[B"}})

    wait_until(fn ->
      :sys.get_state(view_pid).assigns.current_story_id == "flash"
    end)

    send(pid, {reader, {:data, "\e[B"}})

    wait_until(fn ->
      :sys.get_state(view_pid).assigns.current_story_id == "input"
    end)

    send(pid, {reader, {:data, "\t"}})

    wait_until(
      fn ->
        state = :sys.get_state(pid)

        state.focused == "storybook-preview::storybook-input-active" and
          length(state.frame.last_overlays) == 1
      end,
      100
    )

    send(pid, {reader, {:data, "\e[1;5B"}})

    wait_until(
      fn ->
        state = :sys.get_state(pid)

        state.focused == "storybook-nav" and
          :sys.get_state(view_pid).assigns.current_story_id == "list" and
          state.frame.last_overlays == []
      end,
      100
    )
  end

  test "preview panel highlights for the dropdown story when the dropdown is focused" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook, terminal: terminal)

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
    {:ok, pid} = Breeze.ChildServer.start(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    select_story!(pid, "scroll")
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

defmodule Breeze.Storybook.ServerRenderingTest do
  use Breeze.TestSupport.StorybookCase, async: true

  test "storybook preview child patches clear the full viewport height when the dropdown collapses" do
    {terminal, pid} = start_storybook_server!("dropdown.story.exs")
    view_pid = :sys.get_state(pid).view_pid
    reader = terminal.reader

    {preview_pid, viewport} = wait_for_preview_child(pid, "dropdown")

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
    {terminal, pid} = start_storybook_server!("tabs.story.exs")

    {preview_pid, viewport} = wait_for_preview_child(pid, "tabs")

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

  test "storybook server routes mouse clicks to tabs inside the preview" do
    {terminal, pid} = start_storybook_server!("tabs.story.exs", mouse: true)
    reader = terminal.reader

    {preview_pid, viewport} = wait_for_preview_child(pid, "tabs")

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(preview_pid, terminal: terminal)
    assert :sys.get_state(preview_pid).assigns.selected_tab == "headers"

    body =
      Breeze.ChildServer.layout_snapshot(preview_pid).mouse_targets["storybook-tabs-tab-body"]

    send_mouse(pid, reader, 0, viewport.left + body.left + 1, viewport.top + body.top + 1)

    wait_until(fn ->
      :sys.get_state(preview_pid).assigns.selected_tab == "body"
    end)

    assert :sys.get_state(pid).focused == "storybook-preview::storybook-tabs"
  end

  test "storybook server routes mouse wheel to scrollable preview stories" do
    for {file, story_id, implicit_id, state_key} <- [
          {"list.story.exs", "list", "storybook-list-muted", :offset},
          {"scroll.story.exs", "scroll", "storybook-scroll", :offset_y},
          {"table.story.exs", "table", "storybook-table", :offset}
        ] do
      {terminal, pid} = start_storybook_server!(file, mouse: true)
      reader = terminal.reader

      {preview_pid, viewport} = wait_for_preview_child(pid, story_id)

      assert {:ok, _acc, _box} = Breeze.ChildServer.render(preview_pid, terminal: terminal)

      {_, before_state} = :sys.get_state(preview_pid).implicit_state[implicit_id]
      target = Breeze.ChildServer.layout_snapshot(preview_pid).mouse_targets[implicit_id]

      send_mouse(
        pid,
        reader,
        65,
        viewport.left + min(target.left + 2, target.right) + 1,
        viewport.top + min(target.top + 1, target.bottom) + 1
      )

      wait_until(fn ->
        {_, after_state} = :sys.get_state(preview_pid).implicit_state[implicit_id]
        Map.fetch!(after_state, state_key) > Map.fetch!(before_state, state_key)
      end)
    end
  end

  test "storybook preview child patches clear the full viewport height when the list selection changes" do
    {terminal, pid} = start_storybook_server!("list.story.exs")

    {preview_pid, viewport} = wait_for_preview_child(pid, "list")

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
    {terminal, pid} = start_storybook_server!("scroll.story.exs")

    {preview_pid, viewport} = wait_for_preview_child(pid, "scroll")

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
    {terminal, pid} = start_storybook_server!("tabs.story.exs")

    {preview_pid, viewport} = wait_for_preview_child(pid, "tabs")
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
end
