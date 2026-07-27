defmodule FlashExample do
  use Breeze.View
  import Breeze.Blocks

  @messages %{
    "success" => %{
      kind: :success,
      title: "Saved",
      message: "Draft synced to disk",
      highlight: "success"
    },
    "info" => %{
      kind: :info,
      title: "Queued",
      message: "Background job started",
      highlight: "#6bc2ff"
    },
    "warning" => %{
      kind: :warning,
      title: "Check Input",
      message: "Missing optional metadata",
      highlight: {250, 189, 47}
    },
    "error" => %{
      kind: :error,
      title: "Publish Failed",
      message: "Remote rejected the release please try again later",
      highlight: "error"
    }
  }

  @actions [
    {"success", "Success", "1"},
    {"info", "Info", "2"},
    {"warning", "Warning", "3"},
    {"error", "Error", "4"}
  ]

  @placements ["bottom-right", "bottom-left", "top-right", "top-left"]
  @variants ["default", "square", "rounded"]

  def mount(_opts, term) do
    {:ok,
     term
     |> switch_theme(:gruvbox)
     |> focus("success")
     |> put_local_keybindings(base_keybindings())
     |> clear_flash()
     |> assign(
       next_id: 1,
       last_id: nil,
       placement: "bottom-right",
       variant: "default"
     )}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        actions: @actions,
        flash_count: length(Breeze.Flash.entries(assigns.breeze.flash)),
        queued_count: length(Breeze.Flash.queued_entries(assigns.breeze.flash)),
        placement_label: String.replace(assigns.placement, "-", " "),
        variant_label: assigns.variant
      )

    ~H"""
    <box class="grid grid-cols-1 grid-rows-2 w-screen h-screen bg">
      <box class="w-full h-full pl-2 pt-1">
        <box class="font-bold">Flash Messages</box>
        <box class="text-muted">Enter adds the focused message. 1-4 add directly.</box>
        <box class="text-muted">c clears all, x clears latest, e clears errors.</box>
        <box class="text-muted">p moves the stack, v changes variant.</box>
        <box class="text-muted">F3 cycles theme. Max three show; queued messages wait.</box>
        <box>
        </box>
        <box class="grid grid-cols-4 gap-x-1 w-72">
          <box
            :for={{id, label, key} <- @actions}
            id={id}
            focusable
            class="rounded w-17 h-4 focus:border-primary"
          >
            <box class="font-bold text-center">{label}</box>
            <box class="text-center text-muted">{key}</box>
          </box>
        </box>
        <box>
        </box>
        <box class="rounded w-50 h-10">
          <box class="font-bold">State</box>
          <box>Visible: {@flash_count}</box>
          <box>Queued: {@queued_count}</box>
          <box>Latest id: {inspect(@last_id)}</box>
          <box>Placement: {@placement_label}</box>
          <box>Variant: {@variant_label}</box>
          <box>Theme: {@breeze.theme.name}</box>
        </box>
        <.flash_group
          flash={@breeze.flash}
          placement={@placement}
          variant={@variant}
          width={36}
          offset={1}
        />
      </box>
      <box class="h-1 w-full bg-panel overflow-hidden">
        <.keybinding_bar
          keybindings={@breeze.keybindings}
          class="inline w-full overflow-hidden pl-1"
        />
      </box>
    </box>
    """
  end

  def handle_event(_, %{"key" => key}, term) when key in ["1", "2", "3", "4"] do
    action =
      @actions
      |> Enum.find(fn {_id, _label, action_key} -> action_key == key end)
      |> elem(0)

    {:noreply, push_flash(term, action)}
  end

  def handle_event(_, %{"key" => "Enter"}, %{focused: focused} = term) do
    if Map.has_key?(@messages, focused) do
      {:noreply, push_flash(term, focused)}
    else
      {:noreply, term}
    end
  end

  def handle_event(_, %{"key" => "c"}, term),
    do: {:noreply, clear_flash(assign(term, last_id: nil))}

  def handle_event(_, %{"key" => "e"}, term), do: {:noreply, clear_flash(term, :error)}

  def handle_event(_, %{"key" => "x"}, %{assigns: %{last_id: id}} = term) when not is_nil(id) do
    {:noreply, term |> clear_flash(id) |> assign(last_id: nil)}
  end

  def handle_event(_, %{"key" => "p"}, term) do
    {:noreply, assign(term, placement: next_placement(term.assigns.placement))}
  end

  def handle_event(_, %{"key" => "v"}, term) do
    {:noreply, assign(term, variant: next_variant(term.assigns.variant))}
  end

  def handle_event(_, %{"key" => "q"}, term), do: {:stop, term}
  def handle_event(_, _, term), do: {:noreply, term}
  def handle_info(_, term), do: {:noreply, term}

  defp push_flash(term, action) do
    message = Map.fetch!(@messages, action)
    id = "flash-#{term.assigns.next_id}"

    term
    |> put_flash(message.kind, message.message,
      id: id,
      title: "#{message.title} ##{term.assigns.next_id}",
      highlight: message.highlight,
      max: 3,
      duration: 5_000
    )
    |> assign(next_id: term.assigns.next_id + 1, last_id: id)
  end

  defp next_placement(current) do
    index = Enum.find_index(@placements, &(&1 == current)) || 0
    Enum.at(@placements, rem(index + 1, length(@placements)))
  end

  defp next_variant(current) do
    index = Enum.find_index(@variants, &(&1 == current)) || 0
    Enum.at(@variants, rem(index + 1, length(@variants)))
  end

  defp base_keybindings do
    [
      {"Enter", "Add"},
      {"1-4", "Push"},
      {"c", "All"},
      {"x", "Last"},
      {"e", "Err"},
      {"p", "Place"},
      {"v", "Shape"},
      {"F3", "Theme"},
      {"q", "Quit"}
    ]
  end
end

Breeze.Example.run(
  [
    view: FlashExample,
    theme: Breeze.Theme.builtin(:gruvbox),
    hide_cursor: true,
    mouse: false,
    reload: true,
    global_keybindings: [
      {"F3", "Theme", &Breeze.View.cycle_theme/2},
      {"q", "Quit", fn _event, term -> {:stop, term} end}
    ]
  ],
  keep_alive: :infinity
)
