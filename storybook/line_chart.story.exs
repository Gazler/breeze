defmodule Breeze.Storybook.Stories.Blocks.LineChartStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "line-chart",
      title: "Chart (Line)",
      description: "Latency (Y, ms) over elapsed time (X, seconds).",
      notes: [
        "Each data row has numeric x and values keyed by the series key.",
        "Series have a key and name. Colors are assigned automatically unless supplied.",
        "Toggle the checkbox to switch between automatic and fixed bounds.",
        "Braille dots share one color per terminal cell. Later series win at crossings.",
        "Width and height include the axes and legend. Scroll the preview on smaller terminals."
      ],
      source:
        ~s|<.line_chart data={@data} series={@series} width={44} height={10} min={@min} max={@max} />|
    }
  end

  def mount(_opts, term) do
    {:ok,
     term
     |> assign(
       fixed_scale: false,
       series: [
         %{key: :baseline, name: "Baseline"},
         %{key: :candidate, name: "Candidate"}
       ],
       data: [
         %{x: 0, values: %{baseline: 140, candidate: 180}},
         %{x: 1, values: %{baseline: 190, candidate: 150}},
         %{x: 2, values: %{baseline: 160, candidate: 170}},
         %{x: 3, values: %{baseline: 240, candidate: 160}},
         %{x: 4, values: %{baseline: 200, candidate: 130}},
         %{x: 5, values: %{baseline: 180, candidate: 150}},
         %{x: 6, values: %{baseline: 220, candidate: 120}}
       ]
     )
     |> focus("storybook-line-chart-scale")}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        min: if(assigns.fixed_scale, do: 0, else: nil),
        max: if(assigns.fixed_scale, do: 300, else: nil)
      )

    ~H"""
    <.scroll id="storybook-line-chart-scroll" class="w-full h-full bg-panel">
      <.checkbox
        id="storybook-line-chart-scale"
        checked={@fixed_scale}
        br-change="storybook_chart_scale_changed"
      >
        Fixed scale: 0–300 ms
      </.checkbox>
      <box class="pt-1">
        <.line_chart data={@data} series={@series} width={44} height={10} min={@min} max={@max}/>
      </box>
    </.scroll>
    """
  end

  def handle_event("storybook_chart_scale_changed", %{value: value}, term) do
    {:noreply, assign(term, fixed_scale: value)}
  end

  def handle_event(_, _, term), do: {:noreply, term}
end
