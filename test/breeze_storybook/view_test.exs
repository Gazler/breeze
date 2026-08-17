defmodule Breeze.Storybook.RenderingTest do
  use Breeze.TestSupport.StorybookCase, async: true

  test "renders stories for the keybinding bar, Markdown, and tree blocks" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    for {file, expected_content} <- [
          {"keybinding_bar.story.exs", ["Active keybindings", "Enter Select", "d Details"]},
          {"markdown.story.exs", ["# Release Notes", "formatted text", "inline code"]},
          {"tree.story.exs", ["breeze", "lib", "blocks.ex"]}
        ] do
      {:ok, pid} =
        start_child_server(
          view: Breeze.Storybook,
          terminal: terminal,
          start_opts: [directory: "storybook", file: file]
        )

      assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
      plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")

      for content <- expected_content do
        assert plain_content =~ content
      end
    end
  end

  test "button story shows the latest keyboard and mouse press" do
    terminal = %Termite.Terminal{size: %{width: 44, height: 10}}

    {:ok, pid} =
      start_child_server(
        view: Breeze.Storybook.Stories.Blocks.ButtonStory,
        terminal: terminal
      )

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert BackBreeze.Utils.strip_escape_chars(box.content) =~ "Latest press: None"

    assert {:noreply, "storybook-button-primary", _changed?} =
             Breeze.ChildServer.set_focus(pid, "storybook-button-primary")

    assert {:noreply, "storybook-button-primary", true} =
             Breeze.ChildServer.dispatch_input(pid, "Enter")

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert BackBreeze.Utils.strip_escape_chars(box.content) =~ "Latest press: Confirm"

    bounds = :sys.get_state(pid).mouse_targets["storybook-button-cancel"]

    mouse = %{
      "mouse" => %{
        "button" => "left",
        "x" => div(bounds.left + bounds.right, 2),
        "y" => div(bounds.top + bounds.bottom, 2)
      }
    }

    assert {:noreply, "storybook-button-cancel", true} =
             Breeze.ChildServer.dispatch_input(pid, put_in(mouse, ["mouse", "action"], "press"))

    assert %{assigns: %{latest_press: "Confirm"}} = Breeze.ChildServer.metadata(pid)

    assert {:noreply, "storybook-button-cancel", true} =
             Breeze.ChildServer.dispatch_input(
               pid,
               put_in(mouse, ["mouse", "action"], "release")
             )

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert BackBreeze.Utils.strip_escape_chars(box.content) =~ "Latest press: Cancel"
  end

  test "button story switches between default and bordered variants" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} =
      start_child_server(
        view: Breeze.Storybook,
        terminal: terminal,
        start_opts: [directory: "storybook", file: "button.story.exs"]
      )

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    plain_content = BackBreeze.Utils.strip_escape_chars(box.content)

    assert plain_content =~ "Preview: Button / Default"
    assert plain_content =~ " Default  Bordered "
    assert plain_content =~ ~s|<.button id="confirm" class="w-12">Confirm|

    assert {:noreply, "storybook-nav", true} =
             Breeze.ChildServer.dispatch_event(pid, "select_variant", %{value: "bordered"})

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    plain_content = BackBreeze.Utils.strip_escape_chars(box.content)

    assert plain_content =~ "Preview: Button / Bordered"
    assert plain_content =~ ~s|variant="bordered"|
  end

  test "bordered button story adds colored focus edges across the bottom border" do
    terminal = %Termite.Terminal{size: %{width: 44, height: 10}}
    theme = Breeze.Theme.builtin(:nebula)

    {:ok, pid} =
      start_child_server(
        view: Breeze.Storybook.Stories.Blocks.ButtonStory,
        terminal: terminal,
        theme: theme,
        assigns: %{__breeze_story_variant__: "bordered"}
      )

    assert {:ok, _acc, box} =
             Breeze.ChildServer.render(pid, terminal: terminal, focused: "not-focused")

    assert BackBreeze.Utils.strip_escape_chars(box.content) =~ "Confirm"
    refute BackBreeze.Utils.strip_escape_chars(box.content) =~ "▀"

    primary_code = theme |> Breeze.Theme.color(:primary) |> Tuple.to_list() |> Enum.join(";")
    error_code = theme |> Breeze.Theme.color(:error) |> Tuple.to_list() |> Enum.join(";")
    panel_code = theme |> Breeze.Theme.color(:panel) |> Tuple.to_list() |> Enum.join(";")

    confirm = :sys.get_state(pid).rendered_boxes["storybook-button-primary"]
    unfocused_delete = :sys.get_state(pid).rendered_boxes["storybook-button-delete"]

    assert confirm.style.width == 12
    assert unfocused_delete.style.background_color == Breeze.Theme.color(theme, :panel)

    assert {:ok, _acc, focused_confirm_box} =
             Breeze.ChildServer.render(pid,
               terminal: terminal,
               focused: "storybook-button-primary"
             )

    focused_confirm_content = BackBreeze.Utils.strip_escape_chars(focused_confirm_box.content)

    assert focused_confirm_content =~ "╰▀▀▀▀▀▀▀▀▀▀╯"

    assert focused_confirm_box.content =~
             ~r/48;2;#{panel_code}[^m]*38;2;#{primary_code}m╰▀/u

    refute focused_confirm_box.content =~ ~r/\e\[[0-9;]*7;[0-9;]*mConfirm/u

    assert {:ok, _acc, focused_box} =
             Breeze.ChildServer.render(pid,
               terminal: terminal,
               focused: "storybook-button-delete"
             )

    focused_delete = :sys.get_state(pid).rendered_boxes["storybook-button-delete"]

    assert focused_delete.style.background_color == unfocused_delete.style.background_color
    assert focused_delete.style.border_color == Breeze.Theme.color(theme, :error)

    focused_delete_content = BackBreeze.Utils.strip_escape_chars(focused_box.content)

    assert focused_delete_content =~ "╰▀▀▀▀▀▀▀▀▀▀╯"

    assert focused_box.content =~
             ~r/48;2;#{panel_code}[^m]*38;2;#{error_code}m╰▀/u

    refute focused_box.content =~ ~r/\e\[[0-9;]*7;[0-9;]*mDelete/u
  end

  test "spinner story renders its idle state and animation decoration" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} =
      start_child_server(
        view: Breeze.Storybook,
        terminal: terminal,
        start_opts: [directory: "storybook", file: "spinner.story.exs"]
      )

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")

    assert plain_content =~ "Asynchronous task animation"
    assert plain_content =~ "Completed runs: 0"

    preview_pid = :sys.get_state(pid).children["storybook-preview"].pid

    assert {:ok, _acc, _box,
            [
              %{
                id: "storybook-spinner",
                every_ms: 80,
                active_when_pending: true,
                box: spinner_box
              }
            ]} =
             Breeze.ChildServer.render_snapshot(preview_pid, terminal: terminal)

    panel_background =
      preview_pid
      |> Breeze.ChildServer.metadata()
      |> Map.fetch!(:theme)
      |> Breeze.Theme.color(:panel)

    assert spinner_box.style.background_color == panel_background

    assert {:noreply, "storybook-nav", true} =
             Breeze.ChildServer.dispatch_event(pid, "select_variant", %{value: "bars"})

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert BackBreeze.Utils.strip_escape_chars(box.content) =~
             "Preview: Spinner / Bars"

    preview_pid = :sys.get_state(pid).children["storybook-preview"].pid

    assert {:ok, _acc, _box,
            [%{id: "storybook-spinner", every_ms: 120, active_when_pending: true}]} =
             Breeze.ChildServer.render_snapshot(preview_pid, terminal: terminal)
  end

  test "spinner story runs work outside the event callback" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    test_pid = self()

    task_fun = fn ->
      send(test_pid, {:spinner_task_started, self()})

      receive do
        :finish_spinner_task -> :ok
      after
        100 -> :ok
      end
    end

    {:ok, pid} =
      start_child_server(
        view: Breeze.Storybook.Stories.Blocks.SpinnerStory,
        terminal: terminal,
        start_opts: [task_fun: task_fun]
      )

    assert {:noreply, "storybook-spinner-run", true} =
             Breeze.ChildServer.dispatch_input(pid, "Enter")

    assert_receive {:spinner_task_started, task_pid}

    assert %{assigns: %{running?: true, completed_runs: 0}} =
             Breeze.ChildServer.metadata(pid)

    assert {:ok, _acc, _box, [%{id: "storybook-spinner", active_when_pending: false}]} =
             Breeze.ChildServer.render_snapshot(pid, terminal: terminal)

    send(task_pid, :finish_spinner_task)

    assert :ok =
             wait_until(
               fn ->
                 match?(
                   %{assigns: %{running?: false, completed_runs: 1}},
                   Breeze.ChildServer.metadata(pid)
                 )
               end,
               500
             )

    assert {:ok, _acc, _box, [%{id: "storybook-spinner", active_when_pending: true}]} =
             Breeze.ChildServer.render_snapshot(pid, terminal: terminal)
  end

  test "table story renders its complete Population header" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} =
      start_child_server(
        view: Breeze.Storybook,
        terminal: terminal,
        start_opts: [directory: "storybook", file: "table.story.exs"]
      )

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "") =~ "Population"
  end

  test "table story stretches unbounded data columns with the available width" do
    view = Breeze.Storybook.Stories.Blocks.TableStory
    narrow_terminal = %Termite.Terminal{size: %{width: 44, height: 12}}
    wide_terminal = %Termite.Terminal{size: %{width: 64, height: 12}}

    {:ok, pid} = start_child_server(view: view, terminal: narrow_terminal)

    assert {:ok, _acc, narrow_box} = Breeze.ChildServer.render(pid, terminal: narrow_terminal)
    assert {:ok, _acc, wide_box} = Breeze.ChildServer.render(pid, terminal: wide_terminal)

    population_column = fn box ->
      box.content
      |> BackBreeze.Utils.strip_escape_chars()
      |> String.split("\n")
      |> Enum.find(&String.contains?(&1, "Population"))
      |> String.split("Population", parts: 2)
      |> hd()
      |> BackBreeze.Utils.string_length()
    end

    assert population_column.(wide_box) > population_column.(narrow_box)
  end

  test "tree story keeps selection in story-local state" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} =
      start_child_server(
        view: Breeze.Storybook,
        terminal: terminal,
        start_opts: [directory: "storybook", file: "tree.story.exs"]
      )

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "storybook-preview::storybook-tree", true} =
             Breeze.ChildServer.set_focus(pid, "storybook-preview::storybook-tree")

    assert {:noreply, "storybook-preview::storybook-tree", true} =
             Breeze.ChildServer.dispatch_input(pid, "ArrowDown")

    child = :sys.get_state(pid).children["storybook-preview"].pid
    assert :sys.get_state(child).assigns.selected == "lib"
  end

  test "checkbox story renders checked, unchecked, and disabled controls" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} =
      start_child_server(
        view: Breeze.Storybook,
        terminal: terminal,
        start_opts: [directory: "storybook", file: "checkbox.story.exs"]
      )

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")

    assert plain_content =~ "[x] Mouse input"
    assert plain_content =~ "[ ] Inspector"
    assert plain_content =~ "⟦x⟧ Unavailable"
  end

  test "dropdown story renders a single visible closed indicator" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    select_story!(pid, "dropdown")

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/, box.content, "")
    lines = String.split(plain_content, "\n")

    assert Enum.any?(lines, &(String.contains?(&1, "POST") and String.contains?(&1, "▼")))
  end

  test "storybook can boot from a single story file" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} =
      start_child_server(
        view: Breeze.Storybook,
        terminal: terminal,
        start_opts: [directory: "storybook", file: "dropdown.story.exs"]
      )

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    state = :sys.get_state(pid)

    assert Enum.map(state.assigns.stories, & &1.id) == ["dropdown"]
    assert state.assigns.current_story_id == "dropdown"
  end
end

defmodule Breeze.Storybook.DetailRenderingTest do
  use Breeze.TestSupport.StorybookCase, async: true

  test "story details wrap long sources and notes to the panel width" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 40}}

    {:ok, pid} =
      start_child_server(
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

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    select_story!(pid, "dropdown")

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")

    assert plain_content
           |> String.split("\n")
           |> Enum.count(&(String.contains?(&1, "POST") and String.contains?(&1, "▼"))) == 1
  end

  test "dropdown story keeps the selected value after choosing an item" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    select_story!(pid, "dropdown")

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
end

defmodule Breeze.Storybook.FormRenderingTest do
  use Breeze.TestSupport.StorybookCase, async: true

  test "input story cursor layout stays aligned with the rendered input row" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

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

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

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
end

defmodule Breeze.Storybook.InputUpdateRenderingTest do
  use Breeze.TestSupport.StorybookCase, async: true

  test "input story updates its value through delegated story events" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

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
end

defmodule Breeze.Storybook.TextareaRenderingTest do
  use Breeze.TestSupport.StorybookCase, async: true

  test "textarea story placeholder cursor layout stays aligned with the rendered placeholder row" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} =
      start_child_server(
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
      start_child_server(
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
end

defmodule Breeze.Storybook.ModalRenderingTest do
  use Breeze.TestSupport.StorybookCase, async: true

  test "modal story opens the real modal from its trigger" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

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

  test "closing the dimmed modal restores the Storybook backdrop" do
    {terminal, pid} =
      start_storybook_server!("modal.story.exs", theme: Breeze.Theme.builtin(:nebula))

    reader = terminal.reader
    {preview_pid, _viewport} = wait_for_preview_child(pid, "modal")
    view_pid = :sys.get_state(pid).view_pid
    trigger = "storybook-preview::storybook-modal-trigger"

    assert {:noreply, ^trigger, true} = Breeze.ChildServer.set_focus(view_pid, trigger)
    send(pid, :child_invalidated)

    initial_output =
      wait_until(fn ->
        state = :sys.get_state(pid)
        if state.focused == trigger, do: state.frame.base_output, else: false
      end)

    drain_terminal_writes()
    send(pid, {reader, {:data, "\r"}})

    opened_output =
      wait_until(fn ->
        state = :sys.get_state(pid)

        if :sys.get_state(preview_pid).assigns.show_modal and
             state.focused == "storybook-preview::storybook-modal-close" do
          state.frame.base_output
        else
          false
        end
      end)

    refute opened_output == initial_output

    drain_terminal_writes()
    send(pid, {reader, {:data, "\e"}})

    closed_state =
      wait_until(fn ->
        state = :sys.get_state(pid)

        if not :sys.get_state(preview_pid).assigns.show_modal and state.focused == trigger do
          state
        else
          false
        end
      end)

    assert closed_state.frame.base_output == initial_output
    assert closed_state.debug.stats[:last_render_cause] == :child_invalidated
  end
end

defmodule Breeze.Storybook.LayoutTest do
  use Breeze.TestSupport.StorybookCase, async: true

  test "renders a keybindings bar" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")

    assert plain_content =~ "d Details"
    assert plain_content =~ "F2 Debug"
    assert plain_content =~ "F3 Theme"
    assert plain_content =~ "^j/k Stories"
    assert plain_content =~ "^h/l Variants"
    assert plain_content =~ "q Quit"
  end

  test "d toggles story details while focus is inside the preview" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, initial_acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    initial_preview_height = :sys.get_state(pid).assigns.preview_panel_height
    assert Map.has_key?(initial_acc.boxes, "storybook-details")

    assert {:noreply, "storybook-preview::storybook-button-primary", true} =
             Breeze.ChildServer.set_focus(pid, "storybook-preview::storybook-button-primary")

    assert {:noreply, "storybook-preview::storybook-button-primary", true} =
             Breeze.ChildServer.dispatch_input(pid, "d")

    assert {:ok, hidden_acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    refute Map.has_key?(hidden_acc.boxes, "storybook-details")
    assert :sys.get_state(pid).assigns.preview_panel_height > initial_preview_height

    assert {:noreply, "storybook-preview::storybook-button-primary", true} =
             Breeze.ChildServer.dispatch_input(pid, "d")

    assert {:ok, visible_acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert Map.has_key?(visible_acc.boxes, "storybook-details")
  end

  test "preview panel highlights when a focused element lives inside the preview child" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "storybook-preview::storybook-button-primary", true} =
             Breeze.ChildServer.set_focus(
               pid,
               "storybook-preview::storybook-button-primary"
             )

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert box.content =~ ~r/\e\[[0-9;]*38;5;4m╭▶/
    assert box.content =~ "Preview: Button"
  end

  test "storybook nav renders the selected marker and label without overlap" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")

    assert plain_content =~ ">Button"
  end

  test "panel focus moves from the story nav to the button preview" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, nav_box} = Breeze.ChildServer.render(pid, terminal: terminal)

    nav_header =
      nav_box.content
      |> BackBreeze.Utils.strip_escape_chars()
      |> String.split("\n")
      |> hd()

    assert nav_header =~ "╭▶Storybook"
    assert nav_header =~ "╭─Preview: Button"

    assert {:noreply, "storybook-preview::storybook-button-primary", true} =
             Breeze.ChildServer.set_focus(
               pid,
               "storybook-preview::storybook-button-primary"
             )

    assert {:ok, _acc, preview_box} = Breeze.ChildServer.render(pid, terminal: terminal)

    preview_header =
      preview_box.content
      |> BackBreeze.Utils.strip_escape_chars()
      |> String.split("\n")
      |> hd()

    assert preview_header =~ "╭─Storybook"
    assert preview_header =~ "╭▶Preview: Button"
  end

  test "F2 toggles the debug pane" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    refute :sys.get_state(pid).assigns.show_debug
    refute Map.has_key?(:sys.get_state(pid).children, "debug")

    assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, "F2")
    assert :sys.get_state(pid).assigns.show_debug

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert Map.has_key?(:sys.get_state(pid).children, "debug")
  end

  test "F3 cycles the storybook theme" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} =
      start_child_server(
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
      start_child_server(
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
end

defmodule Breeze.Storybook.InteractionLayoutTest do
  use Breeze.TestSupport.StorybookCase, async: true

  @focused_panel_color {131, 165, 152}
  @unfocused_panel_color {146, 131, 116}

  defp panel_title_color?(header, title, {red, green, blue}) do
    color = "#{red};#{green};#{blue}"

    Regex.match?(
      ~r/38;2;#{color}m╭.\e\[0m\e\[[0-9;]*38;2;#{color}m#{Regex.escape(title)}/u,
      header
    )
  end

  test "tabbing through the button variants into the preview moves the focused panel state" do
    {terminal, pid} =
      start_storybook_server!("button.story.exs", theme: Breeze.Theme.builtin(:gruvbox))

    reader = terminal.reader

    wait_for_preview_child(pid, "button")

    initial_header =
      wait_until(fn ->
        case :sys.get_state(pid).frame.last_lines do
          [header | _lines] ->
            if panel_title_color?(header, "Storybook", @focused_panel_color) and
                 panel_title_color?(header, "Preview: Button", @unfocused_panel_color) do
              header
            else
              false
            end

          _lines ->
            false
        end
      end)

    assert panel_title_color?(initial_header, "Storybook", @focused_panel_color)
    assert panel_title_color?(initial_header, "Preview: Button", @unfocused_panel_color)

    send(pid, {reader, {:data, "\t"}})

    wait_until(fn ->
      :sys.get_state(pid).focused == "storybook-variant-tabs"
    end)

    send(pid, {reader, {:data, "\t"}})

    focused_header =
      wait_until(
        fn ->
          state = :sys.get_state(pid)

          with "storybook-preview::storybook-button-primary" <- state.focused,
               [header | _lines] <- state.frame.last_lines,
               true <- panel_title_color?(header, "Storybook", @unfocused_panel_color),
               true <- panel_title_color?(header, "Preview: Button", @focused_panel_color) do
            header
          else
            _other -> false
          end
        end,
        500
      )

    assert panel_title_color?(focused_header, "Storybook", @unfocused_panel_color)
    assert panel_title_color?(focused_header, "Preview: Button", @focused_panel_color)
  end

  test "server lets storybook F3 run before focused preview live child input" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      start_app_server(
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

  for {name, file, focus_id, open?} <- [
        {"focused checkbox", "checkbox.story.exs", "storybook-checkbox-mouse", false},
        {"open dropdown", "dropdown.story.exs", "storybook-dropdown", true},
        {"focused list", "list.story.exs", "storybook-list-muted", false}
      ] do
    test "server cascades the storybook F3 theme through #{name}" do
      terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

      {:ok, pid} =
        start_app_server(
          view: Breeze.Storybook,
          terminal: terminal,
          theme: Breeze.Theme.builtin(:gruvbox),
          start_opts: [directory: "storybook", file: unquote(file)]
        )

      on_exit(fn -> stop_server(pid) end)

      view_pid = :sys.get_state(pid).view_pid
      focused = "storybook-preview::" <> unquote(focus_id)

      wait_until(fn ->
        Map.has_key?(:sys.get_state(pid).children, "storybook-preview")
      end)

      preview_pid = :sys.get_state(pid).children["storybook-preview"].pid

      assert {:noreply, ^focused, true} = Breeze.ChildServer.set_focus(view_pid, focused)

      if unquote(open?) do
        assert {:noreply, ^focused, true} = Breeze.ChildServer.dispatch_input(view_pid, "Enter")
      end

      send(pid, :child_invalidated)

      wait_until(fn ->
        :sys.get_state(pid).focused == focused
      end)

      send(pid, {terminal.reader, {:data, "\e[13~"}})

      wait_until(fn ->
        Breeze.ChildServer.metadata(view_pid).theme.name == "nord" and
          Breeze.ChildServer.metadata(preview_pid).theme.name == "nord"
      end)
    end
  end
end

defmodule Breeze.Storybook.VariantInteractionLayoutTest do
  use Breeze.TestSupport.StorybookCase, async: true

  test "list story renders variant tabs below the description and switches variants" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

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

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

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
end

defmodule Breeze.Storybook.ScrollInteractionLayoutTest do
  use Breeze.TestSupport.StorybookCase, async: true

  test "list story mouse wheel scrolls the preview list without changing selection" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

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
                 "button" => "wheel_down",
                 "action" => "press",
                 "x" => preview_bounds.left + div(preview_bounds.width, 2),
                 "y" => preview_bounds.top + 2
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

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    select_story!(pid, "table")
    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    child = :sys.get_state(pid).children["storybook-preview"].pid
    {Breeze.Implicit.List, before_table} = :sys.get_state(child).implicit_state["storybook-table"]
    preview_bounds = Breeze.ChildServer.layout_snapshot(pid).mouse_targets["storybook-preview"]

    assert {:noreply, "storybook-nav", true} =
             Breeze.ChildServer.dispatch_input(pid, %{
               "mouse" => %{
                 "button" => "wheel_down",
                 "action" => "press",
                 "x" => preview_bounds.left + div(preview_bounds.width, 2),
                 "y" => preview_bounds.top + 3
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

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "storybook-preview::storybook-button-primary", true} =
             Breeze.ChildServer.set_focus(pid, "storybook-preview::storybook-button-primary")

    assert {:noreply, "storybook-nav", true} =
             Breeze.ChildServer.dispatch_input(pid, %{"ctrlKey" => true, "key" => "ArrowDown"})

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "Preview: Checkbox"

    assert {:noreply, "storybook-nav", true} =
             Breeze.ChildServer.dispatch_input(pid, %{"ctrlKey" => true, "key" => "ArrowUp"})

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "Preview: Button"
  end
end

defmodule Breeze.Storybook.VariantNavigationTest do
  use Breeze.TestSupport.StorybookCase, async: true

  test "Ctrl+H/L and Ctrl+Left/Right navigate variants regardless of current focus" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

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
end

defmodule Breeze.Storybook.PreviewNavigationTest do
  use Breeze.TestSupport.StorybookCase, async: true

  test "ctrl-arrow story navigation does not duplicate the input cursor overlay" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} = start_app_server(view: Breeze.Storybook, terminal: terminal, reader: reader)

    view_pid = :sys.get_state(pid).view_pid

    on_exit(fn -> stop_server(pid) end)

    wait_until(fn ->
      :sys.get_state(view_pid).assigns.current_story_id == "button"
    end)

    send(pid, {reader, {:data, "\e[B"}})

    wait_until(fn ->
      :sys.get_state(view_pid).assigns.current_story_id == "checkbox"
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
      500
    )

    view_state = :sys.get_state(view_pid)
    input_index = Enum.find_index(view_state.assigns.stories, &(&1.id == "input"))
    next_story_id = Enum.at(view_state.assigns.stories, input_index + 1).id

    send(pid, {reader, {:data, "\e[1;5B"}})

    wait_until(
      fn ->
        state = :sys.get_state(pid)

        state.focused == "storybook-nav" and
          :sys.get_state(view_pid).assigns.current_story_id == next_story_id and
          state.frame.last_overlays == []
      end,
      500
    )
  end
end

defmodule Breeze.Storybook.PreviewFocusNavigationTest do
  use Breeze.TestSupport.StorybookCase, async: true

  test "preview panel highlights for the dropdown story when the dropdown is focused" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    select_story!(pid, "dropdown")
    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "storybook-preview::storybook-dropdown", true} =
             Breeze.ChildServer.set_focus(
               pid,
               "storybook-preview::storybook-dropdown"
             )

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert box.content =~ ~r/\e\[[0-9;]*38;5;4m╭▶/
    assert box.content =~ "Preview: Dropdown"
  end

  test "preview panel highlights for the scroll story when the scroll region is focused" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} = start_child_server(view: Breeze.Storybook, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    select_story!(pid, "scroll")
    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "storybook-preview::storybook-scroll", true} =
             Breeze.ChildServer.set_focus(
               pid,
               "storybook-preview::storybook-scroll"
             )

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert box.content =~ ~r/\e\[[0-9;]*38;5;4m╭▶/
    assert box.content =~ "Preview: Scroll"
  end
end

defmodule Breeze.Storybook.ServerRenderingTest do
  use Breeze.TestSupport.StorybookCase, async: true

  defmodule NestedStorybookRoot do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box class="padding-top-3 padding-left-5 width-full height-full">
        <live
          id="outer"
          view={Breeze.Storybook}
          start_opts={[directory: "storybook", file: "input.story.exs"]}
          class="width-60 height-18"
          focusable
        >
        </live>
      </box>
      """
    end
  end

  test "nested storybook cursor decorations use absolute preview coordinates" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} = start_app_server(view: NestedStorybookRoot, terminal: terminal)

    on_exit(fn -> stop_server(pid) end)

    state =
      wait_until(
        fn ->
          state = :sys.get_state(pid)

          if Map.has_key?(state.children, "outer::storybook-preview") do
            state
          end
        end,
        500
      )

    preview_pid = state.children["outer::storybook-preview"].pid

    assert {:noreply, "storybook-input-active", true} =
             Breeze.ChildServer.set_focus(preview_pid, "storybook-input-active")

    :sys.replace_state(pid, fn state ->
      %{state | focused: "outer::storybook-preview::storybook-input-active"}
    end)

    send(pid, :child_invalidated)

    {input_viewport, cursor_layout} =
      wait_until(
        fn ->
          state = :sys.get_state(pid)

          input_viewport =
            state.rendered.elements["outer::storybook-preview::storybook-input-active"]

          cursor =
            Enum.find(state.frame.decorations, fn decoration ->
              decoration.id == "outer::storybook-preview::storybook-input-active"
            end)

          if input_viewport && cursor, do: {input_viewport, cursor.layout}
        end,
        500
      )

    assert cursor_layout.left == input_viewport.left
    assert cursor_layout.top == input_viewport.top
  end

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

    assert Enum.any?(writes, fn write ->
             write =~ ~r/\e\[[0-9;]*48;5;0(?:;[0-9;]*)?m/
           end)
  end
end

defmodule Breeze.Storybook.ServerPatchRenderingTest do
  use Breeze.TestSupport.StorybookCase, async: true

  test "storybook preview child patches dropdown highlight changes" do
    {terminal, pid} = start_storybook_server!("dropdown.story.exs")

    {preview_pid, viewport} = wait_for_preview_child(pid, "dropdown")

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(preview_pid, terminal: terminal)

    assert {:noreply, "storybook-dropdown", _changed?} =
             Breeze.ChildServer.set_focus(preview_pid, "storybook-dropdown")

    :sys.replace_state(pid, fn state ->
      %{state | focused: "storybook-preview::storybook-dropdown"}
    end)

    drain_terminal_writes()

    assert {:noreply, "storybook-dropdown", true} =
             Breeze.ChildServer.dispatch_input(preview_pid, "Enter")

    wait_until(fn ->
      match?(
        {Breeze.Implicit.Dropdown, %{open?: true, highlighted_index: 1}},
        Breeze.ChildServer.metadata(preview_pid).implicit_state["storybook-dropdown"]
      )
    end)

    _writes = await_terminal_writes()
    drain_terminal_writes()

    assert {:noreply, "storybook-dropdown", true} =
             Breeze.ChildServer.dispatch_input(preview_pid, "ArrowDown")

    wait_until(fn ->
      match?(
        {Breeze.Implicit.Dropdown, %{open?: true, highlighted_index: 2}},
        Breeze.ChildServer.metadata(preview_pid).implicit_state["storybook-dropdown"]
      )
    end)

    writes =
      wait_until(
        fn ->
          writes = drain_terminal_writes()
          payload = IO.iodata_to_binary(writes)

          if payload =~ ~r/\e\[7(?:;[0-9]+)*mPUT/, do: writes, else: false
        end,
        500
      )

    assert redraw_or_full_viewport_patch?(writes, viewport)
    payload = IO.iodata_to_binary(writes)
    assert payload =~ ~r/\e\[7(?:;[0-9]+)*mPUT/
    refute payload =~ ~r/\e\[7(?:;[0-9]+)*mPOST/
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
end

defmodule Breeze.Storybook.PreviewInputRenderingTest do
  use Breeze.TestSupport.StorybookCase, async: true

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
end

defmodule Breeze.Storybook.PreviewWheelRenderingTest do
  use Breeze.TestSupport.StorybookCase, async: true

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
end

defmodule Breeze.Storybook.PreviewPatchInputRenderingTest do
  use Breeze.TestSupport.StorybookCase, async: true

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

  test "tabbing a focused preview control avoids a full redraw" do
    {terminal, pid} = start_storybook_server!("tabs.story.exs")

    {preview_pid, _viewport} = wait_for_preview_child(pid, "tabs")
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
  end
end
