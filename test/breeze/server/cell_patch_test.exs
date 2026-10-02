defmodule Breeze.Server.CellPatchTest do
  use ExUnit.Case, async: true
  alias Breeze.Server.{CellPatch, Frame}

  defmodule ModalView do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <box class="w-screen h-screen bg">
        <box :for={n <- 1..40}>Application row {n}</box>
        <.modal :if={@open} id="dialog" width={40} height={10} dim={true}>
          <:title>Dialog</:title>
          <box>Modal contents</box>
        </.modal>
      </box>
      """
    end
  end

  defp styled(text, foreground, extra \\ "") do
    "\e[48;2;10;20;30;38;2;#{foreground};#{foreground};#{foreground}m" <>
      extra <> text <> "\e[0m"
  end

  test "foreground dimming retains blank padding but repaints text" do
    old = styled("text" <> String.duplicate(" ", 196), 200)
    new = styled("text" <> String.duplicate(" ", 196), 100)
    patch = CellPatch.build(old, new, 2, 200)
    assert patch == "\e[3;1H\e[0m" <> styled("text", 100)
    assert CellPatch.build(new, old, 2, 200) == "\e[3;1H\e[0m" <> styled("text", 200)
    assert CellPatch.build(styled("   ", 200), styled("   ", 100), 0, 3) == ""
  end

  test "changed backgrounds and foreground-visible attributes repaint spaces" do
    for extra <- ["\e[4m", "\e[7m", "\e[9m"] do
      patch = CellPatch.build(styled("   ", 200, extra), styled("   ", 100, extra), 0, 3)
      assert patch =~ "   "
      assert patch =~ extra
    end

    old = styled("   ", 200)
    new = String.replace(old, "48;2;10;20;30", "48;2;30;40;50")
    assert CellPatch.build(old, new, 0, 3) == nil

    assert Frame.build_payload([old], [new], [], [], 3, cell_patch: true) ==
             Frame.build_payload([old], [new], [], [], 3)
  end

  test "patches retain colors across cursor moves and only change differing colors" do
    old = styled("left", 200) <> styled(String.duplicate(" ", 40), 200) <> styled("right", 180)
    new = styled("left", 100) <> styled(String.duplicate(" ", 40), 100) <> styled("right", 90)

    assert CellPatch.build(old, new, 0, 49) ==
             "\e[1;1H\e[0m\e[48;2;10;20;30;38;2;100;100;100mleft" <>
               "\e[1;45H\e[38;2;90;90;90mright\e[0m"
  end

  test "retained colors reset when a patch returns to terminal defaults" do
    old = styled("left", 200) <> styled(String.duplicate(" ", 40), 200) <> "old"
    new = styled("left", 100) <> styled(String.duplicate(" ", 40), 100) <> "new"

    assert CellPatch.build(old, new, 0, 47) =~ "\e[1;45H\e[49;39mnew\e[0m"
  end

  test "attribute transitions fully reset retained state" do
    for attribute <- ["\e[1m", "\e[4m", "\e[7m"] do
      old =
        styled("old", 200, attribute) <>
          styled(String.duplicate(" ", 40), 200) <> styled("old", 200)

      new =
        styled("new", 100, attribute) <>
          styled(String.duplicate(" ", 40), 100) <> styled("new", 100)

      patch = CellPatch.build(old, new, 0, 46)
      assert patch =~ "\e[1;44H\e[0m\e[48;2;10;20;30;38;2;100;100;100mnew"
      assert replay([old], patch) == visual_cells(new)
    end
  end

  test "color transitions handle indexed and basic colors alongside RGB" do
    for color <- ["38;5;123", "91"] do
      old = styled("old", 200) <> styled(String.duplicate(" ", 40), 200) <> "\e[#{color}mold\e[0m"
      new = styled("new", 100) <> styled(String.duplicate(" ", 40), 100) <> "\e[#{color}mnew\e[0m"
      assert CellPatch.build(old, new, 0, 46) =~ "\e[1;44H\e[49;#{color}mnew\e[0m"
    end
  end

  test "rows reuse parsed styles and transitions without caching row positions or content" do
    old = styled("old", 200) <> styled(String.duplicate(" ", 40), 200) <> styled("tail", 180)
    new = styled("new", 100) <> styled(String.duplicate(" ", 40), 100) <> styled("tail", 90)
    {first, cache} = CellPatch.build(old, new, 0, 47, CellPatch.new_cache())
    {second, reused} = CellPatch.build(old, new, 3, 47, cache)
    assert cache == reused
    assert second == String.replace(first, "\e[1;", "\e[4;")
    assert CellPatch.build(old, new, 0, 47) == first
  end

  test "plain frames skip cache setup and later RGB rows still initialize it" do
    assert CellPatch.build("before", "after", 0, 20, nil) == {nil, nil}
    old = styled("text     ", 200)
    new = styled("text     ", 100)
    {patch, cache} = CellPatch.build(old, new, 1, 20, nil)
    assert is_map(cache)
    assert patch == CellPatch.build(old, new, 1, 20)
  end

  test "wide recolor fallback retains parsed styles for later eligible rows" do
    old = styled("界", 200)
    new = styled("界", 100)
    assert {nil, cache} = CellPatch.build(old, new, 0, 20, nil)
    assert map_size(cache.styles) > 0

    assert Frame.build_payload([old], [new], [], [], 20, cell_patch: true) ==
             Frame.build_payload([old], [new], [], [], 20)

    {patch, _} = CellPatch.build(styled("text", 200), styled("text", 100), 1, 20, cache)
    assert patch == CellPatch.build(styled("text", 200), styled("text", 100), 1, 20)
  end

  test "blank runs and ASCII fast paths keep combining marks with their base" do
    for text <- ["─́──", "é", "     ́", "     │tail", "     👩‍💻", "a\u{1F3FB}"] do
      old = styled(text, 200)
      new = styled(text, 100)

      case CellPatch.build(old, new, 0, 40) do
        nil -> assert text in ["     👩‍💻", "a\u{1F3FB}"]
        patch -> assert replay([old], patch) == visual_cells(new)
      end
    end
  end

  test "run comparisons clear stale text and handle different run boundaries" do
    for {before, after_text} <- [{"xxx     x", "x    xxxx"}, {"     text", ""}, {"", "   text"}] do
      old = styled(before, 200)
      new = styled(after_text, 100)
      patch = CellPatch.build(old, new, 0, 9)
      # Include the terminal-default padding in the expected cell maps.
      old = old <> String.duplicate(" ", 9 - String.length(before))
      new = new <> String.duplicate(" ", 9 - String.length(after_text))
      assert replay([old], patch) == visual_cells(new)
    end
  end

  test "unsupported controls, wide glyphs and unterminated styles retain the baseline" do
    old = styled("text", 200)

    for text <- ["界", "👩‍💻", "\t", "\e]8;;url\a", "\e[2J"] do
      assert CellPatch.build(old, styled(text, 100), 0, 20) == nil
    end

    assert CellPatch.build(old, "\e[38;2;1;2;3mtext", 0, 20) == nil
    assert CellPatch.build(old, styled("longer", 100), 0, 3) == nil
  end

  test "overlay removal repairs padding even when its foreground is invisible" do
    old = styled(String.duplicate(" ", 200), 200)
    new = styled(String.duplicate(" ", 200), 100)
    overlay = %{x: 50, y: 0, char: "X"}
    assert Frame.build_payload([old], [new], [overlay], [], 200, cell_patch: true) =~ new
  end

  test "opening and closing a dimmed fullscreen modal transmits less padding" do
    opts = [
      theme: Breeze.Theme.builtin(:nebula),
      terminal: %Termite.Terminal{size: %{width: 240, height: 80}}
    ]

    closed =
      Breeze.Renderer.render_to_string(ModalView, %{open: false}, opts)
      |> Frame.normalize_lines(80)

    opened =
      Breeze.Renderer.render_to_string(ModalView, %{open: true}, opts)
      |> Frame.normalize_lines(80)

    for {before, after_lines} <- [{closed, opened}, {opened, closed}] do
      payload = Frame.build_payload(before, after_lines, [], [], 240, cell_patch: true)
      baseline = Frame.build_payload(before, after_lines, [], [], 240)
      assert byte_size(payload) < byte_size(baseline) / 3
      assert replay(before, payload) == visual_cells(Enum.join(after_lines, "\n"))
    end
  end

  defp replay(lines, payload) do
    parts = Regex.split(~r/\e\[\d+;\d+H/, payload, include_captures: true, trim: true)

    {screen, _style} =
      parts
      |> Enum.chunk_every(2)
      |> Enum.reduce({visual_cells(Enum.join(lines, "\n")), ""}, fn [position, content],
                                                                    {screen, style} ->
        [_, row, col] = Regex.run(~r/\e\[(\d+);(\d+)H/, position)

        cells =
          visual_cells(style <> content, String.to_integer(col) - 1, String.to_integer(row) - 1)

        style =
          Regex.scan(~r/\e\[[0-9;]*m/, content)
          |> Enum.reduce(style, fn [sgr], style ->
            if sgr in ["\e[0m", "\e[m"], do: "", else: style <> sgr
          end)

        {Map.merge(screen, cells), style}
      end)

    screen
  end

  defp visual_cells(content, x \\ 0, y \\ 0) do
    {cells, _, _} = BackBreeze.Box.LayerMap.generate(content, %{}, x, y)

    fills =
      Enum.reduce(Map.get(cells, :__default_fill__, []), %{}, fn {point, left, top, right, bottom},
                                                                 acc ->
        Enum.reduce(top..bottom, acc, fn y, acc ->
          Enum.reduce(left..right, acc, fn x, acc -> Map.put(acc, {y, x}, point) end)
        end)
      end)

    cells = Map.merge(fills, Map.drop(cells, [:__default_fill__, :__wide_glyphs__]))

    Map.new(cells, fn {position, {char, style}} ->
      background = rgb(style, "48")
      foreground = if char != " ", do: rgb(style, "38")
      {position, {char, background, foreground}}
    end)
  end

  defp rgb(style, code) do
    Regex.scan(Regex.compile!("(?:\\[|;)#{code};2;(\\d+);(\\d+);(\\d+)"), style)
    |> List.last()
    |> case do
      nil -> nil
      [_ | channels] -> channels
    end
  end
end
