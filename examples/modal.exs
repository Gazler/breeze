defmodule ModalExample do
  use Breeze.View
  import Breeze.Blocks

  def mount(_opts, term) do
    {:ok,
     term
     |> focus("open-modal")
     |> assign(show_modal: false, selected_action: "none", modal_variant: :centered)}
  end

  def render(assigns) do
    ~H"""
    <box style="width-screen height-screen">
      <box style="bold">Modal example</box>
      <box>Press Enter, m, or 1/2/3 to open a modal.</box>
      <box>Tab should stay inside the modal until it closes.</box>
      <box>Escape closes the modal. q quits the example.</box>
      <box>
      </box>
      <box style="bold">Modal sizes</box>
      <box id="open-modal" focusable style="border-rounded width-18 height-3 focus:border-4">
        <box style="bold text-center">Centered</box>
      </box>
      <box id="open-wide-modal" focusable style="border-rounded width-18 height-3 focus:border-4">
        <box style="bold text-center">Wide</box>
      </box>
      <box id="open-inset-modal" focusable style="border-rounded width-18 height-3 focus:border-4">
        <box style="bold text-center">Inset</box>
      </box>
      <box>
      </box>
      <box id="other-panel" focusable style="border-rounded width-26 height-4 focus:border-4">
        <box style="bold">Background panel</box>
        <box>Last action: {@selected_action}</box>
      </box>
      <.modal
        :if={@show_modal and @modal_variant == :centered}
        id="example-modal"
        width={46}
        height={10}
        br-change="close_modal"
      >
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
      <.modal
        :if={@show_modal and @modal_variant == :wide}
        id="wide-modal"
        width={64}
        height={12}
        br-change="close_modal"
      >
        <:title>Wide Modal</:title>
        <box>This modal uses the fixed-size centered form.</box>
        <box>Use larger explicit dimensions for palettes and editors.</box>
        <box>
        </box>
        <box style="bold">Controls</box>
        <box style="inline">
          <box style="width-10">Enter</box>
          <box>Confirm the current action</box>
        </box>
        <box style="inline">
          <box style="width-10">Escape</box>
          <box>Dismiss the modal</box>
        </box>
        <box>
        </box>
        <box
          id="wide-close"
          focusable
          default-focus
          style="border-rounded width-18 height-1 focus:border-4"
        >
          <box style="bold text-center">Close</box>
        </box>
      </.modal>
      <.modal
        :if={@show_modal and @modal_variant == :inset}
        id="inset-modal"
        inset_x={4}
        inset_y={2}
        br-change="close_modal"
      >
        <:title>Inset Modal</:title>
        <box>This modal uses fixed inset-x-4 inset-y-2 width-screen height-screen.</box>
        <box>It is useful for fullscreen dialogs that still leave a gutter.</box>
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
        <box>
        </box>
        <box
          id="inset-close"
          focusable
          default-focus
          style="border-rounded width-18 height-1 focus:border-4"
        >
          <box style="bold text-center">Close</box>
        </box>
      </.modal>
    </box>
    """
  end

  def handle_event("close_modal", _, term), do: {:noreply, assign(term, show_modal: false)}

  def handle_event(_, %{"key" => "1"}, term),
    do: {:noreply, assign(term, show_modal: true, modal_variant: :centered)}

  def handle_event(_, %{"key" => "2"}, term),
    do: {:noreply, assign(term, show_modal: true, modal_variant: :wide)}

  def handle_event(_, %{"key" => "3"}, term),
    do: {:noreply, assign(term, show_modal: true, modal_variant: :inset)}

  def handle_event(_, %{"key" => key}, %{assigns: %{show_modal: false}} = term)
      when key in ["Enter", "m"] and term.focused == "open-modal" do
    {:noreply, assign(term, show_modal: true, modal_variant: :centered)}
  end

  def handle_event(_, %{"key" => key}, %{assigns: %{show_modal: false}} = term)
      when key in ["Enter", "m"] and term.focused == "open-wide-modal" do
    {:noreply, assign(term, show_modal: true, modal_variant: :wide)}
  end

  def handle_event(_, %{"key" => key}, %{assigns: %{show_modal: false}} = term)
      when key in ["Enter", "m"] and term.focused == "open-inset-modal" do
    {:noreply, assign(term, show_modal: true, modal_variant: :inset)}
  end

  def handle_event(_, %{"key" => "m"}, term),
    do: {:noreply, assign(term, show_modal: true, modal_variant: :centered)}

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

  def handle_event(
        _,
        %{"key" => "Enter"},
        %{assigns: %{show_modal: true}, focused: focus} = term
      )
      when focus in ["wide-close", "inset-close"] do
    {:noreply, assign(term, show_modal: false, selected_action: "dismiss")}
  end

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(_, term), do: {:noreply, term}
end

Breeze.Example.run(
  [
    view: ModalExample,
    hide_cursor: true,
    global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
