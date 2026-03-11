defmodule ModalExample do
  use Breeze.View
  import Breeze.Blocks

  def mount(_opts, term) do
    {:ok,
     term
     |> focus("open-modal")
     |> assign(show_modal: false, selected_action: "none")}
  end

  def render(assigns) do
    ~H"""
    <box style="width-screen height-screen">
      <box style="bold">Modal example</box>
      <box>Press Enter or m to open the modal.</box>
      <box>Tab should stay inside the modal until it closes.</box>
      <box>Escape closes the modal. q quits the example.</box>
      <box>
      </box>
      <box id="open-modal" focusable style="border-rounded width-26 height-3 focus:border-4">
        <box style="bold">Open modal</box>
      </box>
      <box>
      </box>
      <box id="other-panel" focusable style="border-rounded width-26 height-4 focus:border-4">
        <box style="bold">Background panel</box>
        <box>Last action: {@selected_action}</box>
      </box>
      <.modal :if={@show_modal} id="example-modal" width={46} height={10} br-change="close_modal">
        <:title>Focused Widget Help</:title>
        <box>Centered panel with trapped Tab focus.</box>
        <box>Use it for help, palettes, and overlays.</box>
        <box>
        </box>
        <box style="bold">Controls</box>
        <box style="inline">
          <box style="width-10">Tab</box>
          <box>Move between actions</box>
        </box>
        <box style="inline">
          <box style="width-10">Escape</box>
          <box>Dismiss the modal</box>
        </box>
        <box style="inline">
          <box style="width-10">Enter</box>
          <box>Activate focused action</box>
        </box>
        <box style="inline">
          <box
            id="confirm"
            focusable
            default-focus
            style="border-rounded width-14 height-1 focus:border-4"
          >
            <box style="bold">Confirm</box>
          </box>
          <box>
          </box>
          <box id="cancel" focusable style="border-rounded width-14 height-1 focus:border-4">
            <box style="bold">Dismiss</box>
          </box>
        </box>
      </.modal>
    </box>
    """
  end

  def handle_event("close_modal", _, term), do: {:noreply, assign(term, show_modal: false)}

  def handle_event(_, %{"key" => key}, %{assigns: %{show_modal: false}} = term)
      when key in ["Enter", "m"] and term.focused == "open-modal" do
    {:noreply, assign(term, show_modal: true)}
  end

  def handle_event(_, %{"key" => "m"}, term), do: {:noreply, assign(term, show_modal: true)}

  def handle_event(
        _,
        %{"key" => "Enter"},
        %{assigns: %{show_modal: true}, focused: "confirm"} = term
      ),
      do: {:noreply, assign(term, show_modal: false, selected_action: "confirm")}

  def handle_event(
        _,
        %{"key" => "Enter"},
        %{assigns: %{show_modal: true}, focused: "cancel"} = term
      ),
      do: {:noreply, assign(term, show_modal: false, selected_action: "cancel")}

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(_, term), do: {:noreply, term}
end

Breeze.Server.start_link(
  view: ModalExample,
  hide_cursor: true,
  global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
)

receive do
end
