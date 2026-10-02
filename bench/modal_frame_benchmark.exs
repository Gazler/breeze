# Run with: mix run bench/modal_frame_benchmark.exs
# Measures frame encoding only, excluding layout and terminal/SSH I/O.
# Each operation creates a fresh frame cache; both paths receive identical rows.
# Modal fixtures use the renderer; other cases are synthetic 240x80 ANSI frames.
# Row-shift cases exercise Frame diffs, not ScrollFrame's terminal scroll commands.
# CSV output includes median/p95 microseconds per frame, bytes and VM reductions.
defmodule BreezeBench.ModalFrame do
  alias Breeze.Server.Frame

  defmodule View do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <box class="w-screen h-screen grid bg">
        <box class="h-1 bg-panel">Org console — shell stopped</box>
        <box class="pt-1 grid grid-cols-2">
          <.panel class="w-34 bg">
            <:title>Sprites</:title>
            <box :for={n <- 1..78} class="inline h-1 w-full">
              <box class="w-2 text-muted">- </box>
              <box class="w-22">{name(n)}</box>
              <box class="w-full text-muted">stopped</box>
            </box>
          </.panel>
          <.panel class="bg">
            <:title>bench-053</:title>
            <box>default/bench-053 sprite shell</box>
            <box>Sprite is stopped; start it before attaching.</box>
          </.panel>
        </box>
        <box class="h-1 bg-panel">Esc close</box>
        <.modal :if={@open} id="create" width={54} height={9} dim>
          <:title>New sprite</:title>
          <box>Name</box>
          <.input id="name" input-value=""/>
        </.modal>
      </box>
      """
    end

    defp name(n), do: "default/bench-" <> String.pad_leading(to_string(n), 3, "0")
  end

  def run do
    IO.puts(
      "scenario,baseline_us,patch_us,ratio,baseline_p95_us,patch_p95_us,baseline_bytes,patch_bytes,baseline_reductions,patch_reductions"
    )

    for scenario <- scenarios() do
      measure(scenario)
    end
  end

  defp scenarios do
    modals =
      for {width, height} <- [{80, 24}, {120, 40}, {240, 80}] do
        opts = [
          theme: Breeze.Theme.builtin(:nord),
          terminal: %Termite.Terminal{size: %{width: width, height: height}}
        ]

        closed =
          Breeze.Renderer.render_to_string(View, %{open: false}, opts)
          |> Frame.normalize_lines(height)

        opened =
          Breeze.Renderer.render_to_string(View, %{open: true}, opts)
          |> Frame.normalize_lines(height)

        [
          {"modal open #{width}x#{height}", closed, opened, width},
          {"modal close #{width}x#{height}", opened, closed, width}
        ]
      end
      |> List.flatten()

    width = 240
    plain = for n <- 1..80, do: String.pad_trailing("Application row #{n}: ready", width)
    rgb = Enum.map(plain, &style(&1, 200))

    dense =
      for n <- 1..80 do
        for col <- 1..24,
            into: "",
            do: style(String.pad_trailing("#{n}:#{col}", 10), 100 + rem(col, 5) * 20)
      end

    unicode =
      for n <- 1..80,
          do: style(String.duplicate("界", 100) <> String.pad_trailing(" row #{n}", 40), 200)

    combining = for _ <- 1..80, do: style(String.duplicate("é", width), 200)

    dim = fn rows ->
      Enum.map(rows, &String.replace(&1, "38;2;200;200;200", "38;2;100;100;100"))
    end

    modals ++
      [
        {"unchanged 240x80", rgb, rgb, width},
        {"initial draw 240x80", nil, rgb, width},
        {"one character RGB", rgb, List.update_at(rgb, 30, &String.replace(&1, "ready", "read!")),
         width},
        {"one character plain", plain,
         List.update_at(plain, 30, &String.replace(&1, "ready", "read!")), width},
        {"scroll RGB one row", rgb,
         tl(rgb) ++ [style(String.pad_trailing("Application row 81: ready", width), 200)], width},
        {"scroll plain one row", plain,
         tl(plain) ++ [String.pad_trailing("Application row 81: ready", width)], width},
        {"sparse foreground dim", rgb, dim.(rgb), width},
        {"dense styled recolor", dense,
         Enum.map(dense, &String.replace(&1, "48;2;10;20;30", "48;2;20;30;40")), width},
        {"background recolor", rgb,
         Enum.map(rgb, &String.replace(&1, "48;2;10;20;30", "48;2;20;30;40")), width},
        {"wide Unicode fallback", unicode, dim.(unicode), width},
        {"combining Unicode dim", combining, dim.(combining), width}
      ]
  end

  defp style(text, foreground),
    do: "\e[48;2;10;20;30;38;2;#{foreground};#{foreground};#{foreground}m" <> text <> "\e[0m"

  defp measure({name, previous, current, width}) do
    encoders =
      for enabled <- [false, true],
          do: fn -> Frame.build_payload(previous, current, [], [], width, cell_patch: enabled) end

    for encode <- encoders, _ <- 1..20, do: encode.()

    # Alternate order to reduce systematic warmup/clock bias. Batch small
    # operations to avoid timer resolution dominating unchanged frames.
    samples =
      for sample <- 1..100 do
        order = if rem(sample, 2) == 0, do: [0, 1], else: [1, 0]

        for index <- order, into: %{} do
          encode = Enum.at(encoders, index)
          {:reductions, before} = Process.info(self(), :reductions)
          {us, _} = :timer.tc(fn -> for _ <- 1..10, do: encode.() end)
          {:reductions, after_count} = Process.info(self(), :reductions)
          {index, {us / 10, (after_count - before) / 10}}
        end
      end

    [baseline, patch] =
      for index <- [0, 1] do
        times = samples |> Enum.map(&elem(&1[index], 0)) |> Enum.sort()
        reductions = samples |> Enum.map(&elem(&1[index], 1)) |> Enum.sort()

        %{
          median: Enum.at(times, 50),
          p95: Enum.at(times, 94),
          reductions: Enum.at(reductions, 50),
          bytes: byte_size(Enum.at(encoders, index).())
        }
      end

    values = [
      name,
      baseline.median,
      patch.median,
      Float.round(patch.median / max(baseline.median, 0.1), 2),
      baseline.p95,
      patch.p95,
      baseline.bytes,
      patch.bytes,
      baseline.reductions,
      patch.reductions
    ]

    IO.puts(Enum.join(values, ","))
  end
end

BreezeBench.ModalFrame.run()
