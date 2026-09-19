defmodule Breeze.BarChartTest do
  use ExUnit.Case, async: true

  alias Breeze.Charts.{Bar, Data}

  @series [%{key: :a, name: "A", color: 2}, %{key: :b, name: "B", color: 4}]

  defmodule ChartView do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <.bar_chart data={@data} series={@series} width={24} height={8} orientation={@orientation}/>
      """
    end
  end

  test "public block switches orientation and preserves explicit vertical dimensions when empty" do
    assigns = %{
      data: [%{x: "Run", values: %{input: 10}}],
      series: [%{key: :input, name: "Input"}],
      orientation: :vertical
    }

    terminal = %Termite.Terminal{size: %{width: 30, height: 20}}
    {_, vertical} = Breeze.Renderer.render(ChartView, assigns, terminal: terminal)

    {_, horizontal} =
      Breeze.Renderer.render(ChartView, %{assigns | orientation: :horizontal}, terminal: terminal)

    {_, empty} =
      Breeze.Renderer.render(ChartView, %{assigns | data: [], series: []}, terminal: terminal)

    assert {vertical.width, vertical.height} == {24, 8}
    assert {empty.width, empty.height} == {24, 8}
    assert vertical.content =~ "└"
    refute horizontal.content =~ "└"
    assert {horizontal.width, horizontal.height} == {24, 3}
  end

  test "grouped bars share a scale while stacked bars scale category totals" do
    data = [%{x: "X", values: %{a: 2, b: 2}}, %{x: "Y", values: %{a: 4, b: 4}}]

    assert lines(Bar.render(data, @series, 20, :grouped, nil)) == [
             "■ A  ■ B",
             "",
             "X / A ██████       2",
             "X / B ██████       2",
             "",
             "Y / A ████████████ 4",
             "Y / B ████████████ 4"
           ]

    stacked = Bar.render(data, @series, 12, :stacked, nil)
    assert lines(stacked) == ["■ A  ■ B", "", "X ████     4", "Y ████████ 8"]
    assert Enum.any?(stacked, &(&1.text == "████" and &1.style == %{foreground_color: 2}))
    assert Enum.any?(stacked, &(&1.text == "████" and &1.style == %{foreground_color: 4}))
  end

  test "fractional grouped bars keep a fixed scale and clamp outliers" do
    data = [
      %{x: "X", values: %{a: 0.25}},
      %{x: "Y", values: %{a: 10}},
      %{x: "Z", values: %{a: 0}}
    ]

    assert lines(Bar.render(data, [%{key: :a, name: "A"}], 20, :grouped, 2)) == [
             "■ A",
             "",
             "X / A █▏        0.25",
             "",
             "Y / A █████████ 10  ",
             "",
             "Z / A           0   "
           ]
  end

  test "stack rounding uses cumulative boundaries and never allocates cells to zero segments" do
    series = @series ++ [%{key: :c, name: "C", color: 6}, %{key: :d, name: "D", color: 8}]
    data = [%{x: "X", values: %{a: 1, b: 0, c: 1, d: 1}}]
    spans = Bar.render(data, series, 2, :stacked, nil)
    assert List.last(lines(spans)) == "██"
    assert List.last(spans).text == "█"
    refute Enum.any?(spans, &(&1.text =~ "█" and &1.style == %{foreground_color: 4}))
    clipped = Bar.render(data, series, 2, :stacked, 1)
    assert List.last(lines(clipped)) == "██"
    assert Enum.any?(clipped, &(&1.text == "██" and &1.style == %{foreground_color: 2}))
    refute Enum.any?(clipped, &(&1.text =~ "█" and &1.style == %{foreground_color: 6}))
  end

  test "unicode labels and wrapped legends stay within narrow widths" do
    data = [%{x: "カテゴリ", values: %{a: 100, b: 30}}]
    series = [%{key: :a, name: "長い名前"}, %{key: :b, name: "Other"}]

    for width <- 1..20, mode <- [:grouped, :stacked] do
      assert Bar.render(data, series, width, mode, nil)
             |> lines()
             |> Enum.all?(&(BackBreeze.Utils.string_length(&1) <= width))
    end
  end

  test "compound emoji categories and legends stay whole and fit both orientations" do
    for {category, name} <- [{"👩‍💻", "A"}, {"X", "👩‍💻"}], mode <- [:grouped, :stacked] do
      data = [%{x: category, values: %{a: 1}}]
      series = [%{key: :a, name: name}]

      for width <- 1..20 do
        for spans <- [
              Bar.render(data, series, width, mode, nil),
              Bar.render_vertical(data, series, width, 8, mode, nil)
            ] do
          assert Enum.all?(lines(spans), &(BackBreeze.Utils.string_length(&1) <= width))

          for grapheme <- spans |> Enum.map_join(& &1.text) |> String.graphemes() do
            refute grapheme in ["👩", "💻", "‍"]
          end
        end
      end

      for spans <- [
            Bar.render(data, series, 60, mode, nil),
            Bar.render_vertical(data, series, 60, 8, mode, nil)
          ] do
        rows = lines(spans)
        assert Enum.any?(rows, &String.contains?(&1, "■ " <> name))
        assert Enum.any?(rows, &String.contains?(&1, category))
      end
    end
  end

  test "empty data and all-zero bars do not invent magnitude" do
    assert Bar.render([], [], 12, :grouped, nil) == []
    assert Bar.render([], @series, 12, :stacked, nil) == []

    for mode <- [:grouped, :stacked] do
      result = Bar.render([%{x: "X", values: %{a: 0}}], [%{key: :a, name: "A"}], 12, mode, nil)
      refute Enum.any?(result, &String.contains?(&1.text, "█"))
      assert result |> lines() |> List.last() |> String.ends_with?("0")
    end
  end

  test "automatic scales preserve fractional data below one" do
    data = [%{x: "X", values: %{a: 0.1}}, %{x: "Y", values: %{a: 0.2}}]

    for mode <- [:grouped, :stacked] do
      bars =
        Bar.render(data, [%{key: :a, name: "A"}], 4, mode, nil)
        |> Enum.filter(&String.contains?(&1.text, "█"))
        |> Enum.map(& &1.text)

      assert bars == ["██", "████"]
    end
  end

  test "shared data selects values by key in data and series order with optional colors" do
    data = [
      %{x: "Y", values: %{:a => 4, "b" => -2, :unused => "ignored"}},
      %{x: "X", values: %{:a => 2, "b" => 3}}
    ]

    series = [%{key: "b", name: "B"}, %{key: :a, name: "A", color: {10, 20, 30}}]

    assert {["Y", "X"],
            [
              %{key: "b", name: "B", color: 6, values: [-2, 3]},
              %{key: :a, name: "A", color: {10, 20, 30}, values: [4, 2]}
            ]} = Data.prepare(data, series)

    assert {["X", "Y"],
            [
              %{key: :a, values: [2, 4], color: {10, 20, 30}},
              %{key: "b", values: [3, -2], color: 5}
            ]} = Data.prepare(Enum.reverse(data), Enum.reverse(series))

    positive = [%{x: 2, values: %{a: 4, b: 2}}, %{x: 1, values: %{a: 2, b: 1}}]
    bars = Bar.render(positive, Enum.reverse(@series), 20, :grouped, nil) |> lines()
    assert Enum.at(bars, 2) == "2 / B ██████       2"
    assert Enum.at(bars, 3) == "2 / A ████████████ 4"
    assert Enum.at(bars, 5) == "1 / B ███          1"
  end

  test "invalid keyed data fails instead of dropping or misaligning series" do
    for data <- [[%{x: "X", values: %{a: 1}}], [%{x: "X", values: %{a: 1, b: "bad"}}]] do
      assert_raise ArgumentError, fn -> Data.prepare(data, @series) end
    end

    assert_raise ArgumentError, ~r/unique/, fn -> Data.prepare([], @series ++ @series) end

    assert_raise ArgumentError, ~r/all numbers or all single-line strings/, fn ->
      Data.prepare([%{x: 1, values: %{}}, %{x: "X", values: %{}}], [])
    end

    assert_raise ArgumentError, ~r/single-line strings/, fn ->
      Data.prepare([%{x: "X\nY", values: %{}}], [])
    end

    assert_raise ArgumentError, ~r/nonnegative numbers/, fn ->
      Bar.render([%{x: "X", values: %{a: -1}}], [%{key: :a, name: "A"}], 12, :stacked, nil)
    end

    assert_raise ArgumentError, ~r/max must be a positive number/, fn ->
      Bar.render([], [], 12, :grouped, 0)
    end

    assert_raise ArgumentError, ~r/width must be a positive integer/, fn ->
      Bar.render([], [], 0, :grouped, nil)
    end
  end

  test "vertical grouped bars put categories on X and share the largest individual Y value" do
    data = [%{x: "X", values: %{a: 2, b: 1}}, %{x: "Y", values: %{a: 4, b: 4}}]

    assert lines(Bar.render_vertical(data, @series, 12, 7, :grouped, nil)) == [
             "4│      █ █ ",
             " │      █ █ ",
             " │ █    █ █ ",
             " │ █ █  █ █ ",
             "0└──────────",
             "    X    Y  ",
             "■ A  ■ B"
           ]

    stacked = Bar.render_vertical(data, @series, 12, 7, :stacked, nil)

    assert lines(stacked) == [
             "8│     ████ ",
             " │     ████ ",
             " │████ ████ ",
             " │████ ████ ",
             "0└──────────",
             "    X    Y  ",
             "■ A  ■ B"
           ]

    colored_bars = Enum.filter(stacked, &String.contains?(&1.text, "█"))
    assert List.first(colored_bars).style == %{foreground_color: 4}
    assert List.last(colored_bars).style == %{foreground_color: 2}
  end

  test "vertical bars keep fractional top cells and clip stacked segments at a fixed maximum" do
    grouped =
      Bar.render_vertical(
        [%{x: "X", values: %{a: 0.25}}],
        [%{key: :a, name: "A"}],
        8,
        7,
        :grouped,
        4
      )

    assert Enum.any?(grouped, &String.contains?(&1.text, "▂"))
    refute Enum.any?(grouped, &String.contains?(&1.text, "█"))
    data = [%{x: "X", values: %{a: 4, zero: 0, b: 9}}]

    series = [
      %{key: :a, name: "A", color: 2},
      %{key: :zero, name: "Zero", color: 3},
      %{key: :b, name: "B", color: 4}
    ]

    clipped = Bar.render_vertical(data, series, 24, 7, :stacked, 4)
    bars = Enum.filter(clipped, &String.contains?(&1.text, "█"))
    assert bars != []
    assert Enum.all?(bars, &(&1.style == %{foreground_color: 2}))
    stacked = Bar.render_vertical(data, series, 24, 7, :stacked, nil)
    refute Enum.any?(stacked, &(&1.style == %{foreground_color: 3} and &1.text =~ "█"))
  end

  test "vertical Unicode labels and tiny dimensions stay bounded without showing partial groups" do
    series = [%{key: :a, name: "長い名前"}, %{key: :b, name: "Other"}]
    data = [%{x: "検索", values: %{a: 100, b: 30}}, %{x: "処理", values: %{a: 50, b: 20}}]

    for width <- 1..20, height <- 1..12, mode <- [:grouped, :stacked] do
      rows = Bar.render_vertical(data, series, width, height, mode, nil) |> lines()
      assert length(rows) <= height
      assert Enum.all?(rows, &(BackBreeze.Utils.string_length(&1) <= width))
    end

    refute Bar.render_vertical(data, series, 6, 12, :grouped, nil)
           |> Enum.any?(&String.contains?(&1.text, "│"))
  end

  test "vertical empty and zero data stays empty while negative values and invalid heights fail" do
    assert Bar.render_vertical([], [], 12, 7, :stacked, nil) == []
    series = [%{key: :a, name: "A"}]

    for mode <- [:grouped, :stacked] do
      spans = Bar.render_vertical([%{x: "X", values: %{a: 0}}], series, 12, 7, mode, nil)
      refute Enum.any?(spans, &String.contains?(&1.text, "█"))
    end

    assert_raise ArgumentError, ~r/nonnegative numbers/, fn ->
      Bar.render_vertical([%{x: "X", values: %{a: -1}}], series, 12, 7, :stacked, nil)
    end

    assert_raise ArgumentError, ~r/height must be a positive integer/, fn ->
      Bar.render_vertical([], [], 12, 0, :grouped, nil)
    end
  end

  defp lines(spans), do: spans |> Enum.map_join(& &1.text) |> String.split("\n")
end
