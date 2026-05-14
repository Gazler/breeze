defmodule Breeze.Storybook.Stories.Charts.ChartStory do
  use Breeze.Storybook.Story
  import Breeze.Chart

  def story do
    %{
      id: "charts",
      group: "Charts",
      title: "Charts",
      description: "Terminal-native charts rendered through the Breeze.Chart namespace.",
      notes: [
        "Charts render as ordinary Breeze component content.",
        "Large charts can opt into virtual text for scrollable output.",
        "Axis and dataset slots accept the same theme color classes as other Breeze elements.",
        "The namespace is separate from Breeze.Blocks so it can be extracted later."
      ],
      source:
        "<.sparkline data={values} show_axis>\n  <:axis class=\"text-muted\" />\n</.sparkline>\n<.bar_chart data={rows} show_axis>\n  <:axis class=\"text-muted\" />\n</.bar_chart>\n<.line_chart show_axis>\n  <:axis class=\"text-muted\" />\n  <:x_axis title=\"sample\" labels={[\"0\", \"11\"]} class=\"text-muted\" />\n  <:y_axis format={fn value -> \"\#{round(value)}ms\" end} class=\"text-muted\" />\n  <:dataset data={latency} class=\"text-success\" />\n</.line_chart>"
    }
  end

  def render(assigns) do
    sparkline = [2, 8, 4, 12, 9, 16, 13, 19, 11, 24, 18, 28, 21, 31, 27, 35]

    bars = [
      %{label: "2xx", value: 42},
      %{label: "3xx", value: 12},
      %{label: "4xx", value: 8},
      %{label: "5xx", value: 3}
    ]

    latency = [12, 18, 15, 24, 29, 25, 34, 40, 37, 45, 51, 48]
    throughput = [8, 12, 14, 13, 18, 22, 21, 26, 30, 31, 35, 38]

    assigns =
      assign(assigns,
        sparkline: sparkline,
        bars: bars,
        latency: latency,
        throughput: throughput
      )

    ~H"""
    <box class="grid grid-cols-1 grid-rows-3 width-full height-full overflow-hidden bg-panel">
      <box class="width-full height-3 bg-panel">
        <box class="width-full height-1 bold text-primary bg-panel">Sparkline</box>
        <.sparkline data={@sparkline} show_axis class="width-full height-2 text-accent">
          <:axis class="text-muted">
          </:axis>
        </.sparkline>
      </box>
      <box class="width-full height-8 bg-panel">
        <box class="width-full height-1 bold text-primary bg-panel">Bar chart</box>
        <.bar_chart data={@bars} show_axis class="width-28 height-7 text-accent">
          <:axis class="text-muted">
          </:axis>
        </.bar_chart>
      </box>
      <box class="width-full height-full overflow-hidden bg-panel">
        <box class="width-full height-1 bold text-primary bg-panel">Line chart</box>
        <.line_chart show_axis class="width-full height-10">
          <:axis class="text-muted">
          </:axis>
          <:x_axis title="sample" labels={["0", "11"]} class="text-muted">
          </:x_axis>
          <:y_axis format={fn value -> "#{round(value)}ms" end} class="text-muted">
          </:y_axis>
          <:dataset name="latency" data={@latency} class="text-success">
          </:dataset>
          <:dataset name="throughput" data={@throughput} marker="+" class="text-primary">
          </:dataset>
        </.line_chart>
      </box>
    </box>
    """
  end
end
