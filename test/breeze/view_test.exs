defmodule Breeze.ViewTest do
  use ExUnit.Case, async: true

  import Breeze.View
  import Breeze.TestSupport.WaitUntil

  defmodule BreezeAssignsView do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box>{@breeze.theme.name}/{@breeze.theme.actual_mode}/{@breeze.theme.status}</box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
  end

  defmodule FlashLifecycleView do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box>flash lifecycle</box>
      """
    end

    def handle_event("push", _event, term) do
      term =
        term
        |> put_flash(:info, "One", id: "one", max: 2, duration: 20)
        |> put_flash(:warning, "Two", id: "two", duration: 250)
        |> put_flash(:error, "Three", id: "three", duration: 250)

      {:noreply, term}
    end

    def handle_event("push_serial", _event, term) do
      term =
        term
        |> put_flash(:info, "First", id: "first", max: 1, duration: 220)
        |> put_flash(:success, "Second", id: "second", duration: 100)

      {:noreply, term}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  test "update_implicit updates an existing implicit state" do
    term = %{
      implicit_state: %{
        "dropdown" =>
          {Breeze.Implicit.Dropdown, %{open?: false, selected_index: 1, highlighted_index: 0}}
      }
    }

    updated =
      update_implicit(term, "dropdown", fn
        {Breeze.Implicit.Dropdown, state} -> Breeze.Implicit.Dropdown.open(state)
      end)

    assert {Breeze.Implicit.Dropdown, %{open?: true, highlighted_index: 1}} =
             updated.implicit_state["dropdown"]
  end

  test "update_implicit ignores missing implicits" do
    term = %{implicit_state: %{}}

    assert update_implicit(term, "missing", fn {_mod, state} -> state end) == term
  end

  test "put_local_keybindings and put_focus_keybindings normalize keybinding hints" do
    term = %Breeze.Term{assigns: %{}, local_keybindings: [], focus_keybindings: %{}}

    updated =
      term
      |> put_local_keybindings([{"q", "Quit"}])
      |> put_focus_keybindings("editor", [{"Enter", "Save"}])

    assert updated.local_keybindings == [%{key: "q", label: "Quit", handler: nil}]

    assert updated.focus_keybindings == %{
             "editor" => [%{key: "Enter", label: "Save", handler: nil}]
           }
  end

  test "put_flash appends stackable flash entries" do
    term = %Breeze.Term{assigns: %{}}

    updated =
      term
      |> put_flash(:info, "Saved", id: "save", highlight: "accent")
      |> put_flash(:error, "Publish failed", id: "publish-error", highlight: "error")
      |> put_flash(:info, "Custom", id: "custom", color: "#f0a")

    assert Breeze.Flash.entries(updated.assigns.breeze.flash) == [
             %{id: "save", kind: :info, message: "Saved", highlight: "accent"},
             %{
               id: "publish-error",
               kind: :error,
               message: "Publish failed",
               highlight: "error"
             },
             %{id: "custom", kind: :info, message: "Custom", highlight: "#f0a"}
           ]

    assert Breeze.Flash.queued_entries(updated.assigns.breeze.flash) == []
  end

  test "put_flash queues entries past the visible max" do
    term =
      %Breeze.Term{assigns: %{}}
      |> put_flash(:info, "One", id: "one", max: 2, duration: false)
      |> put_flash(:info, "Two", id: "two")
      |> put_flash(:info, "Three", id: "three")

    assert Enum.map(Breeze.Flash.entries(term.assigns.breeze.flash), & &1.id) == ["one", "two"]
    assert Enum.map(Breeze.Flash.queued_entries(term.assigns.breeze.flash), & &1.id) == ["three"]
  end

  test "clear_flash removes messages by kind, id, or all messages" do
    term =
      %Breeze.Term{assigns: %{}}
      |> put_flash(:info, "Saved", id: "save")
      |> put_flash(:error, "Publish failed", id: "publish-error")

    assert Breeze.Flash.entries(clear_flash(term, :info).assigns.breeze.flash) == [
             %{id: "publish-error", kind: :error, message: "Publish failed"}
           ]

    assert Breeze.Flash.entries(clear_flash(term, "publish-error").assigns.breeze.flash) == [
             %{id: "save", kind: :info, message: "Saved"}
           ]

    assert clear_flash(term).assigns.breeze.flash == []
  end

  test "flash timeout clears visible entries and promotes queued entries" do
    session = Breeze.Test.start!(FlashLifecycleView)
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert {:noreply, _focused, true} = Breeze.Test.event(session, "push", %{})

    flash = Breeze.Test.metadata(session).assigns.breeze.flash
    assert Enum.map(Breeze.Flash.entries(flash), & &1.id) == ["one", "two"]
    assert Enum.map(Breeze.Flash.queued_entries(flash), & &1.id) == ["three"]

    wait_until(fn ->
      flash = Breeze.Test.metadata(session).assigns.breeze.flash

      Enum.map(Breeze.Flash.entries(flash), & &1.id) == ["two", "three"] and
        Breeze.Flash.queued_entries(flash) == []
    end)
  end

  test "queued flash starts its timeout only after it is promoted" do
    session = Breeze.Test.start!(FlashLifecycleView)
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert {:noreply, _focused, true} = Breeze.Test.event(session, "push_serial", %{})

    Process.sleep(130)

    flash = Breeze.Test.metadata(session).assigns.breeze.flash
    assert Enum.map(Breeze.Flash.entries(flash), & &1.id) == ["first"]
    assert Enum.map(Breeze.Flash.queued_entries(flash), & &1.id) == ["second"]

    wait_until(fn ->
      flash = Breeze.Test.metadata(session).assigns.breeze.flash

      Enum.map(Breeze.Flash.entries(flash), & &1.id) == ["second"] and
        Breeze.Flash.queued_entries(flash) == []
    end)

    Process.sleep(50)

    flash = Breeze.Test.metadata(session).assigns.breeze.flash
    assert Enum.map(Breeze.Flash.entries(flash), & &1.id) == ["second"]

    wait_until(fn ->
      Breeze.Test.metadata(session).assigns.breeze.flash
      |> Breeze.Flash.entries()
      |> Enum.empty?()
    end)
  end

  test "switch_theme applies a named theme and standard Breeze metadata assigns" do
    term = %Breeze.Term{assigns: %{}}

    updated = switch_theme(term, :gruvbox)

    assert updated.assigns.breeze.theme == %{
             name: :gruvbox,
             actual_mode: :custom,
             status: :ready
           }

    assert updated.theme.name == "gruvbox-dark"
  end

  test "cycle_theme advances through the default theme cycle" do
    term =
      %Breeze.Term{assigns: %{}}
      |> switch_theme(:gruvbox)
      |> cycle_theme()

    assert term.assigns.breeze.theme.name == :nord
    assert term.theme.name == "nord"
  end

  test "cycle_theme can be used directly as a keybinding handler" do
    term = %Breeze.Term{assigns: %{}} |> switch_theme(:solarized_dark)

    assert {:noreply, updated} = cycle_theme(%{"key" => "F3"}, term)
    assert updated.assigns.breeze.theme.name == :system16
    assert updated.theme.mode == :system16
  end

  test "rendering exposes theme metadata in the Breeze assigns namespace" do
    session = Breeze.Test.start!(BreezeAssignsView, theme: Breeze.Theme.builtin(:gruvbox))

    assert Breeze.Test.render!(session) =~ "gruvbox-dark/custom/ready"

    Breeze.Test.stop(session)
  end
end
