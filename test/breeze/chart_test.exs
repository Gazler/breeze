defmodule Breeze.ChartTest do
  use ExUnit.Case, async: true

  alias BackBreeze.TextSpan
  alias Breeze.ChildServer
  alias Breeze.Renderer

  defmodule SparklineView do
    use Breeze.View
    import Breeze.Chart

    def render(assigns) do
      ~H"""
      <.sparkline data={@data} class="width-4"/>
      """
    end
  end

  defmodule SparklineMeanView do
    use Breeze.View
    import Breeze.Chart

    def render(assigns) do
      ~H"""
      <.sparkline data={@data} summary={:mean} class="width-2"/>
      """
    end
  end

  defmodule MissingSparklineView do
    use Breeze.View
    import Breeze.Chart

    def render(assigns) do
      ~H"""
      <.sparkline data={[1, nil, 3]} missing="·" class="width-3"/>
      """
    end
  end

  defmodule BarChartView do
    use Breeze.View
    import Breeze.Chart

    def render(assigns) do
      ~H"""
      <.bar_chart data={@rows} class="width-7 height-4"/>
      """
    end
  end

  defmodule ChartSurfaceView do
    use Breeze.View
    import Breeze.Chart

    def render(assigns) do
      ~H"""
      <box class="bg-panel width-8 height-3">
        <.line_chart series={[%{data: [1, 2]}]} class="width-8 height-3"/>
      </box>
      """
    end
  end

  defmodule SlotStyledChartView do
    use Breeze.View
    import Breeze.Chart

    def render(assigns) do
      ~H"""
      <.line_chart class="width-4 height-3">
        <:axis class="text-muted">
        </:axis>
        <:dataset data={[1, 2]} class="text-success">
        </:dataset>
      </.line_chart>
      """
    end
  end

  defmodule SlotAxisToggleView do
    use Breeze.View
    import Breeze.Chart

    def render(assigns) do
      ~H"""
      <.line_chart show_axis={@axis_state} class="width-4 height-3">
        <:axis class="text-muted">
        </:axis>
        <:dataset data={[1, 2]} class="text-success">
        </:dataset>
      </.line_chart>
      """
    end
  end

  defmodule ScrollChartView do
    use Breeze.View
    import Breeze.Blocks
    import Breeze.Chart

    def mount(_opts, term) do
      {:ok, focus(term, "chart-scroll")}
    end

    def render(assigns) do
      ~H"""
      <.scroll id="chart-scroll" class="width-10 height-4">
        <.line_chart
          series={[%{data: Enum.to_list(1..10)}]}
          virtual
          cache_key={:chart_scroll_test}
          class="width-10 height-10"
        />
      </.scroll>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  test "sparkline buckets values by width" do
    assert SparklineView |> Renderer.render_to_string(%{data: [0, 1, 2, 3]}) |> visible() ==
             "▁▃▆█"
  end

  test "sparkline supports summary functions for bucketed data" do
    assert SparklineMeanView |> Renderer.render_to_string(%{data: [0, 2, 4, 6]}) |> visible() ==
             "▁█"
  end

  test "sparkline renders missing values with the configured symbol" do
    assert MissingSparklineView |> Renderer.render_to_string(%{}) |> visible() == "▁·█"
  end

  test "sparkline can render an attached compact axis" do
    content =
      Breeze.Chart.Sparkline.render(%{
        data: [0, 1, 2],
        class: "width-4 height-2",
        style: nil,
        summary: :max,
        min: nil,
        max: nil,
        missing: " ",
        axis: true,
        axis_color: 8,
        empty: "No data"
      })

    assert plain(content) == "│▁▅█\n└───"
    assert [%TextSpan{text: "│", style: %{foreground_color: 8}} | _] = content
  end

  test "sparkline resolves width-full from its container width" do
    content =
      Breeze.Chart.Sparkline.render(%{
        data: [0, 1, 2],
        class: "width-full height-2",
        style: nil,
        summary: :max,
        min: nil,
        max: nil,
        missing: " ",
        axis: true,
        axis_color: nil,
        empty: "No data"
      })

    output =
      BackBreeze.Style.width(12)
      |> BackBreeze.Style.height(2)
      |> BackBreeze.Style.overflow(:hidden)
      |> BackBreeze.Style.render(content)

    assert output |> String.split("\n") |> hd() |> String.trim_trailing() |> String.length() == 12
    assert output =~ "└───────────"
  end

  test "bar chart renders vertical bars and labels" do
    output =
      Renderer.render_to_string(BarChartView, %{
        rows: [%{label: "A", value: 1}, %{label: "B", value: 2}]
      })

    assert output =~ "A"
    assert output =~ "B"
    assert output =~ "█"
  end

  test "bar chart pads vertical rows so labels stay under their bars" do
    rows = [
      %{label: "2xx", value: 42},
      %{label: "3xx", value: 12},
      %{label: "4xx", value: 8},
      %{label: "5xx", value: 3}
    ]

    lines =
      Breeze.Chart.BarChart.render(%{
        data: rows,
        class: "width-34 height-5",
        style: nil,
        label_key: :label,
        value_key: :value,
        orientation: :vertical,
        min: nil,
        max: nil,
        empty: "No data",
        virtual: false,
        cache_key: nil
      })

    assert Enum.all?(lines, &(String.length(&1) == 34))
    assert List.last(lines) =~ "2xx"
    assert List.last(lines) =~ "3xx"
    refute Enum.at(lines, 3) =~ "2xx"
  end

  test "bar chart can render vertical axes" do
    rows = [
      %{label: "2xx", value: 42},
      %{label: "3xx", value: 12},
      %{label: "4xx", value: 8},
      %{label: "5xx", value: 3}
    ]

    lines =
      Breeze.Chart.BarChart.render(%{
        data: rows,
        class: "width-34 height-5",
        style: nil,
        label_key: :label,
        value_key: :value,
        orientation: :vertical,
        min: nil,
        max: nil,
        missing: :zero,
        axis: true,
        empty: "No data",
        virtual: false,
        cache_key: nil
      })

    assert Enum.all?(lines, &(String.length(&1) == 34))
    assert Enum.take(lines, 3) |> Enum.all?(&String.starts_with?(&1, "│"))
    assert Enum.at(lines, 3) == "└─────────────────────────────────"
    assert List.last(lines) =~ "2xx"
  end

  test "bar chart resolves width-full from its container width" do
    content =
      Breeze.Chart.BarChart.render(%{
        data: [%{label: "2xx", value: 42}, %{label: "5xx", value: 3}],
        class: "width-full height-4",
        style: nil,
        label_key: :label,
        value_key: :value,
        orientation: :vertical,
        min: nil,
        max: nil,
        missing: :zero,
        axis: true,
        empty: "No data",
        virtual: false,
        cache_key: nil
      })

    output =
      BackBreeze.Style.width(18)
      |> BackBreeze.Style.height(4)
      |> BackBreeze.Style.overflow(:hidden)
      |> BackBreeze.Style.render(content)

    assert output =~ "└─────────────────"
  end

  test "bar chart can style axes separately from chart content" do
    content =
      Breeze.Chart.BarChart.render(%{
        data: [%{label: "A", value: 2}, %{label: "B", value: 1}],
        class: "width-8 height-4",
        style: nil,
        label_key: :label,
        value_key: :value,
        orientation: :vertical,
        min: nil,
        max: nil,
        missing: :zero,
        axis: true,
        axis_color: 8,
        empty: "No data",
        virtual: false,
        cache_key: nil
      })

    assert plain(content) =~ "└───────"

    assert Enum.any?(
             content,
             &match?(%TextSpan{text: "└───────", style: %{foreground_color: 8}}, &1)
           )
  end

  test "charts render blank cells on a panel surface" do
    output = Renderer.render_to_string(ChartSurfaceView, %{}, theme: true)

    assert output =~ "\e[48;"
  end

  test "line chart returns styled text spans when series styles are provided" do
    content =
      Breeze.Chart.LineChart.render(%{
        series: [%{data: [1], style: %{foreground_color: 2}}],
        class: "width-1 height-1",
        style: nil,
        x_bounds: :auto,
        y_bounds: :auto,
        axis: false,
        empty: "No data",
        virtual: false,
        cache_key: nil
      })

    assert [%TextSpan{} = span] = content
    assert span.text == "•"
    assert span.style.foreground_color == 2
  end

  test "line chart can render axes" do
    content =
      Breeze.Chart.LineChart.render(%{
        series: [%{data: [1, 2, 3]}],
        class: "width-6 height-4",
        style: nil,
        x_bounds: :auto,
        y_bounds: :auto,
        axis: true,
        empty: "No data",
        virtual: false,
        cache_key: nil
      })

    lines = content |> plain() |> String.split("\n")

    assert length(lines) == 4
    assert Enum.all?(lines, &(String.length(&1) == 6))
    assert Enum.take(lines, 3) |> Enum.all?(&String.starts_with?(&1, "│"))
    assert List.last(lines) == "└─────"
    assert plain(content) =~ "•"
  end

  test "line chart resolves width-full from its container width" do
    content =
      Breeze.Chart.LineChart.render(%{
        series: [%{data: [1, 2, 3]}],
        class: "width-full height-4",
        style: nil,
        x_bounds: :auto,
        y_bounds: :auto,
        axis: true,
        empty: "No data",
        virtual: false,
        cache_key: nil
      })

    output =
      BackBreeze.Style.width(16)
      |> BackBreeze.Style.height(4)
      |> BackBreeze.Style.overflow(:hidden)
      |> BackBreeze.Style.render(content)

    assert output =~ "└───────────────"
  end

  test "line chart can label x and y axes" do
    content =
      Breeze.Chart.LineChart.render(%{
        series: [%{data: [{0, 0}, {10, 100}]}],
        class: "width-22 height-6",
        style: nil,
        x_bounds: :auto,
        y_bounds: :auto,
        x_axis: [%{title: "time", labels: ["0s", "10s"]}],
        y_axis: [%{title: "ms", labels: [{0, "0ms"}, {100, "100ms"}]}],
        empty: "No data",
        virtual: false,
        cache_key: nil
      })

    lines = content |> plain() |> String.split("\n")

    assert length(lines) == 6
    assert Enum.all?(lines, &(String.length(&1) == 22))
    assert Enum.at(lines, 0) =~ "ms 100ms│"
    assert Enum.at(lines, 3) =~ "0ms│"
    assert Enum.at(lines, 4) =~ "└"
    assert Enum.at(lines, 4) =~ "time"
    assert Enum.find_index(String.graphemes(Enum.at(lines, 4)), &(&1 == "t")) == 13
    assert Enum.at(lines, 5) =~ "0s"
    assert Enum.at(lines, 5) =~ "10s"
  end

  test "line chart can generate axis tick labels" do
    content =
      Breeze.Chart.LineChart.render(%{
        series: [%{data: [{0, 0}, {10, 100}]}],
        class: "width-18 height-5",
        style: nil,
        x_bounds: :auto,
        y_bounds: :auto,
        x_axis: [%{ticks: 3, format: fn value -> "#{round(value)}s" end}],
        y_axis: [%{ticks: 2, format: fn value -> "#{round(value)}ms" end}],
        empty: "No data",
        virtual: false,
        cache_key: nil
      })

    plain = plain(content)

    assert plain =~ "0s"
    assert plain =~ "5s"
    assert plain =~ "10s"
    assert plain =~ "0ms"
    assert plain =~ "100ms"
  end

  test "line chart keeps x-axis tick labels separated" do
    content =
      Breeze.Chart.LineChart.render(%{
        series: [%{data: [{0, 0}, {100, 1}]}],
        class: "width-14 height-5",
        style: nil,
        x_bounds: :auto,
        y_bounds: :auto,
        x_axis: [%{ticks: 5, format: fn value -> value |> round() |> Integer.to_string() end}],
        empty: "No data",
        virtual: false,
        cache_key: nil
      })

    label_row = content |> plain() |> String.split("\n") |> List.last()

    label_ranges =
      Regex.scan(~r/\S+/, label_row, return: :index)
      |> List.flatten()

    gaps =
      label_ranges
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [{left_start, left_length}, {right_start, _right_length}] ->
        right_start - (left_start + left_length)
      end)

    assert label_row =~ "0"
    assert label_row =~ "100"
    assert length(label_ranges) >= 2
    assert Enum.all?(gaps, &(&1 >= 2))
  end

  test "line chart defaults axis ticks to auto when an axis slot is present" do
    content =
      Breeze.Chart.LineChart.render(%{
        series: [%{data: [{0, 0}, {10, 100}]}],
        class: "width-18 height-8",
        style: nil,
        x_bounds: :auto,
        y_bounds: :auto,
        y_axis: [%{format: fn value -> "#{round(value)}ms" end}],
        empty: "No data",
        virtual: false,
        cache_key: nil
      })

    plain = plain(content)

    assert plain =~ "100ms│"
    assert plain =~ "50ms│"
    assert plain =~ "0ms│"
  end

  test "line chart auto y-axis ticks leave two blank rows between labels" do
    content =
      Breeze.Chart.LineChart.render(%{
        series: [%{data: [{0, 0}, {10, 100}]}],
        class: "width-18 height-7",
        style: nil,
        x_bounds: :auto,
        y_bounds: :auto,
        y_axis: [
          %{
            ticks: :auto,
            format: fn value -> "#{round(value)}ms" end
          }
        ],
        empty: "No data",
        virtual: false,
        cache_key: nil
      })

    plain = plain(content)

    assert plain =~ "100ms│"
    assert plain =~ "0ms│"
    refute plain =~ "50ms│"
  end

  test "line chart auto y-axis ticks still include first and last labels when compact" do
    content =
      Breeze.Chart.LineChart.render(%{
        series: [%{data: [{0, 0}, {10, 100}]}],
        class: "width-18 height-4",
        style: nil,
        x_bounds: :auto,
        y_bounds: :auto,
        y_axis: [%{format: fn value -> "#{round(value)}ms" end}],
        empty: "No data",
        virtual: false,
        cache_key: nil
      })

    plain = plain(content)

    assert plain =~ "100ms│"
    assert plain =~ "0ms│"
    refute plain =~ "50ms│"
  end

  test "line chart can style axes separately from series" do
    content =
      Breeze.Chart.LineChart.render(%{
        series: [%{data: [1, 2], style: %{foreground_color: 2}}],
        class: "width-4 height-3",
        style: nil,
        x_bounds: :auto,
        y_bounds: :auto,
        axis: true,
        axis_color: 8,
        empty: "No data",
        virtual: false,
        cache_key: nil
      })

    assert Enum.any?(content, &match?(%TextSpan{text: "│", style: %{foreground_color: 8}}, &1))
    assert Enum.any?(content, &match?(%TextSpan{text: "•", style: %{foreground_color: 2}}, &1))
  end

  test "line chart slots resolve theme color classes" do
    theme = Breeze.Theme.new(muted: "#040506", success: "#010203", panel: "#000000")

    content =
      Breeze.Chart.LineChart.render(%{
        series: [],
        dataset: [%{data: [1, 2], class: "text-success"}],
        class: "width-4 height-3",
        style: nil,
        x_bounds: :auto,
        y_bounds: :auto,
        axis: [%{class: "text-muted"}],
        empty: "No data",
        virtual: false,
        cache_key: nil,
        breeze: %{theme: theme}
      })

    assert Enum.any?(
             content,
             &match?(%TextSpan{text: "│", style: %{foreground_color: {4, 5, 6}}}, &1)
           )

    assert Enum.any?(
             content,
             &match?(%TextSpan{text: "•", style: %{foreground_color: {1, 2, 3}}}, &1)
           )
  end

  test "show_axis false hides a styled axis slot" do
    content =
      Breeze.Chart.LineChart.render(%{
        series: [],
        dataset: [%{data: [1, 2], class: "text-success"}],
        class: "width-4 height-3",
        style: nil,
        x_bounds: :auto,
        y_bounds: :auto,
        show_axis: false,
        axis: [%{class: "text-muted"}],
        empty: "No data",
        virtual: false,
        cache_key: nil
      })

    refute plain(content) =~ "│"
    refute plain(content) =~ "└"
    assert plain(content) =~ "•"
  end

  test "show_axis hide state survives component rendering with a styled axis slot" do
    output = Renderer.render_to_string(SlotAxisToggleView, %{axis_state: :hide})

    refute visible(output) =~ "│"
    refute visible(output) =~ "└"
    assert visible(output) =~ "•"
  end

  test "component slots inherit breeze theme context" do
    theme = Breeze.Theme.new(muted: "#040506", success: "#010203", panel: "#000000")

    output =
      Renderer.render_to_string(
        SlotStyledChartView,
        %{breeze: %{theme: theme}},
        theme: theme
      )

    assert output =~ "38;2;4;5;6m│"
    assert output =~ "38;2;1;2;3m•"
  end

  test "virtual line chart can render a deep visible slice" do
    content =
      Breeze.Chart.LineChart.render(%{
        series: [%{data: Enum.to_list(1..10)}],
        class: "width-10 height-10",
        style: nil,
        x_bounds: :auto,
        y_bounds: :auto,
        axis: false,
        empty: "No data",
        virtual: true,
        cache_key: :virtual_line_chart_test
      })

    style =
      BackBreeze.Style.width(10)
      |> BackBreeze.Style.height(2)
      |> BackBreeze.Style.overflow(:hidden)

    output = BackBreeze.Style.render(style, content, offset_top: 8)

    assert output =~ "•"
  end

  test "virtual chart content scrolls through the normal scroll implicit" do
    terminal = %Termite.Terminal{size: %{width: 10, height: 4}}

    {:ok, pid} = ChildServer.start(view: ScrollChartView, terminal: terminal)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

    assert {:ok, _acc, initial_box} = ChildServer.render(pid, terminal: terminal)
    assert initial_box.content =~ "•"

    assert {:noreply, "chart-scroll", true} = ChildServer.dispatch_input(pid, "PageDown")
    assert {:ok, _acc, next_box} = ChildServer.render(pid, terminal: terminal)

    assert next_box.content =~ "•"
    assert next_box.content != initial_box.content
  end

  defp visible(content) do
    String.replace(content, ~r/\e\[[0-9;]*m/u, "")
  end

  defp plain(content) when is_binary(content), do: content

  defp plain(content) when is_list(content) do
    Enum.map_join(content, "", fn
      %TextSpan{text: text} -> text
      text when is_binary(text) -> text
    end)
  end
end
