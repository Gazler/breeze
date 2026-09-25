defmodule Breeze.Storybook.Stories.Blocks.SparklineStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "sparkline",
      title: "Sparkline",
      description: "Compact numeric history with one bar per value.",
      notes: [
        "The smallest value maps to ▁ and the largest to █.",
        "Set min and max to keep related charts on the same scale.",
        "Each value takes one column. A narrower class clips without resampling."
      ],
      source: ~S(<.sparkline values={[2, 4, 3, 8, 6]} class="text-success" />)
    }
  end

  def render(assigns) do
    ~H"""
    <box class="w-full h-full bg-panel">
      <box class="bold">Automatic scale</box>
      <box class="inline w-full">
        <box class="w-14">Throughput</box>
        <.sparkline values={[12, 18, 14, 24, 32, 28, 42, 36, 48, 40, 52, 44]} class="text-success"/>
      </box>
      <box class="bold pt-1">Shared scale: 0–100%</box>
      <box class="inline w-full">
        <box class="w-14">CPU</box>
        <.sparkline values={[10, 15, 20, 18, 35, 55, 70, 85, 60, 45, 30, 20]} min={0} max={100}/>
      </box>
      <box class="inline w-full">
        <box class="w-14">Memory</box>
        <.sparkline values={~c"(*+-0247:<>A"} min={0} max={100} class="text-accent"/>
      </box>
    </box>
    """
  end
end
