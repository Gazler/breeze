defmodule Breeze.ChildServerEventTest do
  use ExUnit.Case, async: true

  defmodule ModalView do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term) do
      {:ok, assign(term, show_modal: true, closed?: false)}
    end

    def render(assigns) do
      ~H"""
      <box style="width-screen height-screen">
        <.modal :if={@show_modal} id="example-modal" width={30} height={6} br-change="close_modal">
          <:title>Modal</:title>
          <box
            id="confirm"
            focusable
            default-focus
            style="border-rounded width-10 height-1 focus:border-4"
          >
            <box>Confirm</box>
          </box>
        </.modal>
      </box>
      """
    end

    def handle_event("close_modal", _event, term) do
      {:noreply, assign(term, show_modal: false, closed?: true)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  test "escape on a focused modal child routes to the modal implicit" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: ModalView, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert %{focused: "confirm"} = Breeze.ChildServer.metadata(pid)

    assert {:noreply, "confirm", true} = Breeze.ChildServer.dispatch_input(pid, "Escape")

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    state = :sys.get_state(pid)

    assert state.assigns.closed? == true
    assert state.assigns.show_modal == false
  end
end
