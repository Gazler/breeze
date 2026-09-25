defmodule Breeze.Storybook.Stories.Blocks.BarChartStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "bar-chart",
      title: "Chart (Bar)",
      description: "Compare input and output tokens across three runs.",
      variants: [
        %{
          id: "grouped",
          label: "Grouped",
          description: "Compare each run's input and output tokens as separate bars.",
          notes: [
            "All series share a zero baseline and the largest individual value sets the scale.",
            "Switch to Stacked to compare totals using the same data.",
            "Toggle Horizontal bars to put categories on Y and values on X."
          ],
          source:
            ~s|<.bar_chart data={@data} series={@series} width={44} height={10} mode={:grouped} orientation={@orientation} />|
        },
        %{
          id: "stacked",
          label: "Stacked",
          description: "Compare each run's total tokens with input and output segments.",
          notes: [
            "The largest category total sets the scale. Colors identify each series.",
            "Segment boundaries round to whole cells. Tiny segments may disappear.",
            "Toggle Horizontal bars to put categories on Y and values on X."
          ],
          source:
            ~s|<.bar_chart data={@data} series={@series} width={44} height={10} mode={:stacked} orientation={@orientation} />|
        }
      ],
      notes: [
        "Both variants use the same data rows and series keys. Colors are assigned automatically.",
        "Categories sit on the X axis and token counts on the Y axis.",
        "Grouped bars share a scale. Stacked bars scale against the largest total.",
        "Each data row has x and nonnegative values keyed by the series key.",
        "Scroll the preview on smaller terminals."
      ],
      source:
        ~s|<.bar_chart data={@data} series={@series} width={44} height={10} orientation={@orientation} />|
    }
  end

  def mount(_opts, term) do
    {:ok,
     term
     |> assign(
       horizontal: false,
       series: [
         %{key: :input, name: "Input"},
         %{key: :output, name: "Output"}
       ],
       data: [
         %{x: "Run A", values: %{input: 420, output: 180}},
         %{x: "Run B", values: %{input: 610, output: 240}},
         %{x: "Run C", values: %{input: 350, output: 210}}
       ]
     )
     |> focus("storybook-bar-chart-orientation")}
  end

  def render(assigns) do
    mode = if assigns[:__breeze_story_variant__] == "stacked", do: :stacked, else: :grouped

    assigns =
      assign(assigns,
        mode: mode,
        orientation: if(assigns.horizontal, do: :horizontal, else: :vertical)
      )

    ~H"""
    <.scroll id="storybook-bar-chart-scroll" class="w-full h-full bg-panel">
      <.checkbox
        id="storybook-bar-chart-orientation"
        checked={@horizontal}
        br-change="storybook_bar_orientation_changed"
      >
        Horizontal bars
      </.checkbox>
      <box class="pt-1">
        <.bar_chart
          data={@data}
          series={@series}
          width={44}
          height={10}
          mode={@mode}
          orientation={@orientation}
        />
      </box>
    </.scroll>
    """
  end

  def handle_event("storybook_bar_orientation_changed", %{value: value}, term) do
    {:noreply, assign(term, horizontal: value)}
  end

  def handle_event(_, _, term), do: {:noreply, term}
end
