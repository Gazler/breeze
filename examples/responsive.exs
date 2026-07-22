defmodule Responsive do
  use Breeze.View

  def mount(_opts, term), do: {:ok, term}

  def render(assigns) do
    ~H"""
    <box class="w-screen h-screen overflow-hidden bg p-0 sm:p-1 lg:p-2">
      <box class="font-bold text-primary">Operations</box>
      <box class="text-muted">
        {@breeze.terminal.width}×{@breeze.terminal.height} · {@breeze.breakpoint} breakpoint
      </box>
      <box class="md:hidden text-muted">[O] [A] [Q] [N] · q quit</box>
      <box class="hidden md:block text-muted">Overview  Activity  Queue  Nodes · q quit</box>
      <box
        class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-x-0 gap-y-0 sm:gap-x-1 sm:gap-y-1 lg:gap-x-2 w-full sm:pt-1"
      >
        <box
          class="border-none sm:border-square lg:rounded border-primary bg-panel w-full h-2 sm:h-4 overflow-hidden pl-0 pr-0 sm:pl-1 sm:pr-1"
        >
          <box class="font-bold">Overview</box>
          <box class="text-success">Healthy</box>
        </box>
        <box
          class="border-none sm:border-square lg:rounded border-accent bg-panel w-full h-2 sm:h-4 overflow-hidden pl-0 pr-0 sm:pl-1 sm:pr-1"
        >
          <box class="font-bold">Activity</box>
          <box>128 events</box>
        </box>
        <box
          class="border-none sm:border-square lg:rounded border-warning bg-panel w-full h-2 sm:h-4 overflow-hidden pl-0 pr-0 sm:pl-1 sm:pr-1"
        >
          <box class="font-bold">Queue</box>
          <box>7 waiting</box>
        </box>
        <box
          class="border-none sm:border-square lg:rounded border-success bg-panel w-full h-2 sm:h-4 overflow-hidden pl-0 pr-0 sm:pl-1 sm:pr-1"
        >
          <box class="font-bold">Nodes</box>
          <box>12 online</box>
        </box>
      </box>
      <box class="hidden lg:block pt-1 text-muted">
        Wide layout keeps every service visible in a single row.
      </box>
    </box>
    """
  end

  def handle_event(_, _, term), do: {:noreply, term}
  def handle_info(_, term), do: {:noreply, term}
end

Breeze.Example.run(
  [
    view: Responsive,
    global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
