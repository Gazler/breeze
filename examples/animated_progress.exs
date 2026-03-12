defmodule AnimatedProgressBar do
  use Breeze.View

  def mount(opts, term) do
    width = Keyword.get(opts, :width, 24)
    label = Keyword.get(opts, :label, "Animated progress")
    interval = Keyword.get(opts, :interval, 60)
    send(self(), :tick)
    {:ok, assign(term, value: 0, width: width, direction: 1, interval: interval, label: label)}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        filled: String.duplicate("=", assigns.value),
        empty: String.duplicate(" ", assigns.width - assigns.value)
      )

    ~H"""
    <box id="progress" focusable style="border-rounded width-30 height-5 focus:border-4">
      <box style="bold">{@label}</box>
      <box>[{@filled}{@empty}]</box>
      <box>{@value}/{@width}</box>
    </box>
    """
  end

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(:tick, term) do
    Process.send_after(self(), :tick, term.assigns.interval)

    next_value = term.assigns.value + term.assigns.direction

    {value, direction} =
      cond do
        next_value >= term.assigns.width -> {term.assigns.width, -1}
        next_value <= 0 -> {0, 1}
        true -> {next_value, term.assigns.direction}
      end

    {:noreply, assign(term, value: value, direction: direction)}
  end

  def handle_info(_, term), do: {:noreply, term}
end

defmodule AnimatedProgressExample do
  use Breeze.View

  def mount(_opts, term), do: {:ok, term}

  def render(assigns) do
    ~H"""
    <box style="width-screen height-screen">
      <box style="bold">Animated child views</box>
      <box>Each progress bar below is a separate child view with its own tick interval.</box>
      <box>Press tab to focus them. Press q to quit.</box>
      <box style="height-1">
      </box>
      <box style="inline">
        <live
          id="progress_slow"
          view={AnimatedProgressBar}
          start_opts={[label: "Slow", width: 20, interval: 140]}
        >
        </live>
        <box style="width-2">
        </box>
        <live
          id="progress_medium"
          view={AnimatedProgressBar}
          start_opts={[label: "Medium", width: 16, interval: 85]}
        >
        </live>
        <box style="width-2">
        </box>
        <live
          id="progress_fast"
          view={AnimatedProgressBar}
          start_opts={[label: "Fast", width: 12, interval: 45]}
        >
        </live>
      </box>
    </box>
    """
  end

  def handle_event(_, _, term), do: {:noreply, term}
  def handle_info(_, term), do: {:noreply, term}
end

Breeze.Example.run(
  [
    view: AnimatedProgressExample,
    hide_cursor: true,
    global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
