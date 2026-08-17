defmodule Breeze.Implicit.CheckboxTest do
  use ExUnit.Case, async: true

  import Breeze.TestSupport.ProcessHelpers, only: [start_child_server: 1]

  alias Breeze.ChildServer
  alias Breeze.Implicit.Checkbox

  defmodule CheckboxView do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term |> assign(checked: false) |> focus("other")}

    def render(assigns) do
      ~H"""
      <box class="width-30 height-3">
        <box class="height-1">
          <.button id="other">Other</.button>
        </box>
        <box class="height-1">
          <.checkbox id="mouse" checked={@checked} br-change="mouse_changed">Mouse</.checkbox>
        </box>
      </box>
      """
    end

    def handle_event("mouse_changed", %{value: value}, term) do
      {:noreply, assign(term, checked: value)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule UncontrolledCheckboxView do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, focus(term, "mouse")}

    def render(assigns) do
      ~H"""
      <.checkbox id="mouse">Mouse</.checkbox>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule DisabledCheckboxView do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, focus(term, "other")}

    def render(assigns) do
      ~H"""
      <box class="width-30 height-3">
        <box id="other" focusable class="height-1">Other</box>
        <box class="height-1">
          <.checkbox id="mouse" disabled br-change="mouse_changed">Mouse</.checkbox>
        </box>
      </box>
      """
    end

    def handle_event("mouse_changed", %{value: value}, term) do
      {:noreply, assign(term, changed_to: value)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  describe "init/3" do
    test "starts unchecked and enabled" do
      assert {:ok, %{checked: false, disabled: false}} = Checkbox.init([], %{}, %{})
    end

    test "adopts a controlled checked value over its previous state" do
      assert {:ok, %{checked: false}} =
               Checkbox.init([], %{:"checkbox-checked" => "false"}, %{checked: true})

      assert {:ok, %{checked: true}} =
               Checkbox.init([], %{:"checkbox-checked" => "true"}, %{checked: false})
    end

    test "retains its previous value when checked is uncontrolled" do
      assert {:ok, %{checked: true}} = Checkbox.init([], %{}, %{checked: true})
    end
  end

  describe "handle_event/3" do
    test "Enter and Space toggle and emit the boolean value" do
      for key <- ["Enter", " "] do
        state = %{checked: false, disabled: false}

        assert {{:change, %{value: true}}, %{checked: true}} =
                 Checkbox.handle_event(:input, %{"key" => key}, state)
      end
    end

    test "the first left press toggles regardless of prior focus" do
      state = %{checked: false, disabled: false}

      event = %{
        "mouse" => %{"button" => "left", "action" => "press"},
        "target" => "mouse",
        "focused" => "other"
      }

      assert {{:change, %{value: true}}, %{checked: true}} =
               Checkbox.handle_event(:input, event, state)
    end

    test "disabled checkboxes ignore keyboard and mouse activation" do
      state = %{checked: false, disabled: true}
      mouse = %{"mouse" => %{"button" => "left", "action" => "press"}}

      assert {:noreply, ^state} = Checkbox.handle_event(:input, %{"key" => " "}, state)
      assert {:noreply, ^state} = Checkbox.handle_event(:input, %{"key" => "Enter"}, state)
      assert {:noreply, ^state} = Checkbox.handle_event(:input, mouse, state)
    end
  end

  test "checked state selects the root and matching indicator" do
    assert [selected: true] =
             Checkbox.handle_modifiers(:root, [], %{checked: true, disabled: false})

    assert [] = Checkbox.handle_modifiers(:root, [], %{checked: false, disabled: false})

    assert [selected: true] =
             Checkbox.handle_modifiers(:child, [{:"checkbox-state", "checked"}], %{
               checked: true,
               disabled: false
             })

    assert [] =
             Checkbox.handle_modifiers(:child, [{:"checkbox-state", "unchecked"}], %{
               checked: true,
               disabled: false
             })
  end

  test "disabled state mutes the root and every owned child" do
    state = %{checked: false, disabled: true}

    assert [style: "text-muted"] = Checkbox.handle_modifiers(:root, [], state)

    assert [selected: true, style: "text-muted"] =
             Checkbox.handle_modifiers(
               :child,
               [{:"checkbox-state", "unchecked"}],
               state
             )

    assert [style: "text-muted"] = Checkbox.handle_modifiers(:child, [], state)
  end

  test "a first click focuses and toggles the rendered checkbox" do
    terminal = %Termite.Terminal{size: %{width: 30, height: 5}}
    {:ok, pid} = start_child_server(view: CheckboxView, terminal: terminal)

    assert {:ok, _acc, box} = ChildServer.render(pid, terminal: terminal)
    assert strip_ansi(box.content) =~ "[ ] Mouse"

    assert {:noreply, "mouse", true} = click(pid, "mouse")

    assert %{focused: "mouse", assigns: %{checked: true}} = ChildServer.metadata(pid)
    assert %{"mouse" => {Checkbox, %{checked: true}}} = ChildServer.metadata(pid).implicit_state

    assert {:ok, _acc, box} = ChildServer.render(pid, terminal: terminal)
    content = strip_ansi(box.content)
    assert content =~ "|x| Mouse"
    refute content =~ "[x] Mouse"

    assert {:noreply, "mouse", true} = click(pid, "mouse")
    assert %{assigns: %{checked: false}} = ChildServer.metadata(pid)
  end

  test "focus uses bar delimiters as a non-color cue" do
    terminal = %Termite.Terminal{size: %{width: 20, height: 3}}
    {:ok, pid} = start_child_server(view: UncontrolledCheckboxView, terminal: terminal)

    assert {:ok, _acc, box} = ChildServer.render(pid, terminal: terminal)
    content = strip_ansi(box.content)

    assert content =~ "| | Mouse"
    refute content =~ "[ ] Mouse"
  end

  test "Space and Enter toggle a rendered checkbox" do
    terminal = %Termite.Terminal{size: %{width: 30, height: 5}}
    {:ok, pid} = start_child_server(view: CheckboxView, terminal: terminal)

    assert {:ok, _acc, _box} = ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "mouse", true} = ChildServer.set_focus(pid, "mouse")

    assert {:noreply, "mouse", true} = ChildServer.dispatch_input(pid, " ")
    assert %{assigns: %{checked: true}} = ChildServer.metadata(pid)

    assert {:noreply, "mouse", true} = ChildServer.dispatch_input(pid, "Enter")
    assert %{assigns: %{checked: false}} = ChildServer.metadata(pid)
  end

  test "an uncontrolled checkbox retains its implicit state" do
    terminal = %Termite.Terminal{size: %{width: 20, height: 3}}
    {:ok, pid} = start_child_server(view: UncontrolledCheckboxView, terminal: terminal)

    assert {:ok, _acc, _box} = ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "mouse", true} = ChildServer.dispatch_input(pid, " ")
    assert {:ok, _acc, box} = ChildServer.render(pid, terminal: terminal)

    assert strip_ansi(box.content) =~ "|x| Mouse"
  end

  test "a disabled checkbox cannot receive focus or toggle" do
    terminal = %Termite.Terminal{size: %{width: 30, height: 5}}

    {:ok, pid} =
      start_child_server(
        view: DisabledCheckboxView,
        terminal: terminal,
        theme: Breeze.Theme.builtin(:nebula)
      )

    assert {:ok, acc, box} = ChildServer.render(pid, terminal: terminal)
    refute "mouse" in acc.focusables
    assert box.content =~ ~r/\e\[[0-9;]*38;2;125;163;200m⟦ ⟧ Mouse/

    assert {:noreply, "other", false} = click(pid, "mouse")

    assert %{focused: "other", assigns: assigns} = ChildServer.metadata(pid)
    refute Map.has_key?(assigns, :changed_to)

    assert %{"mouse" => {Checkbox, %{checked: false, disabled: true}}} =
             ChildServer.metadata(pid).implicit_state
  end

  defp click(pid, id) do
    bounds = :sys.get_state(pid).mouse_targets[id]

    ChildServer.dispatch_input(pid, %{
      "mouse" => %{
        "button" => "left",
        "action" => "press",
        "x" => div(bounds.left + bounds.right, 2),
        "y" => div(bounds.top + bounds.bottom, 2)
      }
    })
  end

  defp strip_ansi(content), do: Regex.replace(~r/\e\[[0-9;]*m/u, content, "")
end
