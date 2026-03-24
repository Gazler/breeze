Application.put_env(:breeze, :example_mode, :load_only)
Code.require_file("../examples/posting.exs", __DIR__)

defmodule BreezeBench.PostingServerBenchmark do
  @terminal_size %{width: 250, height: 70}

  defmodule FakeAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(_opts) do
      {:ok, %{ref: make_ref(), size: BreezeBench.PostingServerBenchmark.terminal_size()}}
    end

    def reader(term), do: {:ok, term.ref}
    def write(term, _str), do: {:ok, term}
    def resize(term), do: term.size
  end

  @interactions [
    {"tab", "\t"},
    {"type_a", "a"},
    {"type_slash", "/"},
    {"ctrl_t", "\x14"},
    {"f1", "F1"}
  ]
  @burst_interactions [
    {"burst_a_100", List.duplicate("a", 100)},
    {"burst_slash_100", List.duplicate("/", 100)}
  ]

  @iterations 30

  def terminal_size, do: @terminal_size

  def run do
    IO.puts("posting_server_benchmark")
    IO.puts("  iterations: #{@iterations}")
    IO.puts("  terminal: #{@terminal_size.width}x#{@terminal_size.height}")
    IO.puts("")

    Enum.each(@interactions, fn {label, key} ->
      samples =
        for _ <- 1..@iterations do
          run_once(key)
        end

      report(label, samples)
    end)

    Enum.each(@burst_interactions, fn {label, keys} ->
      samples =
        for _ <- 1..10 do
          run_burst_once(keys)
        end

      report_burst(label, samples)
    end)
  end

  defp run_once(key) do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        reader: reader,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    initial_render_count = :sys.get_state(pid).debug_stats[:render_base_count] || 0

    send(pid, {reader, {:data, key}})
    state = await_settle(pid, initial_render_count)

    sample = %{
      root_us: state.debug_stats[:last_root_snapshot_app_us] || state.debug_stats[:last_root_snapshot_us],
      live_us:
        state.debug_stats[:last_live_children_app_us] || state.debug_stats[:last_live_children_us],
      base_us: state.debug_stats[:last_render_base_app_us] || state.debug_stats[:last_render_base_us],
      frame_us: state.debug_stats[:last_frame_compose_us] || 0,
      flushes: state.debug_stats[:flush_input_batch_count] || 0,
      invalidations: state.debug_stats[:child_invalidated_count] || 0,
      animations: state.debug_stats[:animation_tick_count] || 0,
      renders: state.debug_stats[:render_base_count] || 0,
      cause: state.debug_stats[:last_render_cause],
      profile: state.debug_stats[:last_render_profile] || []
    }

    Process.exit(pid, :normal)
    sample
  end

  defp run_burst_once(keys) do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        reader: reader,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    started_at = System.monotonic_time(:millisecond)

    Enum.each(keys, fn key ->
      send(pid, {reader, {:data, key}})
    end)

    {state, peak} = await_burst_settle(pid, %{queue: 0, mailbox: 0, memory: 0})
    finished_at = System.monotonic_time(:millisecond)

    sample = %{
      burst_size: length(keys),
      drain_ms: finished_at - started_at,
      peak_queue: peak.queue,
      peak_mailbox: peak.mailbox,
      peak_memory: peak.memory,
      final_memory: process_memory(pid),
      flushes: state.debug_stats[:flush_input_batch_count] || 0,
      renders: state.debug_stats[:render_base_count] || 0
    }

    Process.exit(pid, :normal)
    sample
  end

  defp await_settle(pid, initial_render_count, attempts \\ 50)

  defp await_settle(pid, initial_render_count, attempts) when attempts > 0 do
    state = :sys.get_state(pid)

    if settled?(state, initial_render_count) do
      state
    else
      Process.sleep(20)
      await_settle(pid, initial_render_count, attempts - 1)
    end
  end

  defp await_settle(pid, _initial_render_count, 0), do: :sys.get_state(pid)

  defp await_burst_settle(pid, peak, attempts \\ 200)

  defp await_burst_settle(pid, peak, attempts) when attempts > 0 do
    state = :sys.get_state(pid)

    peak = %{
      queue: max(peak.queue, :queue.len(state.queued_input)),
      mailbox: max(peak.mailbox, message_queue_len(pid)),
      memory: max(peak.memory, process_memory(pid))
    }

    if :queue.is_empty(state.queued_input) and not state.input_flush_scheduled? and
         is_nil(state.pending_ref) and is_nil(state.render_timer) do
      {state, peak}
    else
      Process.sleep(10)
      await_burst_settle(pid, peak, attempts - 1)
    end
  end

  defp await_burst_settle(pid, peak, 0), do: {:sys.get_state(pid), peak}

  defp settled?(state, initial_render_count) do
    :queue.is_empty(state.queued_input) and not state.input_flush_scheduled? and
      is_nil(state.pending_ref) and (state.debug_stats[:render_base_count] || 0) > initial_render_count
  end

  defp report(label, samples) do
    profile = samples |> List.last() |> Map.fetch!(:profile)

    IO.puts(label)
    IO.puts("  cause: #{samples |> List.last() |> Map.fetch!(:cause)}")
    IO.puts("  root avg: #{fmt_avg(samples, :root_us)}")
    IO.puts("  live avg: #{fmt_avg(samples, :live_us)}")
    IO.puts("  base avg: #{fmt_avg(samples, :base_us)}")
    IO.puts("  frame avg: #{fmt_avg(samples, :frame_us)}")
    IO.puts("  renders avg: #{fmt_numeric_avg(samples, :renders)}")
    IO.puts("  flushes avg: #{fmt_numeric_avg(samples, :flushes)}")
    IO.puts("  invalidations avg: #{fmt_numeric_avg(samples, :invalidations)}")
    IO.puts("  animations avg: #{fmt_numeric_avg(samples, :animations)}")
    IO.puts("  profile: #{inspect(profile)}")
    IO.puts("")
  end

  defp report_burst(label, samples) do
    IO.puts(label)
    IO.puts("  drain avg: #{fmt_numeric_avg(samples, :drain_ms)}ms")
    IO.puts("  peak queue avg: #{fmt_numeric_avg(samples, :peak_queue)}")
    IO.puts("  peak mailbox avg: #{fmt_numeric_avg(samples, :peak_mailbox)}")
    IO.puts("  peak memory avg: #{fmt_bytes_avg(samples, :peak_memory)}")
    IO.puts("  final memory avg: #{fmt_bytes_avg(samples, :final_memory)}")
    IO.puts("  flushes avg: #{fmt_numeric_avg(samples, :flushes)}")
    IO.puts("  renders avg: #{fmt_numeric_avg(samples, :renders)}")
    IO.puts("")
  end

  defp fmt_avg(samples, key) do
    samples
    |> Enum.map(&Map.fetch!(&1, key))
    |> avg()
    |> Kernel./(1000)
    |> Float.round(2)
    |> then(&"#{&1}ms")
  end

  defp fmt_numeric_avg(samples, key) do
    samples
    |> Enum.map(&Map.fetch!(&1, key))
    |> avg()
    |> Float.round(2)
  end

  defp fmt_bytes_avg(samples, key) do
    bytes =
      samples
      |> Enum.map(&Map.fetch!(&1, key))
      |> avg()
      |> Float.round(0)
      |> trunc()

    "#{Float.round(bytes / 1_048_576, 2)}MB"
  end

  defp avg(values) do
    Enum.sum(values) / max(length(values), 1)
  end

  defp message_queue_len(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, len} -> len
      _ -> 0
    end
  end

  defp process_memory(pid) do
    case Process.info(pid, :memory) do
      {:memory, bytes} -> bytes
      _ -> 0
    end
  end
end

BreezeBench.PostingServerBenchmark.run()
