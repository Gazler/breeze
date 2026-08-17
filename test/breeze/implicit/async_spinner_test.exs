defmodule Breeze.Implicit.AsyncSpinnerTest do
  use ExUnit.Case, async: true

  alias BackBreeze.Box
  alias Breeze.Implicit.AsyncSpinner

  test "init selects dots by default and supports the bars variant" do
    assert {:ok, %{variant: :dots, active?: false},
            [rerender_every: 80, active_when_pending: true]} =
             AsyncSpinner.init([], %{}, %{})

    assert {:ok, %{variant: :bars, active?: false},
            [rerender_every: 120, active_when_pending: true]} =
             AsyncSpinner.init([], %{:"spinner-variant" => "bars"}, %{})

    assert {:ok, %{variant: :dots, active?: true},
            [rerender_every: 80, active_when_pending: false]} =
             AsyncSpinner.init(
               [],
               %{:"spinner-variant" => "dots", :"spinner-active" => true},
               %{}
             )
  end

  test "animate cycles through the selected pending frames and uses a middle dot while idle" do
    context = %{frame: 1, pending?: true, layout: nil}

    assert %Box{content: "/"} =
             AsyncSpinner.animate(:root, %Box{}, [], %{variant: :bars}, context)

    assert %Box{content: "⠙"} =
             AsyncSpinner.animate(:root, %Box{}, [], %{variant: :dots}, context)

    assert %Box{content: "·"} =
             AsyncSpinner.animate(
               :root,
               %Box{},
               [],
               %{variant: :dots, active?: false},
               %{context | pending?: false}
             )

    assert %Box{content: "⠙"} =
             AsyncSpinner.animate(
               :root,
               %Box{},
               [],
               %{variant: :dots, active?: true},
               %{context | pending?: false}
             )
  end

  test "animation overlays carry the spinner background style" do
    box = %Box{
      style: %BackBreeze.Style{width: 1, height: 1, foreground_color: 7, background_color: 0}
    }

    assert {:ok, %Box{content: "·"}, overlays: [%{content: content}]} =
             AsyncSpinner.animate(:root, box, [], %{variant: :dots, active?: true}, %{
               frame: 0,
               pending?: false,
               layout: %Breeze.Viewport{left: 2, top: 3}
             })

    assert content =~ "⠋"
    assert content =~ "48;5;0"
  end
end
