defmodule Breeze.Implicit.CheckboxTest do
  use ExUnit.Case, async: true

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
    session = Breeze.Test.start!(CheckboxView, size: {30, 5})
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert Breeze.Test.render_text!(session) =~ "[ ] Mouse"

    assert {:noreply, "mouse", true} = Breeze.Test.click(session, "mouse")

    assert %{focused: "mouse", assigns: %{checked: true}} = Breeze.Test.metadata(session)

    assert %{"mouse" => {Checkbox, %{checked: true}}} =
             Breeze.Test.metadata(session).implicit_state

    content = Breeze.Test.render_text!(session)
    assert content =~ "|x| Mouse"
    refute content =~ "[x] Mouse"

    assert {:noreply, "mouse", true} = Breeze.Test.click(session, "mouse")
    assert %{assigns: %{checked: false}} = Breeze.Test.metadata(session)
  end

  test "focus uses bar delimiters as a non-color cue" do
    session = Breeze.Test.start!(UncontrolledCheckboxView, size: {20, 3})
    on_exit(fn -> Breeze.Test.stop(session) end)

    content = Breeze.Test.render_text!(session)

    assert content =~ "| | Mouse"
    refute content =~ "[ ] Mouse"
  end

  test "Space and Enter toggle a rendered checkbox" do
    session = Breeze.Test.start!(CheckboxView, size: {30, 5})
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert {:noreply, "mouse", true} = Breeze.Test.focus(session, "mouse")

    assert {:noreply, "mouse", true} = Breeze.Test.input(session, " ")
    assert %{assigns: %{checked: true}} = Breeze.Test.metadata(session)

    assert {:noreply, "mouse", true} = Breeze.Test.input(session, "Enter")
    assert %{assigns: %{checked: false}} = Breeze.Test.metadata(session)
  end

  test "an uncontrolled checkbox retains its implicit state" do
    session = Breeze.Test.start!(UncontrolledCheckboxView, size: {20, 3})
    on_exit(fn -> Breeze.Test.stop(session) end)

    _ = Breeze.Test.render!(session)
    assert {:noreply, "mouse", true} = Breeze.Test.input(session, " ")

    assert Breeze.Test.render_text!(session) =~ "|x| Mouse"
  end

  test "a disabled checkbox cannot receive focus or toggle" do
    terminal = %Termite.Terminal{size: %{width: 30, height: 5}}

    session =
      Breeze.Test.start!(DisabledCheckboxView,
        terminal: terminal,
        theme: Breeze.Theme.builtin(:nebula)
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert {:ok, acc, box} = ChildServer.render(session.pid, terminal: terminal)
    refute "mouse" in acc.focusables
    assert box.content =~ ~r/\e\[[0-9;]*38;2;125;163;200m⟦ ⟧ Mouse/

    assert {:noreply, "other", false} = Breeze.Test.click(session, "mouse")

    assert %{focused: "other", assigns: assigns} = Breeze.Test.metadata(session)
    refute Map.has_key?(assigns, :changed_to)

    assert %{"mouse" => {Checkbox, %{checked: false, disabled: true}}} =
             Breeze.Test.metadata(session).implicit_state
  end
end
