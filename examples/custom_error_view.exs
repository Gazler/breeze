defmodule CrashView do
  use Breeze.View

  def mount(_opts, term) do
    {:ok,
     term
     |> focus("crash")
     |> put_local_keybindings([{"c", "Crash"}])}
  end

  def render(assigns) do
    ~H"""
    <box class="w-screen h-screen">
      <box id="crash" focusable class="rounded w-40 h-5 focus:border-4">
        <box class="font-bold">Custom ErrorView Example</box>
        <box>Press c to crash</box>
      </box>
    </box>
    """
  end

  def handle_event(_, %{"key" => "c"}, _term) do
    raise "custom error view example crashed"
  end

  def handle_event(_, _, term), do: {:noreply, term}
end

defmodule ExampleErrorView do
  use Breeze.View
  import Breeze.Blocks

  def render(assigns) do
    ~H"""
    <box class="rounded w-screen h-screen">
      <box class="font-bold text-1">Custom Error View</box>
      <box>View: {inspect(@view)}</box>
      <box>Kind: {inspect(@kind)}</box>
      <box>Reason: {inspect(@reason)}</box>
      <box>Stacktrace frames: {length(@stacktrace)}</box>
      <box class="h-1">
      </box>
      <box class="h-1 bg-panel overflow-hidden">
        <.keybinding_bar keybindings={@breeze.keybindings}/>
      </box>
    </box>
    """
  end
end

Breeze.Example.run(
  view: CrashView,
  render_errors: [
    view: ExampleErrorView,
    keybindings: [
      {"r", "Restart", :restart},
      {"q", "Quit", :stop},
      {"y", "Copy details", :copy_details}
    ]
  ],
  hide_cursor: true,
  global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
)
