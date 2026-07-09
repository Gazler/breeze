defmodule BreezeBench.ListNavigationBenchmark do
  @moduledoc false

  @iterations String.to_integer(System.get_env("ITERATIONS", "60"))
  @warmup String.to_integer(System.get_env("WARMUP", "10"))
  @counts System.get_env("COUNTS", "100,1000")
          |> String.split(",")
          |> Enum.map(&String.to_integer/1)
  @terminals System.get_env("TERMINALS", "80x24,240x80")
             |> String.split(",")
             |> Enum.map(fn size ->
               [width, height] = size |> String.split("x") |> Enum.map(&String.to_integer/1)
               {width, height}
             end)
  @virtual_window (case System.get_env("VIRTUAL_WINDOW") do
                     nil -> nil
                     "" -> nil
                     value -> String.to_integer(value)
                   end)
  @scenario_filter (case System.get_env("SCENARIOS") do
                      nil ->
                        nil

                      "" ->
                        nil

                      value ->
                        value
                        |> String.split(",", trim: true)
                        |> MapSet.new()
                    end)

  defmodule ImplicitOnlyView do
    use Breeze.View
    import Breeze.Blocks

    def mount(opts, term) do
      count = Keyword.fetch!(opts, :count)

      {:ok,
       assign(term,
         items: BreezeBench.ListNavigationBenchmark.items(count),
         virtual: Keyword.get(opts, :virtual, false),
         virtual_overscan: Keyword.get(opts, :virtual_overscan, 24),
         virtual_window: Keyword.get(opts, :virtual_window)
       )}
    end

    def render(assigns) do
      ~H"""
      <box class="width-screen height-screen bg">
        <.list
          id="items"
          variant="muted"
          virtual={@virtual}
          virtual_overscan={@virtual_overscan}
          virtual_window={@virtual_window}
          selected-indicator=" "
          class="height-full width-full bg-panel border-0 focus:border-primary focus:scrollbar-primary"
          item_class="width-full"
        >
          <:item :for={item <- @items} value={item.id}>
            <box class="inline width-full overflow-hidden">
              <box class="width-28 bold">{item.name}</box>
              <box class="width-14 text-muted">{item.version}</box>
              <box class="width-14 text-right text-accent">{item.downloads}</box>
              <box class="width-full text-muted">{item.description}</box>
            </box>
          </:item>
        </.list>
      </box>
      """
    end
  end

  defmodule ControlledView do
    use Breeze.View
    import Breeze.Blocks

    def mount(opts, term) do
      count = Keyword.fetch!(opts, :count)
      items = BreezeBench.ListNavigationBenchmark.items(count)
      selected = List.first(items).id

      {:ok,
       assign(term,
         items: items,
         selected: selected,
         selected_item: List.first(items),
         virtual: Keyword.get(opts, :virtual, false),
         virtual_overscan: Keyword.get(opts, :virtual_overscan, 24),
         virtual_window: Keyword.get(opts, :virtual_window)
       )}
    end

    def render(assigns) do
      ~H"""
      <box class="grid grid-cols-2 gap-x-1 width-screen height-screen bg padding-1">
        <.list
          id="items"
          br-change="selected"
          list-selected={@selected}
          variant="muted"
          virtual={@virtual}
          virtual_overscan={@virtual_overscan}
          virtual_window={@virtual_window}
          selected-indicator=" "
          class="height-full width-full bg-panel border-0 focus:border-primary focus:scrollbar-primary"
          item_class="width-full"
        >
          <:item :for={item <- @items} value={item.id}>
            <box class="inline width-full overflow-hidden">
              <box class="width-28 bold">{item.name}</box>
              <box class="width-14 text-muted">{item.version}</box>
              <box class="width-full text-muted">{item.description}</box>
            </box>
          </:item>
        </.list>
        <box class="height-full width-full bg-panel padding-1 overflow-hidden">
          <box class="height-1 bold text-primary">{@selected_item.name}</box>
          <box class="height-1 text-accent">{@selected_item.version}</box>
          <box class="height-1 text-muted">{@selected_item.downloads} downloads</box>
          <box class="height-full">{@selected_item.description}</box>
        </box>
      </box>
      """
    end

    def handle_event("selected", %{value: id}, term) do
      item = Enum.find(term.assigns.items, &(&1.id == id)) || term.assigns.selected_item
      {:noreply, assign(term, selected: id, selected_item: item)}
    end
  end

  def run do
    IO.puts("list_navigation_benchmark")
    IO.puts("  iterations: #{@iterations}")
    IO.puts("  warmup: #{@warmup}")
    if @virtual_window, do: IO.puts("  virtual_window: #{@virtual_window}")
    IO.puts("")

    scenarios =
      [
        {"implicit_only", ImplicitOnlyView, []},
        {"implicit_virtual", ImplicitOnlyView, virtual_opts()},
        {"controlled", ControlledView, []},
        {"controlled_virtual", ControlledView, virtual_opts()}
      ]
      |> filter_scenarios()

    for {width, height} <- @terminals,
        count <- @counts,
        {label, view, opts} <- scenarios do
      terminal = %Termite.Terminal{size: %{width: width, height: height}}
      IO.puts("#{label} #{count} items #{width}x#{height}")

      dispatch = measure(view, count, terminal, opts, :dispatch)
      dispatch_render = measure(view, count, terminal, opts, :dispatch_render)
      profile = profile_render_step(view, count, terminal, opts)

      IO.puts("  dispatch avg: #{format_ms(avg(dispatch))}")
      IO.puts("  dispatch p95: #{format_ms(percentile(dispatch, 0.95))}")
      IO.puts("  dispatch+render avg: #{format_ms(avg(dispatch_render))}")
      IO.puts("  dispatch+render p95: #{format_ms(percentile(dispatch_render, 0.95))}")
      IO.puts("  profile:")

      Enum.each(profile, fn {metric, us} ->
        IO.puts("    #{format_profile_entry(metric, us)}")
      end)

      IO.puts("")
    end
  end

  def items(count) do
    Enum.map(1..count, fn idx ->
      %{
        id: "item-#{idx}",
        name: "package_#{idx}",
        version: "1.#{rem(idx, 17)}.#{rem(idx, 29)}",
        downloads: Integer.to_string(idx * 12_345),
        description: "A representative package row used to benchmark list cursor movement."
      }
    end)
  end

  defp measure(view, count, terminal, opts, mode) do
    {:ok, pid} =
      Breeze.ChildServer.start(
        view: view,
        start_opts: Keyword.put(opts, :count, count),
        terminal: terminal,
        theme: :system
      )

    try do
      {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
      {:noreply, "items", _changed?} = Breeze.ChildServer.set_focus(pid, "items")

      for _ <- 1..@warmup do
        run_step(pid, terminal, mode)
      end

      for _ <- 1..@iterations do
        {us, _result} = :timer.tc(fn -> run_step(pid, terminal, mode) end)
        us
      end
    after
      Process.exit(pid, :normal)
    end
  end

  defp run_step(pid, _terminal, :dispatch) do
    {:noreply, "items", _changed?} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
  end

  defp run_step(pid, terminal, :dispatch_render) do
    {:noreply, "items", _changed?} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")
    {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
  end

  defp profile_render_step(view, count, terminal, opts) do
    scope = make_ref()

    {:ok, pid} =
      Breeze.ChildServer.start(
        view: view,
        start_opts: Keyword.put(opts, :count, count),
        terminal: terminal,
        theme: :system
      )

    try do
      if System.get_env("COLD_PROFILE") in ["initial", "initial_render"] do
        BackBreeze.RenderCache.clear()
      end

      {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
      {:noreply, "items", _changed?} = Breeze.ChildServer.set_focus(pid, "items")

      for _ <- 1..@warmup do
        run_step(pid, terminal, :dispatch_render)
      end

      if System.get_env("COLD_PROFILE") in ["1", "true"] do
        BackBreeze.RenderCache.clear()
      end

      Breeze.DebugProfiler.reset(scope)
      BackBreeze.BenchProfile.enable_global!()
      BackBreeze.BenchProfile.reset_global!()
      {:noreply, "items", _changed?} = Breeze.ChildServer.dispatch_input(pid, "ArrowDown")

      {:ok, _acc, _box} =
        Breeze.ChildServer.render(pid,
          terminal: terminal,
          profile_scope: scope,
          profile_label: "list"
        )

      back_profile = BackBreeze.BenchProfile.snapshot_global()
      BackBreeze.BenchProfile.disable_global!()

      breeze_profile =
        scope
        |> Breeze.DebugProfiler.snapshot()
        |> Enum.reject(&(&1.metric == :element_count))
        |> Enum.map(&{&1.metric, &1.value})

      breeze_profile ++ back_profile_summary(back_profile)
    after
      Process.exit(pid, :normal)
    end
  end

  defp back_profile_summary(entries) do
    entries
    |> Enum.map(fn {label, stat} -> {{:back_breeze, label}, stat} end)
    |> Enum.sort_by(fn {_label, stat} -> -stat.total_us end)
    |> Enum.take(8)
  end

  defp virtual_opts do
    opts = [virtual: true, virtual_overscan: 4]

    if @virtual_window do
      Keyword.put(opts, :virtual_window, @virtual_window)
    else
      opts
    end
  end

  defp filter_scenarios(scenarios) do
    case @scenario_filter do
      nil ->
        scenarios

      filter ->
        Enum.filter(scenarios, fn {label, _view, _opts} -> MapSet.member?(filter, label) end)
    end
  end

  defp avg(values), do: Enum.sum(values) / max(length(values), 1)

  defp percentile(values, percentile) do
    values = Enum.sort(values)
    index = values |> length() |> Kernel.*(percentile) |> Float.ceil() |> trunc() |> Kernel.-(1)
    Enum.at(values, max(index, 0), 0)
  end

  defp format_ms(us) do
    us
    |> Kernel./(1000)
    |> Float.round(2)
    |> then(&"#{&1}ms")
  end

  defp format_profile_entry({:back_breeze, metric}, %{count: count, total_us: total, max_us: max}) do
    avg = total / max(count, 1)

    "#{format_label({:back_breeze, metric})}: total=#{format_ms(total)} avg=#{format_ms(avg)} max=#{format_ms(max)} count=#{count}"
  end

  defp format_profile_entry(metric, us), do: "#{format_label(metric)}: #{format_ms(us)}"

  defp format_label(label) when is_atom(label), do: Atom.to_string(label)
  defp format_label(label), do: inspect(label)
end

BreezeBench.ListNavigationBenchmark.run()
