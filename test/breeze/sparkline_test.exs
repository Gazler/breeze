defmodule Breeze.SparklineTest do
  use ExUnit.Case, async: true

  defmodule Example do
    use Breeze.View
    import Breeze.Blocks

    def mount(opts, term) do
      {:ok, assign(term, Map.merge(%{values: [], min: nil, max: nil, class: nil}, Map.new(opts)))}
    end

    def handle_event("update", attrs, term), do: {:noreply, assign(term, attrs)}

    def render(assigns) do
      ~H"""
      <.sparkline values={@values} min={@min} max={@max} class={@class}/>
      """
    end
  end

  test "scales signed and fractional values across all eight bars" do
    assert render([-3.5, -2.5, -1.5, -0.5, 0.5, 1.5, 2.5, 3.5]) == "▁▂▃▄▅▆▇█"
    assert render([7, 0, 3, 6]) == "█▁▄▇"
  end

  test "fixed bounds keep charts comparable and clamp outliers" do
    assert render([-10, 0, 10, 20, 40, 70, 90], min: 0, max: 70) == "▁▁▂▃▅██"
    assert render([10, 20], min: 0, max: 70) == "▂▃"
    assert render([40, 40], min: 0, max: 70) == "▅▅"
    assert render([-2, -1], min: 0) == "▁▁"
    assert render([1, 2], max: 0) == "▁▁"
  end

  test "empty and constant data have defined output" do
    assert render([]) == ""
    assert render([0, 0, 0]) == "▁▁▁"
    assert render([42]) == "▁"
  end

  test "layout clips bars instead of wrapping or changing their scale" do
    assert render([0, 1, 2, 3, 4, 5, 6, 7], class: "w-4") == "▁▂▃▄"
  end

  test "changing bounds or values rescales an already rendered chart" do
    session =
      Breeze.Test.start!(Example,
        size: {12, 1},
        start_opts: [values: [20, 30, 40], min: 0, max: 70]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert String.trim(Breeze.Test.render_text!(session)) == "▃▄▅"

    Breeze.Test.event(session, "update", %{max: 140})
    assert String.trim(Breeze.Test.render_text!(session)) == "▂▃▃"

    Breeze.Test.event(session, "update", %{min: 20})
    assert String.trim(Breeze.Test.render_text!(session)) == "▁▂▂"

    Breeze.Test.event(session, "update", %{min: nil, max: nil})
    assert String.trim(Breeze.Test.render_text!(session)) == "▁▅█"

    Breeze.Test.event(session, "update", %{values: [20, 40, 80]})
    assert String.trim(Breeze.Test.render_text!(session)) == "▁▃█"
  end

  test "rejects reversed scale bounds" do
    assert_raise ArgumentError, "sparkline min must be less than or equal to max", fn ->
      render([1, 2], min: 10, max: 0)
    end
  end

  defp render(values, opts \\ []) do
    assigns = Map.merge(%{values: values, min: nil, max: nil, class: nil}, Map.new(opts))
    {_acc, box} = Breeze.Renderer.render(Example, assigns)

    box.content |> BackBreeze.Utils.strip_escape_chars() |> String.trim()
  end
end
