defmodule Breeze.LineChartTest do
  use ExUnit.Case, async: true

  alias Breeze.Charts.Line

  defmodule ChartView do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <.line_chart data={@data} series={@series} width={@width} height={@height} min={@min} max={@max}/>
      """
    end
  end

  @series [%{key: :latency, name: "Latency"}]

  defp data(points), do: Enum.map(points, fn {x, y} -> %{x: x, values: %{latency: y}} end)
  defp text(spans), do: Enum.map_join(spans, & &1.text)

  defp dots(spans) do
    Enum.filter(spans, fn span ->
      case String.to_charlist(span.text) do
        [code] -> code > 0x2800 and code <= 0x28FF
        _ -> false
      end
    end)
  end

  test "clips crossing lines in data space instead of clamping endpoints" do
    bounds = [x_min: 0, x_max: 10, min: 0, max: 10]
    crossing = Line.render(data([{-10, -10}, {20, 20}]), @series, 20, 8, bounds)
    clipped = Line.render(data([{0, 0}, {10, 10}]), @series, 20, 8, bounds)
    assert crossing == clipped

    entering = Line.render(data([{0, -10}, {10, 10}]), @series, 20, 8, bounds)
    correct = Line.render(data([{5, 0}, {10, 10}]), @series, 20, 8, bounds)
    assert entering == correct
    refute dots(entering) == dots(crossing)
  end

  test "keeps in-bounds singletons, omits outside points and handles empty domains" do
    bounds = [x_min: 0, x_max: 10, min: 0, max: 10]
    assert [_] = dots(Line.render(data([{5, 5}]), @series, 20, 8, bounds))
    assert [] = dots(Line.render(data([{5, 20}]), @series, 20, 8, bounds))
    assert [] = dots(Line.render(data([]), @series, 20, 8, []))
    assert [_] = dots(Line.render(data([{3, 9}]), @series, 20, 8, []))
    assert dots(Line.render(data([{0, 9}, {1, 9}]), @series, 20, 8, [])) != []
  end

  test "clipping preserves the plot when x values are nanosecond timestamps" do
    points = [{0, -5}, {200, 15}]
    offset = 1_000_000_000_000_000_000
    timestamps = Enum.map(points, fn {x, y} -> {x + offset, y} end)

    plot = fn points ->
      Line.render(data(points), @series, 50, 8, min: 0, max: 10)
      |> text()
      |> String.split("\n")
      |> Enum.take(5)
    end

    assert plot.(points) == plot.(timestamps)
  end

  test "compound emoji categories and legends stay bounded without splitting graphemes" do
    emoji = "\u{1F469}\u{200D}\u{1F4BB}"
    rows = [%{x: emoji, values: %{latency: 1}}]
    series = [%{key: :latency, name: emoji}]

    for width <- 1..12 do
      content = Line.render(rows, series, width, 8, []) |> text()

      assert Enum.all?(
               String.split(content, "\n"),
               &(BackBreeze.Utils.string_length(&1) <= width)
             )

      remainder = String.replace(content, emoji, "")
      refute String.contains?(remainder, String.codepoints(emoji))
    end

    content = Line.render(rows, series, 12, 8, []) |> text()
    assert length(Regex.scan(~r/#{emoji}/u, content)) == 2
  end

  test "merges Braille masks and gives the last series the shared cell color" do
    bounds = [x_min: 0, x_max: 10, min: 0, max: 10]
    data = [%{x: 5, values: %{a: 5, b: 5.1}}]
    first = %{key: :a, name: "A", color: 6}
    second = %{key: :b, name: "B", color: 5}
    [a] = dots(Line.render(data, [first], 20, 8, bounds))
    [b] = dots(Line.render(data, [second], 20, 8, bounds))
    [merged] = dots(Line.render(data, [first, second], 20, 8, bounds))
    [a_code] = String.to_charlist(a.text)
    [b_code] = String.to_charlist(b.text)

    assert String.to_charlist(merged.text) == [
             0x2800 + Bitwise.bor(a_code - 0x2800, b_code - 0x2800)
           ]

    assert merged.style.foreground_color == 5
  end

  test "dimensions bound the output including wide legend labels and tiny plots" do
    for width <- [1, 2, 7, 30], height <- [1, 3, 7] do
      content =
        Line.render(
          data([{0, 1000}, {1, 2000}]),
          [%{key: :latency, name: "待機時間"}],
          width,
          height,
          []
        )

      rows = content |> text() |> String.split("\n")
      assert length(rows) == height
      assert Enum.all?(rows, &(BackBreeze.Utils.string_length(&1) <= width))
    end
  end

  test "small nonzero domains keep distinct numeric axis labels" do
    content = Line.render(data([{0.001, 0.001}, {0.004, 0.004}]), @series, 30, 8, []) |> text()
    assert content =~ "0.001"
    assert content =~ "0.004"
    refute content =~ "0.0 │"
  end

  test "line and bar charts accept the same keyed category data and optional colors" do
    data = [
      %{x: "Run A", values: %{input: 4, output: 2}},
      %{x: "Run B", values: %{input: 6, output: 3}}
    ]

    series = [%{key: :input, name: "Input"}, %{key: :output, name: "Output"}]
    line = Line.render(data, series, 30, 8, [])
    bar = Breeze.Charts.Bar.render_vertical(data, series, 30, 8, :grouped, nil)

    for content <- [line, bar] do
      assert text(content) =~ "Run A"
      assert text(content) =~ "Run B"
      assert Enum.any?(content, &(&1.style == %{foreground_color: 6}))
      assert Enum.any?(content, &(&1.style == %{foreground_color: 5}))
    end

    singleton = Line.render(Enum.take(data, 1), series, 30, 8, [])
    assert length(Regex.scan(~r/Run A/, text(singleton))) == 1

    assert_raise ArgumentError, ~r/x bounds require numeric/, fn ->
      Line.render(data, series, 30, 8, x_min: 0)
    end
  end

  test "rejects reversed bounds and unsorted points while accepting vertical segments" do
    assert_raise ArgumentError, ~r/minimum/, fn ->
      Line.render([], @series, 20, 8, min: 10, max: 0)
    end

    assert_raise ArgumentError, ~r/nondecreasing/, fn ->
      Line.render(data([{1, 2}, {0, 3}]), @series, 20, 8, [])
    end

    assert dots(Line.render(data([{1, 2}, {1, 3}]), @series, 20, 8, [])) != []
  end

  test "public block reprojects data when bounds or dimensions change" do
    assigns = %{
      data: data([{0, 0}, {1, 10}]),
      series: @series,
      width: 24,
      height: 8,
      min: 0,
      max: 10
    }

    terminal = %Termite.Terminal{size: %{width: 40, height: 20}}
    {_, first} = Breeze.Renderer.render(ChartView, assigns, terminal: terminal)
    {_, rescaled} = Breeze.Renderer.render(ChartView, %{assigns | max: 20}, terminal: terminal)

    {_, resized} =
      Breeze.Renderer.render(ChartView, %{assigns | width: 30, height: 10}, terminal: terminal)

    assert {first.width, first.height} == {24, 8}
    assert {resized.width, resized.height} == {30, 10}
    refute first.content == rescaled.content
    assert BackBreeze.Utils.strip_escape_chars(rescaled.content) =~ "20"
    assert first.content =~ "\e["
  end
end
