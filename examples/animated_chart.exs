defmodule AnimatedChartExample do
  use Breeze.View

  import Breeze.Blocks
  import Breeze.Chart

  @tick_ms 180
  @sample_limit 54
  @min_line_chart_height 5
  @max_line_chart_height 14

  def mount(_opts, term) do
    Process.send_after(self(), :tick, @tick_ms)

    term =
      term
      |> put_local_keybindings(base_keybindings())
      |> assign(
        frame: 0,
        line_chart_height: 9,
        samples: seed_samples(),
        request_rows: seed_request_rows(),
        show_axis: true
      )

    {:ok, term}
  end

  def render(assigns) do
    latest = List.last(assigns.samples) || 0
    average = average(assigns.samples)

    assigns =
      assign(assigns,
        latest: latest,
        average: average,
        axis_state: if(assigns.show_axis, do: :show, else: :hide),
        sparkline_height: assigns.line_chart_height |> Kernel.-(7) |> max(2) |> min(4),
        bar_chart_height: max(div(assigns.line_chart_height + 1, 2), 4)
      )

    ~H"""
    <box class="grid grid-cols-1 grid-rows-2 width-screen height-screen bg">
      <.panel id="animated-chart" class="width-full height-full bg-panel">
        <:title>Animated Chart</:title>
        <box class="width-full height-full bg-panel overflow-hidden">
          <box class="width-full height-1 bold text-primary bg-panel">Rolling latency</box>
          <box class="width-full height-1 text-muted bg-panel">
            latest={@latest}ms avg={@average}ms samples={length(@samples)} frame={@frame}
          </box>
          <box class="width-full height-1 bg-panel">
          </box>
          <.sparkline
            data={@samples}
            show_axis={@axis_state}
            class={"width-full height-#{@sparkline_height} text-accent bg-panel"}
          >
            <:axis class="text-muted">
            </:axis>
          </.sparkline>
          <.line_chart
            show_axis={@axis_state}
            class={"width-full height-#{@line_chart_height} bg-panel"}
          >
            <:axis class="text-muted">
            </:axis>
            <:x_axis
              title="frame"
              ticks={3}
              format={fn value -> value |> round() |> Integer.to_string() end}
              class="text-muted"
            >
            </:x_axis>
            <:y_axis format={fn value -> "#{round(value)}ms" end} class="text-muted">
            </:y_axis>
            <:dataset name="latency" data={@samples} class="text-success">
            </:dataset>
          </.line_chart>
          <box class="width-full height-1 bg-panel">
          </box>
          <box class="width-full height-1 bold text-primary bg-panel">Requests by class</box>
          <.bar_chart
            data={@request_rows}
            show_axis={@axis_state}
            class={"width-34 height-#{@bar_chart_height} text-accent bg-panel"}
          >
            <:axis class="text-muted">
            </:axis>
          </.bar_chart>
        </box>
      </.panel>
      <box class="height-1 width-full bg-panel overflow-hidden">
        <.keybinding_bar keybindings={@breeze.keybindings}/>
      </box>
    </box>
    """
  end

  def handle_info(:tick, term) do
    Process.send_after(self(), :tick, @tick_ms)

    frame = term.assigns.frame + 1
    next_sample = sample_for(frame)

    samples =
      term.assigns.samples
      |> Kernel.++([next_sample])
      |> Enum.take(-@sample_limit)

    {:noreply,
     assign(term,
       frame: frame,
       samples: samples,
       request_rows: request_rows_for(frame)
     )}
  end

  def handle_info(_, term), do: {:noreply, term}

  def handle_event(_, _, term), do: {:noreply, term}

  defp base_keybindings do
    [
      {"a", "Axes", &toggle_axes/2},
      {"+", "Taller", &increase_chart_height/2},
      {"-", "Shorter", &decrease_chart_height/2},
      {"q", "Quit"}
    ]
  end

  defp toggle_axes(_event, term) do
    {:noreply, assign(term, show_axis: !term.assigns.show_axis)}
  end

  defp increase_chart_height(_event, term), do: adjust_chart_height(term, 1)
  defp decrease_chart_height(_event, term), do: adjust_chart_height(term, -1)

  defp adjust_chart_height(term, delta) do
    height =
      term.assigns.line_chart_height
      |> Kernel.+(delta)
      |> max(@min_line_chart_height)
      |> min(@max_line_chart_height)

    {:noreply, assign(term, line_chart_height: height)}
  end

  defp seed_samples do
    1..@sample_limit
    |> Enum.map(&sample_for/1)
  end

  defp seed_request_rows do
    request_rows_for(0)
  end

  defp sample_for(frame) do
    wave = :math.sin(frame / 4) * 18
    slow_wave = :math.cos(frame / 11) * 9
    spike = if rem(frame, 17) in [0, 1], do: 22, else: 0

    round(48 + wave + slow_wave + spike)
  end

  defp request_rows_for(frame) do
    [
      %{label: "2xx", value: 36 + rem(frame * 3, 18)},
      %{label: "3xx", value: 8 + rem(frame, 9)},
      %{label: "4xx", value: 4 + rem(frame * 2, 7)},
      %{label: "5xx", value: 1 + rem(frame, 4)}
    ]
  end

  defp average([]), do: 0

  defp average(samples) do
    samples
    |> Enum.sum()
    |> Kernel./(length(samples))
    |> round()
  end
end

Breeze.Example.run(
  [
    view: AnimatedChartExample,
    reload: true,
    hide_cursor: true,
    global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
