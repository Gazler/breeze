defmodule BreezeBench.AllExamplesCPU.Adapter do
  @moduledoc false

  @behaviour Termite.Terminal.Adapter

  def start(opts) do
    {width, height} = Keyword.fetch!(opts, :size)
    {:ok, %{ref: make_ref(), size: %{width: width, height: height}}}
  end

  def reader(terminal), do: {:ok, terminal.ref}
  def write(terminal, _data), do: {:ok, terminal}
  def resize(terminal), do: terminal.size
end

defmodule BreezeBench.AllExamplesCPU do
  @moduledoc false

  @result_prefix "BREEZE_BENCH_RESULT\t"
  @default_inputs 80
  @default_interval_ms 2
  @default_samples 3
  @default_size {120, 40}
  @examples_root Path.expand("../examples", __DIR__)

  @scenarios [
    %{
      id: "animated_progress",
      file: "animated_progress.exs",
      view: AnimatedProgressExample,
      server_opts: [hide_cursor: true]
    },
    %{
      id: "counter",
      file: "counter.exs",
      view: Demo,
      keys: ["ArrowUp", "ArrowDown"],
      server_opts: [alt_screen: false]
    },
    %{
      id: "crash_handler",
      file: "crash_handler.exs",
      view: CrashHandlerExample,
      keys: ["Enter", "x"],
      server_opts: [hide_cursor: true]
    },
    %{id: "custom_error_view", file: "custom_error_view.exs", view: CrashView},
    %{id: "debug", file: "debug.exs", view: Breeze.Debug, keys: ["ArrowDown", "ArrowUp"]},
    %{id: "demo", file: "demo.exs", view: Demo},
    %{
      id: "docs",
      file: "docs.exs",
      view: Docs,
      keys: ["ArrowDown", "ArrowUp"],
      server_opts: [hide_cursor: true, mouse: true]
    },
    %{
      id: "ex_codex_ex",
      file: "ex_codex_ex.exs",
      view: ExCodexEx,
      keys: ["x", "\b"],
      server_opts: [alt_screen: false, hide_cursor: true]
    },
    %{id: "fixed", file: "fixed.exs", view: FixedExample},
    %{id: "flash", file: "flash.exs", view: FlashExample, keys: ["p", "v"]},
    %{
      id: "focus",
      file: "focus.exs",
      view: Focus,
      keys: ["ArrowDown", "ArrowUp"],
      server_opts: [hide_cursor: false]
    },
    %{
      id: "forms",
      file: "forms.exs",
      view: FormsDemo,
      keys: ["x", "\b"],
      server_opts: [hide_cursor: true]
    },
    %{id: "grid", file: "grid.exs", view: Demo},
    %{
      id: "large_scroll",
      file: "large_scroll.exs",
      view: LargeScroll,
      keys: ["PageDown", "PageUp"],
      server_opts: [mouse: true]
    },
    %{
      id: "list_view",
      file: "list_view.exs",
      view: ListViewDemo,
      keys: ["ArrowDown", "ArrowUp"],
      server_opts: [mouse: true]
    },
    %{
      id: "logger",
      file: "logger.exs",
      view: LoggerExample,
      keys: ["l", "x"],
      server_opts: [inspector: true]
    },
    %{id: "modal", file: "modal.exs", view: ModalExample, keys: ["1", "Escape"]},
    %{
      id: "mouse",
      file: "mouse.exs",
      view: MouseExample,
      keys: ["\e[<65;8;8M", "\e[<64;8;8M"],
      server_opts: [hide_cursor: true, mouse: true]
    },
    %{
      id: "nested_views",
      file: "nested_views.exs",
      view: NestedViewsExample,
      keys: ["ArrowUp", "ArrowDown"],
      server_opts: [hide_cursor: true]
    },
    %{
      id: "posting",
      file: "posting.exs",
      view: Posting,
      keys: ["ArrowLeft", "ArrowRight"],
      server_opts: [hide_cursor: true, mouse: [mode: :motion], inspector: true]
    },
    %{
      id: "remote_inspector",
      file: "remote_inspector.exs",
      load: :source_proxy,
      view: Breeze.RemoteInspector.View,
      keys: ["ArrowDown", "ArrowUp"],
      server_opts: [mouse: true, inspector: true]
    },
    %{id: "responsive", file: "responsive.exs", view: Responsive},
    %{
      id: "scroll",
      file: "scroll.exs",
      view: Scroll,
      keys: ["PageDown", "PageUp"],
      server_opts: [mouse: true]
    },
    %{
      id: "slow_event_animation",
      file: "slow_event_animation.exs",
      view: SlowEventAnimationDemo,
      server_opts: [hide_cursor: true]
    },
    %{
      id: "snake",
      file: "snake.exs",
      view: Snake,
      keys: ["p", "x"],
      start_opts: [seed: {3, 29, 5}, tick_ms: 60_000],
      server_opts: [hide_cursor: true]
    },
    %{
      id: "storybook",
      file: "storybook.exs",
      view: Breeze.Storybook,
      keys: ["ArrowDown", "ArrowUp"],
      start_opts: [directory: "storybook"],
      server_opts: [hide_cursor: true, mouse: true, inspector: true]
    },
    %{
      id: "tabs",
      file: "tabs.exs",
      view: TabsExample,
      keys: ["ArrowRight", "ArrowLeft"],
      server_opts: [hide_cursor: true]
    },
    %{id: "theme", file: "theme.exs", view: ThemeDemo, keys: ["7", "8"]},
    %{
      id: "tree",
      file: "tree.exs",
      view: TreeExample,
      keys: ["ArrowDown", "ArrowUp"],
      start_opts: [root: "examples"]
    },
    %{
      id: "ssh/ssh_counter",
      file: "ssh/ssh_counter.exs",
      load: :module_only,
      view: SSHCounter,
      keys: ["ArrowUp", "ArrowDown"],
      start_opts: [username: "benchmark"]
    },
    %{
      id: "ssh/ssh_posting",
      file: "ssh/ssh_posting.exs",
      load: :source_proxy,
      proxy_file: "posting.exs",
      view: Posting,
      keys: ["ArrowLeft", "ArrowRight"],
      start_opts: [username: "benchmark"],
      server_opts: [hide_cursor: true, mouse: [mode: :motion], inspector: true]
    }
  ]

  def run do
    case System.get_env("BREEZE_BENCH_SCENARIO") do
      nil -> run_suite()
      id -> run_worker(fetch_scenario!(id))
    end
  end

  defp run_suite do
    samples = env_integer("SAMPLES", @default_samples)
    root = File.cwd!()
    benchmark = Path.expand(__ENV__.file)
    scenarios = selected_scenarios()
    validate_scenario_inventory!()

    if samples <= 0 or rem(samples, 2) == 0 do
      raise "SAMPLES must be a positive odd number, got: #{samples}"
    end

    IO.puts("all_examples_cpu_benchmark")
    IO.puts("  examples: #{length(scenarios)}")
    IO.puts("  inputs/example: #{env_integer("INPUTS", @default_inputs)}")
    IO.puts("  input interval: #{env_integer("INPUT_INTERVAL_MS", @default_interval_ms)}ms")
    IO.puts("  samples: #{samples}")
    IO.puts("")

    results =
      Enum.map(scenarios, fn scenario ->
        samples =
          Enum.map(1..samples, fn _sample ->
            run_isolated_worker(root, benchmark, scenario.id)
          end)

        result = median_result(samples)

        IO.puts(
          "#{String.pad_trailing(scenario.id, 24)} " <>
            "cpu=#{pad_number(result.cpu_ms, 6)}ms " <>
            "wall=#{pad_number(result.wall_ms, 6)}ms " <>
            "renders=#{pad_number(result.renders, 4)} " <>
            "flushes=#{pad_number(result.flushes, 4)} " <>
            "reductions=#{result.reductions}"
        )

        result
      end)

    total_cpu_ms = Enum.sum(Enum.map(results, & &1.cpu_ms))

    IO.puts("")
    IO.puts("total_cpu_ms=#{total_cpu_ms}")
    IO.puts("total_wall_ms=#{Enum.sum(Enum.map(results, & &1.wall_ms))}")
    IO.puts("total_renders=#{Enum.sum(Enum.map(results, & &1.renders))}")
    IO.puts("total_flushes=#{Enum.sum(Enum.map(results, & &1.flushes))}")
    assert_baseline_reduction!(total_cpu_ms)
  end

  defp run_isolated_worker(root, benchmark, scenario_id) do
    env = [
      {"BREEZE_BENCH_SCENARIO", scenario_id},
      {"INPUTS", Integer.to_string(env_integer("INPUTS", @default_inputs))},
      {"INPUT_INTERVAL_MS",
       Integer.to_string(env_integer("INPUT_INTERVAL_MS", @default_interval_ms))},
      {"BENCH_WIDTH", Integer.to_string(elem(benchmark_size(), 0))},
      {"BENCH_HEIGHT", Integer.to_string(elem(benchmark_size(), 1))},
      {"ELIXIR_ERL_OPTIONS", "+S 1:1 +SDcpu 1 +SDio 1 +A 1"}
    ]

    {output, status} =
      System.cmd(
        "mix",
        ["run", "--no-compile", "--no-deps-check", benchmark],
        cd: root,
        env: env,
        stderr_to_stdout: true
      )

    if status != 0 do
      raise "benchmark worker #{scenario_id} failed (#{status}):\n#{output}"
    end

    output
    |> String.split("\n")
    |> Enum.find(&String.starts_with?(&1, @result_prefix))
    |> case do
      nil -> raise "benchmark worker #{scenario_id} returned no result:\n#{output}"
      line -> parse_result(line)
    end
  end

  defp run_worker(scenario) do
    Process.flag(:trap_exit, true)
    Application.put_env(:breeze, :example_mode, :load_only)
    load_scenario(scenario)

    size = benchmark_size()
    terminal = Termite.Terminal.start(adapter: BreezeBench.AllExamplesCPU.Adapter, size: size)

    server_opts = [
      view: scenario.view,
      start_opts: expanded_start_opts(scenario),
      terminal: terminal,
      theme: Breeze.Theme.builtin(:gruvbox),
      logger: :replace,
      inspector: false
    ]

    server_opts =
      server_opts
      |> Keyword.merge(Map.get(scenario, :server_opts, []))
      |> Keyword.put(:halt_fun, fn -> :ok end)

    {:ok, router} = Breeze.Server.start_link(server_opts)
    router_state = :sys.get_state(router)
    server = router_state.server_pid
    reader = router_state.reader

    try do
      await_drained!(router, server)
      send_inputs(router, reader, scenario_keys(scenario), 6, 1)
      await_drained!(router, server)
      collect_garbage(router, server)

      before = sample_counters(server)
      runtime_before = runtime_total()
      reductions_before = reductions_total()
      started_at = System.monotonic_time(:millisecond)

      send_inputs(
        router,
        reader,
        scenario_keys(scenario),
        env_integer("INPUTS", @default_inputs),
        env_integer("INPUT_INTERVAL_MS", @default_interval_ms)
      )

      await_drained!(router, server)

      wall_ms = System.monotonic_time(:millisecond) - started_at
      cpu_ms = runtime_total() - runtime_before
      reductions = reductions_total() - reductions_before
      after_sample = sample_counters(server)

      result = %{
        id: scenario.id,
        cpu_ms: cpu_ms,
        wall_ms: wall_ms,
        reductions: reductions,
        renders: after_sample.renders - before.renders,
        flushes: after_sample.flushes - before.flushes,
        fingerprint: state_fingerprint(server)
      }

      IO.puts(encode_result(result))
    after
      stop_router(router)
    end
  end

  defp load_scenario(%{load: :module_only, file: file, view: view}) do
    path = Path.join(@examples_root, file)
    {:ok, ast} = path |> File.read!() |> Code.string_to_quoted(file: path)

    ast
    |> top_level_expressions()
    |> Enum.find(fn
      {:defmodule, _, [{:__aliases__, _, parts}, _]} -> Module.concat(parts) == view
      _ -> false
    end)
    |> case do
      nil -> raise "could not find #{inspect(view)} in #{path}"
      module_ast -> Code.eval_quoted(module_ast, [], file: path)
    end
  end

  defp load_scenario(%{load: :source_proxy, file: file} = scenario) do
    source_path = Path.join(@examples_root, file)
    {:ok, _ast} = source_path |> File.read!() |> Code.string_to_quoted(file: source_path)

    case Map.get(scenario, :proxy_file) do
      nil -> :ok
      proxy_file -> Code.require_file(Path.join(@examples_root, proxy_file))
    end

    :ok
  end

  defp load_scenario(%{file: file}) do
    Code.require_file(Path.join(@examples_root, file))
    :ok
  end

  defp top_level_expressions({:__block__, _, expressions}), do: expressions
  defp top_level_expressions(expression), do: [expression]

  defp expanded_start_opts(scenario) do
    scenario
    |> Map.get(:start_opts, [])
    |> Keyword.update(:root, nil, &Path.expand/1)
    |> Keyword.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp scenario_keys(scenario) do
    scenario
    |> Map.get(:keys, ["x", "y"])
    |> Enum.map(&raw_key/1)
  end

  defp raw_key("ArrowUp"), do: "\e[A"
  defp raw_key("ArrowDown"), do: "\e[B"
  defp raw_key("ArrowRight"), do: "\e[C"
  defp raw_key("ArrowLeft"), do: "\e[D"
  defp raw_key("PageUp"), do: "\e[5~"
  defp raw_key("PageDown"), do: "\e[6~"
  defp raw_key("Enter"), do: "\r"
  defp raw_key("Escape"), do: "\e"
  defp raw_key(key), do: key

  defp send_inputs(server, reader, keys, count, interval_ms) do
    keys = List.to_tuple(keys)
    key_count = tuple_size(keys)

    if count > 0 do
      Enum.each(0..(count - 1), fn index ->
        send(server, {reader, {:data, elem(keys, rem(index, key_count))}})
        if interval_ms > 0, do: Process.sleep(interval_ms)
      end)
    end
  end

  defp await_drained!(router, server, attempts \\ 10_000)

  defp await_drained!(router, server, attempts) when attempts > 0 do
    _router_state = :sys.get_state(router)
    state = :sys.get_state(server)
    input = state.input
    {:message_queue_len, router_mailbox_size} = Process.info(router, :message_queue_len)
    {:message_queue_len, mailbox_size} = Process.info(server, :message_queue_len)

    if router_mailbox_size == 0 and mailbox_size == 0 and
         :queue.is_empty(input.queued_input) and
         not input.flush_scheduled? and is_nil(input.pending_ref) and
         not input.render_after_flush? and is_nil(Map.get(input, :render_timer)) do
      state
    else
      Process.sleep(5)
      await_drained!(router, server, attempts - 1)
    end
  end

  defp await_drained!(_router, server, 0) do
    raise "server did not drain: #{inspect(:sys.get_state(server).input)}"
  end

  defp collect_garbage(router, server) do
    state = :sys.get_state(server)
    :erlang.garbage_collect(router)
    :erlang.garbage_collect(server)
    :erlang.garbage_collect(state.view_pid)

    Enum.each(state.children, fn {_id, child} ->
      if is_pid(child.pid) and Process.alive?(child.pid), do: :erlang.garbage_collect(child.pid)
    end)
  end

  defp sample_counters(server) do
    stats = :sys.get_state(server).debug.stats

    %{
      renders: Map.get(stats, :render_base_count, 0),
      flushes: Map.get(stats, :flush_input_batch_count, 0)
    }
  end

  defp state_fingerprint(server) do
    state = :sys.get_state(server)
    metadata = Breeze.ChildServer.metadata(state.view_pid)

    :erlang.phash2({
      state.focused,
      state.frame.base_output,
      metadata.assigns,
      metadata.implicit_state
    })
  end

  defp runtime_total do
    {total, _since_last} = :erlang.statistics(:runtime)
    total
  end

  defp reductions_total do
    {total, _since_last} = :erlang.statistics(:reductions)
    total
  end

  defp stop_router(router) do
    if Process.alive?(router), do: GenServer.stop(router, :normal, 5_000)
  catch
    :exit, _reason -> :ok
  end

  defp encode_result(result) do
    @result_prefix <>
      Enum.join(
        [
          result.id,
          Integer.to_string(result.cpu_ms),
          Integer.to_string(result.wall_ms),
          Integer.to_string(result.reductions),
          Integer.to_string(result.renders),
          Integer.to_string(result.flushes),
          Integer.to_string(result.fingerprint)
        ],
        "\t"
      )
  end

  defp parse_result(line) do
    [id, cpu_ms, wall_ms, reductions, renders, flushes, fingerprint] =
      line
      |> String.trim_leading(@result_prefix)
      |> String.split("\t")

    %{
      id: id,
      cpu_ms: String.to_integer(cpu_ms),
      wall_ms: String.to_integer(wall_ms),
      reductions: String.to_integer(reductions),
      renders: String.to_integer(renders),
      flushes: String.to_integer(flushes),
      fingerprint: String.to_integer(fingerprint)
    }
  end

  defp median_result([result]), do: result

  defp median_result(results) do
    middle = div(length(results), 2)

    %{
      id: hd(results).id,
      cpu_ms: median_field(results, :cpu_ms, middle),
      wall_ms: median_field(results, :wall_ms, middle),
      reductions: median_field(results, :reductions, middle),
      renders: median_field(results, :renders, middle),
      flushes: median_field(results, :flushes, middle),
      fingerprint: hd(results).fingerprint
    }
  end

  defp median_field(results, field, middle) do
    results
    |> Enum.map(&Map.fetch!(&1, field))
    |> Enum.sort()
    |> Enum.at(middle)
  end

  defp benchmark_size do
    {
      env_integer("BENCH_WIDTH", elem(@default_size, 0)),
      env_integer("BENCH_HEIGHT", elem(@default_size, 1))
    }
  end

  defp env_integer(name, default) do
    case System.get_env(name) do
      nil -> default
      value -> String.to_integer(value)
    end
  end

  defp fetch_scenario!(id) do
    Enum.find(@scenarios, &(&1.id == id)) ||
      raise "unknown scenario #{inspect(id)}"
  end

  defp selected_scenarios do
    case System.get_env("SCENARIOS") do
      nil ->
        @scenarios

      value ->
        selected = value |> String.split(",", trim: true) |> MapSet.new()
        scenarios = Enum.filter(@scenarios, &MapSet.member?(selected, &1.id))

        missing = MapSet.difference(selected, MapSet.new(Enum.map(scenarios, & &1.id)))

        if MapSet.size(missing) > 0 do
          raise "unknown scenarios: #{missing |> Enum.sort() |> Enum.join(", ")}"
        end

        scenarios
    end
  end

  defp validate_scenario_inventory! do
    files =
      @examples_root
      |> Path.join("**/*.exs")
      |> Path.wildcard()
      |> Enum.map(&Path.relative_to(&1, @examples_root))
      |> Enum.sort()

    scenario_files =
      @scenarios
      |> Enum.map(& &1.file)
      |> Enum.sort()

    if files != scenario_files do
      raise """
      benchmark scenario inventory does not match examples/**/*.exs
      files: #{inspect(files)}
      scenarios: #{inspect(scenario_files)}
      """
    end
  end

  defp assert_baseline_reduction!(total_cpu_ms) do
    case System.get_env("BASELINE_CPU_MS") do
      nil ->
        :ok

      value ->
        baseline_cpu_ms = String.to_integer(value)

        if baseline_cpu_ms <= 0 do
          raise "BASELINE_CPU_MS must be positive, got: #{baseline_cpu_ms}"
        end

        reduction = 100.0 * (1.0 - total_cpu_ms / baseline_cpu_ms)
        IO.puts("baseline_cpu_ms=#{baseline_cpu_ms}")
        IO.puts("cpu_reduction_pct=#{Float.round(reduction, 2)}")

        if reduction < 50.0 do
          raise "CPU reduction #{Float.round(reduction, 2)}% is below required 50%"
        end
    end
  end

  defp pad_number(number, width) do
    number
    |> Integer.to_string()
    |> String.pad_leading(width)
  end
end

BreezeBench.AllExamplesCPU.run()
