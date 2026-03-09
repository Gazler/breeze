defmodule CounterPanel do
  use Breeze.View

  def mount(opts, term) do
    term =
      term
      |> assign(label: Keyword.fetch!(opts, :label))
      |> assign(count: Keyword.get(opts, :initial, 0))
      |> focus("panel")

    {:ok, term}
  end

  def render(assigns) do
    ~H"""
    <box id="panel" focusable style="border-rounded width-24 height-6 focus:border-4">
      <box style="bold">{@label}</box>
      <box>Count: {@count}</box>
      <box>Up/down changes this panel.</box>
    </box>
    """
  end

  def handle_event(_, %{"key" => "ArrowUp"}, term) do
    {:noreply, assign(term, count: term.assigns.count + 1)}
  end

  def handle_event(_, %{"key" => "ArrowDown"}, term) do
    {:noreply, assign(term, count: term.assigns.count - 1)}
  end

  def handle_event(_, _, term), do: {:noreply, term}
  def handle_info(_, term), do: {:noreply, term}
end

defmodule NestedViewsExample do
  use Breeze.View

  def mount(_opts, term) do
    {:ok, assign(term, show_right: true)}
  end

  def render(assigns) do
    ~H"""
    <box style="width-screen height-screen">
      <box style="bold">Nested views example</box>
      <box>Tab moves focus between child views.</box>
      <box>Arrow up/down updates the focused child view.</box>
      <box>Press "t" to toggle the right view. Press "q" to quit.</box>
      <box style="inline">
        <live id="left" view={CounterPanel} start_opts={[label: "Left panel", initial: 0]}>
        </live>
        <box style="width-2">
        </box>
        <live
          :if={@show_right}
          id="right"
          view={CounterPanel}
          start_opts={[label: "Right panel", initial: 10]}
        >
        </live>
      </box>
    </box>
    """
  end

  def handle_event(_, %{"key" => "t"}, term) do
    {:noreply, assign(term, show_right: !term.assigns.show_right)}
  end

  def handle_event(_, _, term), do: {:noreply, term}
  def handle_info(_, term), do: {:noreply, term}
end

Breeze.Server.start_link(
  view: NestedViewsExample,
  hide_cursor: true,
  global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
)

receive do
end
