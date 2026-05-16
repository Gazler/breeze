defmodule BreezeBench.TreeBenchmark do
  @moduledoc false

  @samples 8
  @terminal %Termite.Terminal{size: %{width: 100, height: 40}}

  defmodule View do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <box class="width-screen height-screen bg-panel">
        <.tree
          id="repo-tree"
          nodes={@nodes}
          selected={@selected}
          expanded={@expanded}
          class="width-full height-full border-invisible bg-panel focus:border-primary"
        >
          <:item :let={row}>
            <box class="inline height-1 overflow-hidden">
              <box
                class="inline width-2 height-1 overflow-hidden"
                style={%{foreground_color: row.node.icon_color}}
              >
                {row.node.icon}
              </box>
              <box selected-with-owner class="inline height-1 overflow-hidden selected:text-bg">
                {row.label}
              </box>
            </box>
          </:item>
        </.tree>
      </box>
      """
    end
  end

  defmodule PlainView do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <box class="width-screen height-screen bg-panel">
        <.tree
          id="repo-tree"
          nodes={@nodes}
          selected={@selected}
          expanded={@expanded}
          class="width-full height-full border-invisible bg-panel focus:border-primary"
        />
      </box>
      """
    end
  end

  def run(root \\ File.cwd!()) do
    root = Path.expand(root)

    IO.puts("tree_benchmark")
    IO.puts("  root: #{root}")
    IO.puts("  samples: #{@samples}")
    IO.puts("  terminal: #{@terminal.size.width}x#{@terminal.size.height}")
    IO.puts("")

    scenarios(root)
    |> Enum.each(fn {label, expanded} ->
      expanded = Enum.uniq(expanded)
      expanded_set = MapSet.new(expanded)

      build_samples =
        for _ <- 1..@samples do
          collect_sample(fn -> build_nodes(root, expanded_set) end)
        end

      nodes = List.last(build_samples).result
      row_count = count_rows(nodes)

      render_samples =
        for _ <- 1..@samples do
          collect_render_sample(View, nodes, expanded)
        end

      plain_render_samples =
        for _ <- 1..@samples do
          collect_render_sample(PlainView, nodes, expanded)
        end

      IO.puts(label)
      IO.puts("  expanded dirs: #{length(expanded)}")
      IO.puts("  visible rows: #{row_count}")
      IO.puts("  rebuild nodes avg: #{format_ms(avg_us(build_samples))}")
      IO.puts("  icon-slot render wall avg: #{format_ms(avg_us(render_samples))}")
      IO.puts("  icon-slot render profile avg:")

      render_samples
      |> average_profile()
      |> Enum.each(fn {metric, value} ->
        IO.puts("    #{metric}: #{format_ms(value)}")
      end)

      IO.puts("  icon-slot BackBreeze profile avg top 6:")

      render_samples
      |> average_back_profile()
      |> Enum.take(6)
      |> Enum.each(fn {label, value, count} ->
        IO.puts(
          "    #{format_label(label)}: #{format_ms(value)} (#{Float.round(count, 1)} calls)"
        )
      end)

      IO.puts("  plain render wall avg: #{format_ms(avg_us(plain_render_samples))}")
      IO.puts("  plain render profile avg:")

      plain_render_samples
      |> average_profile()
      |> Enum.each(fn {metric, value} ->
        IO.puts("    #{metric}: #{format_ms(value)}")
      end)

      IO.puts("")
    end)
  end

  defp scenarios(root) do
    [
      {"root only", [root]},
      {"source folders",
       existing([
         root,
         Path.join(root, "lib"),
         Path.join(root, "lib/breeze"),
         Path.join(root, "test"),
         Path.join(root, "examples")
       ])},
      {"breadth first 25 dirs", collect_dirs(root, 25)},
      {"breadth first 75 dirs", collect_dirs(root, 75)}
    ]
  end

  defp collect_sample(fun) do
    :erlang.garbage_collect()

    {us, result} =
      :timer.tc(fn ->
        fun.()
      end)

    %{us: us, result: result}
  end

  defp collect_render_sample(view, nodes, expanded) do
    assigns = %{nodes: nodes, expanded: expanded, selected: List.first(expanded)}
    implicit_state = bootstrap_implicit_state(view, assigns)
    scope = make_ref()
    Breeze.DebugProfiler.reset(scope)
    BackBreeze.BenchProfile.enable!()
    BackBreeze.BenchProfile.reset!()

    :erlang.garbage_collect()

    {us, {_acc, _box}} =
      :timer.tc(fn ->
        Breeze.Renderer.render(view, assigns,
          terminal: @terminal,
          theme: Breeze.Theme.builtin(:gruvbox),
          focused: "repo-tree",
          implicit_state: implicit_state,
          profile_scope: scope,
          profile_label: "tree"
        )
      end)

    back_profile = BackBreeze.BenchProfile.snapshot()
    BackBreeze.BenchProfile.disable!()

    %{us: us, profile: Breeze.DebugProfiler.snapshot(scope), back_profile: back_profile}
  end

  defp bootstrap_implicit_state(view, assigns) do
    {acc, _box} =
      Breeze.Renderer.render_tree(view, assigns,
        terminal: @terminal,
        theme: Breeze.Theme.builtin(:gruvbox),
        focused: "repo-tree",
        implicit_state: %{}
      )

    bootstrap =
      Breeze.RenderState.bootstrap(
        %Breeze.Term{terminal: @terminal, implicit_state: %{}},
        acc
      )

    bootstrap.implicit_state
  end

  defp average_profile(samples) do
    samples
    |> Enum.flat_map(& &1.profile)
    |> Enum.reject(&(&1.metric == :element_count))
    |> Enum.group_by(& &1.metric, & &1.value)
    |> Enum.map(fn {metric, values} -> {metric, avg(values)} end)
    |> Enum.sort_by(fn {_metric, value} -> value end, :desc)
  end

  defp average_back_profile(samples) do
    samples
    |> Enum.flat_map(fn sample ->
      Enum.map(sample.back_profile, fn {label, stat} ->
        {label, stat.total_us, stat.count}
      end)
    end)
    |> Enum.group_by(fn {label, _total, _count} -> label end, fn {_label, total, count} ->
      {total, count}
    end)
    |> Enum.map(fn {label, values} ->
      {totals, counts} = Enum.unzip(values)
      {label, avg(totals), avg(counts)}
    end)
    |> Enum.sort_by(fn {_label, total, _count} -> total end, :desc)
  end

  defp build_nodes(root, expanded) do
    [directory_node(root, display_root(root), expanded, root?: true)]
  end

  defp directory_node(path, label, expanded, opts \\ []) do
    children =
      if MapSet.member?(expanded, path) do
        path
        |> list_entries()
        |> Enum.map(&entry_node(&1, expanded))
      else
        []
      end

    %{
      id: path,
      label: label,
      icon: directory_icon(path, expanded, Keyword.get(opts, :root?, false)),
      icon_color: {86, 156, 214},
      expandable?: true,
      children: children
    }
  end

  defp entry_node(path, expanded) do
    name = Path.basename(path)

    if File.dir?(path) do
      directory_node(path, name <> "/", expanded)
    else
      {icon, icon_color} = file_icon(name)
      %{id: path, label: name, icon: icon, icon_color: icon_color, expandable?: false}
    end
  end

  defp list_entries(path) do
    case File.ls(path) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.map(&Path.join(path, &1))
        |> Enum.sort_by(fn entry ->
          {if(File.dir?(entry), do: 0, else: 1), Path.basename(entry)}
        end)

      {:error, _reason} ->
        []
    end
  end

  defp collect_dirs(root, limit) do
    do_collect_dirs(:queue.from_list([root]), MapSet.new(), [], limit)
  end

  defp do_collect_dirs(_queue, _seen, acc, limit) when length(acc) >= limit, do: Enum.reverse(acc)

  defp do_collect_dirs(queue, seen, acc, limit) do
    case :queue.out(queue) do
      {{:value, dir}, queue} ->
        if MapSet.member?(seen, dir) do
          do_collect_dirs(queue, seen, acc, limit)
        else
          children =
            dir
            |> list_entries()
            |> Enum.filter(&File.dir?/1)

          queue = Enum.reduce(children, queue, &:queue.in/2)
          do_collect_dirs(queue, MapSet.put(seen, dir), [dir | acc], limit)
        end

      {:empty, _queue} ->
        Enum.reverse(acc)
    end
  end

  defp existing(paths), do: Enum.filter(paths, &File.dir?/1)

  defp count_rows(nodes) do
    Enum.reduce(nodes, 0, fn node, count ->
      count + 1 + count_rows(Map.get(node, :children, []))
    end)
  end

  defp display_root(path) do
    case System.user_home() do
      nil -> path
      home -> String.replace_prefix(path, home, "~")
    end
  end

  defp directory_icon(path, expanded, _root?),
    do: if(MapSet.member?(expanded, path), do: "", else: "")

  defp file_icon(name) do
    case {String.downcase(name), String.downcase(Path.extname(name))} do
      {"mix.exs", _} -> {"", {154, 103, 174}}
      {"mix.lock", _} -> {"", {154, 103, 174}}
      {"readme.md", _} -> {"", {229, 192, 123}}
      {"licence.md", _} -> {"󰍔", {229, 192, 123}}
      {"license.md", _} -> {"󰍔", {229, 192, 123}}
      {"agents.md", _} -> {"", {229, 192, 123}}
      {_, ".ex"} -> {"", {154, 103, 174}}
      {_, ".exs"} -> {"", {154, 103, 174}}
      {_, ".erl"} -> {"", {196, 67, 98}}
      {_, ".hrl"} -> {"", {196, 67, 98}}
      {_, ".md"} -> {"", {229, 192, 123}}
      {_, ".lock"} -> {"", {224, 108, 117}}
      {_, ".toml"} -> {"", {97, 175, 239}}
      {_, ".json"} -> {"", {229, 192, 123}}
      {_, ".js"} -> {"", {240, 219, 79}}
      {_, ".css"} -> {"", {86, 156, 214}}
      {_, ".html"} -> {"", {227, 79, 38}}
      {_, ".svg"} -> {"󰜡", {255, 181, 46}}
      {_, ".png"} -> {"", {152, 195, 121}}
      {_, ".jpg"} -> {"", {152, 195, 121}}
      {_, ".jpeg"} -> {"", {152, 195, 121}}
      {_, ".gif"} -> {"", {152, 195, 121}}
      {_, ".yml"} -> {"", {97, 175, 239}}
      {_, ".yaml"} -> {"", {97, 175, 239}}
      _ -> {"󰈔", {171, 178, 191}}
    end
  end

  defp avg_us(samples), do: samples |> Enum.map(& &1.us) |> avg()

  defp avg(values), do: Enum.sum(values) / max(length(values), 1)

  defp format_ms(us) do
    us
    |> Kernel./(1000)
    |> Float.round(2)
    |> then(&"#{&1}ms")
  end

  defp format_label(label), do: inspect(label)
end

BreezeBench.TreeBenchmark.run()
