defmodule ModalExample do
  use Breeze.View
  import Breeze.Blocks

  def mount(_opts, term) do
    {:ok,
     term
     |> focus("open-modal")
     |> assign(
       show_modal: false,
       selected_action: "none",
       modal_variant: :centered,
       spotlight: false,
       modal_dim: false
     )}
  end

  def render(assigns) do
    ~H"""
    <box class="w-screen h-screen bg">
      <box class="font-bold">Modal example</box>
      <box>Press Enter, m, or 1-7 to open an example.</box>
      <box>Modal variants trap Tab; the screen-dim example does not.</box>
      <box>Escape closes the active example. q quits the example.</box>
      <box>
      </box>
      <box class="font-bold">Normal</box>
      <box class="grid grid-cols-3 w-60">
        <box id="open-modal" focusable class="rounded w-20 h-5 focus:border-4">
          <box class="font-bold text-center">Centered</box>
        </box>
        <box id="open-wide-modal" focusable class="rounded w-20 h-5 focus:border-4">
          <box class="font-bold text-center">Wide</box>
        </box>
        <box id="open-inset-modal" focusable class="rounded w-20 h-5 focus:border-4">
          <box class="font-bold text-center">Inset</box>
        </box>
      </box>
      <box>
      </box>
      <box class="font-bold">Dimmed</box>
      <box class="grid grid-cols-3 w-60">
        <box id="open-dim-modal" focusable class="rounded w-20 h-5 focus:border-4">
          <box class="font-bold text-center">Centered</box>
        </box>
        <box id="open-dim-wide-modal" focusable class="rounded w-20 h-5 focus:border-4">
          <box class="font-bold text-center">Wide</box>
        </box>
        <box id="open-dim-inset-modal" focusable class="rounded w-20 h-5 focus:border-4">
          <box class="font-bold text-center">Inset</box>
        </box>
      </box>
      <box>
      </box>
      <box class="font-bold">Non-modal screen dim</box>
      <box id="spotlight" screen-dim={@spotlight} focusable class="rounded w-20 h-5 focus:border-4">
        <box class="font-bold text-center">Spotlight</box>
      </box>
      <box>
      </box>
      <box id="other-panel" focusable class="rounded w-28 h-6 focus:border-4">
        <box class="font-bold">Background panel</box>
        <box>Last action: {@selected_action}</box>
      </box>
      <.modal
        :if={@show_modal and @modal_variant == :centered}
        id="example-modal"
        width={48}
        height={12}
        dim={@modal_dim}
        br-change="close_modal"
      >
        <:title>Focused Widget Help</:title>
        <box>Centered panel with trapped Tab focus.</box>
        <box>Use it for help, palettes, and overlays.</box>
        <box>
        </box>
        <box class="font-bold">Controls</box>
        <box class="inline">
          <box class="w-10">Tab</box>
          <box>Move between actions</box>
        </box>
        <box class="inline">
          <box class="w-10">Escape</box>
          <box>Dismiss the modal</box>
        </box>
        <box class="inline">
          <box class="w-10">Enter</box>
          <box>Activate focused action</box>
        </box>
        <box class="inline">
          <box id="confirm" focusable default-focus class="rounded w-16 h-3 focus:border-4">
            <box class="font-bold">Confirm</box>
          </box>
          <box>
          </box>
          <box id="cancel" focusable class="rounded w-16 h-3 focus:border-4">
            <box class="font-bold">Dismiss</box>
          </box>
        </box>
      </.modal>
      <.modal
        :if={@show_modal and @modal_variant == :wide}
        id="wide-modal"
        width={66}
        height={14}
        dim={@modal_dim}
        br-change="close_modal"
      >
        <:title>Wide Modal</:title>
        <box>This modal uses the fixed-size centered form.</box>
        <box>Use larger explicit dimensions for palettes and editors.</box>
        <box>
        </box>
        <box class="font-bold">Controls</box>
        <box class="inline">
          <box class="w-10">Enter</box>
          <box>Confirm the current action</box>
        </box>
        <box class="inline">
          <box class="w-10">Escape</box>
          <box>Dismiss the modal</box>
        </box>
        <box>
        </box>
        <box id="wide-close" focusable default-focus class="rounded w-20 h-3 focus:border-4">
          <box class="font-bold text-center">Close</box>
        </box>
      </.modal>
      <.modal
        :if={@show_modal and @modal_variant == :inset}
        id="inset-modal"
        inset_x={4}
        inset_y={2}
        dim={@modal_dim}
        br-change="close_modal"
      >
        <:title>Inset Modal</:title>
        <box>This modal uses fixed inset-x-4 inset-y-2 w-screen h-screen.</box>
        <box>It is useful for fullscreen dialogs that still leave a gutter.</box>
        <box>
        </box>
        <box class="font-bold">Controls</box>
        <box class="inline">
          <box class="w-10">Tab</box>
          <box>Move between actions</box>
        </box>
        <box class="inline">
          <box class="w-10">Escape</box>
          <box>Dismiss the modal</box>
        </box>
        <box>
        </box>
        <box id="inset-close" focusable default-focus class="rounded w-20 h-3 focus:border-4">
          <box class="font-bold text-center">Close</box>
        </box>
      </.modal>
      <box
        :if={@show_modal and @modal_variant == :spotlight}
        id="screen-dim-demo"
        screen-dim
        class="fixed left-18 top-6 w-44 h-8 bg z-50 rounded border-stroke"
      >
        <box class="absolute left-2 top-0 font-bold text">Screen dim only</box>
        <box>This is a plain box using screen-dim.</box>
        <box>Background focus still works outside it.</box>
        <box>Press Escape or 7 to dismiss.</box>
      </box>
    </box>
    """
  end

  def handle_event("close_modal", _, term), do: {:noreply, assign(term, show_modal: false)}

  def handle_event(_, %{"key" => "1"}, term),
    do: {:noreply, open_modal(term, :centered, false)}

  def handle_event(_, %{"key" => "2"}, term),
    do: {:noreply, open_modal(term, :wide, false)}

  def handle_event(_, %{"key" => "3"}, term),
    do: {:noreply, open_modal(term, :inset, false)}

  def handle_event(_, %{"key" => "4"}, term),
    do: {:noreply, open_modal(term, :centered, true)}

  def handle_event(_, %{"key" => "5"}, term),
    do: {:noreply, open_modal(term, :wide, true)}

  def handle_event(_, %{"key" => "6"}, term),
    do: {:noreply, open_modal(term, :inset, true)}

  def handle_event(
        _,
        %{"key" => "7"},
        %{assigns: %{show_modal: true, modal_variant: :spotlight}} = term
      ),
      do: {:noreply, assign(term, show_modal: false)}

  def handle_event(_, %{"key" => "7"}, term),
    do: {:noreply, open_modal(term, :spotlight, false)}

  def handle_event(_, %{"key" => key}, %{assigns: %{show_modal: false}} = term)
      when key in ["Enter", "m"] and term.focused == "open-modal" do
    {:noreply, open_modal(term, :centered, false)}
  end

  def handle_event(_, %{"key" => key}, %{assigns: %{show_modal: false}} = term)
      when key in ["Enter", "m"] and term.focused == "open-wide-modal" do
    {:noreply, open_modal(term, :wide, false)}
  end

  def handle_event(_, %{"key" => key}, %{assigns: %{show_modal: false}} = term)
      when key in ["Enter", "m"] and term.focused == "open-inset-modal" do
    {:noreply, open_modal(term, :inset, false)}
  end

  def handle_event(_, %{"key" => key}, %{assigns: %{show_modal: false}} = term)
      when key in ["Enter", "m"] and term.focused == "open-dim-modal" do
    {:noreply, open_modal(term, :centered, true)}
  end

  def handle_event(_, %{"key" => key}, %{assigns: %{show_modal: false}} = term)
      when key in ["Enter", "m"] and term.focused == "open-dim-wide-modal" do
    {:noreply, open_modal(term, :wide, true)}
  end

  def handle_event(_, %{"key" => key}, %{assigns: %{show_modal: false}} = term)
      when key in ["Enter", "m"] and term.focused == "open-dim-inset-modal" do
    {:noreply, open_modal(term, :inset, true)}
  end

  def handle_event(_, %{"key" => key}, %{assigns: %{show_modal: false}} = term)
      when key in ["Enter", "m"] and term.focused == "spotlight" do
    {:noreply, assign(term, spotlight: !term.assigns.spotlight)}
  end

  def handle_event(_, %{"key" => key}, %{assigns: %{show_modal: false}} = term)
      when key in ["Enter", "m"] and term.focused == "open-screen-dim" do
    {:noreply, open_modal(term, :spotlight, false)}
  end

  def handle_event(_, %{"key" => "m"}, term),
    do: {:noreply, open_modal(term, :centered, false)}

  def handle_event(
        _,
        %{"key" => "Escape"},
        %{assigns: %{show_modal: true, modal_variant: :spotlight}} = term
      ),
      do: {:noreply, assign(term, show_modal: false)}

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

  defp open_modal(term, modal_variant, modal_dim) do
    assign(term, show_modal: true, modal_variant: modal_variant, modal_dim: modal_dim)
  end
end

Breeze.Example.run(
  [
    view: ModalExample,
    hide_cursor: true,
    theme: Breeze.Theme.builtin(:gruvbox),
    global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
