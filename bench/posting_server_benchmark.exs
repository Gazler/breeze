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
    {"ctrl_t", "\x14"},
    {"f1", "F1"}
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

    send(pid, {reader, {:data, key}})
    state = await_settle(pid)

    sample = %{
      root_us: state.debug_stats[:last_root_snapshot_app_us] || state.debug_stats[:last_root_snapshot_us],
      live_us:
        state.debug_stats[:last_live_children_app_us] || state.debug_stats[:last_live_children_us],
      base_us: state.debug_stats[:last_render_base_app_us] || state.debug_stats[:last_render_base_us],
      flushes: state.debug_stats[:flush_input_batch_count] || 0,
      invalidations: state.debug_stats[:child_invalidated_count] || 0,
      animations: state.debug_stats[:animation_tick_count] || 0,
      renders: state.debug_stats[:render_base_count] || 0,
      cause: state.debug_stats[:last_render_cause]
    }

    Process.exit(pid, :normal)
    sample
  end

  defp await_settle(pid, attempts \\ 50)

  defp await_settle(pid, attempts) when attempts > 0 do
    state = :sys.get_state(pid)

    if settled?(state) do
      state
    else
      Process.sleep(20)
      await_settle(pid, attempts - 1)
    end
  end

  defp await_settle(pid, 0), do: :sys.get_state(pid)

  defp settled?(state) do
    state.queued_input == [] and not state.input_flush_scheduled? and is_nil(state.pending_ref) and
      is_nil(state.animation_timer)
  end

  defp report(label, samples) do
    IO.puts(label)
    IO.puts("  cause: #{samples |> List.last() |> Map.fetch!(:cause)}")
    IO.puts("  root avg: #{fmt_avg(samples, :root_us)}")
    IO.puts("  live avg: #{fmt_avg(samples, :live_us)}")
    IO.puts("  base avg: #{fmt_avg(samples, :base_us)}")
    IO.puts("  renders avg: #{fmt_numeric_avg(samples, :renders)}")
    IO.puts("  flushes avg: #{fmt_numeric_avg(samples, :flushes)}")
    IO.puts("  invalidations avg: #{fmt_numeric_avg(samples, :invalidations)}")
    IO.puts("  animations avg: #{fmt_numeric_avg(samples, :animations)}")
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

  defp avg(values) do
    Enum.sum(values) / max(length(values), 1)
  end
end

BreezeBench.PostingServerBenchmark.run()
