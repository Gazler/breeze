defmodule Breeze.Theme.Probe do
  @moduledoc false

  alias Breeze.Theme.Probe.TableOwner

  @palette_cache_table __MODULE__.PaletteCache
  @palette_waiters_table __MODULE__.PaletteWaiters
  @palette_probe_timeout_ms 120
  @required_palette_indexes [1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14]

  @spec cached_terminal_palette(%Termite.Terminal{} | nil) :: map() | nil
  def cached_terminal_palette(%Termite.Terminal{} = terminal) do
    with {:ok, key} <- terminal_cache_key(terminal),
         table <- ensure_palette_cache_table(),
         [{^key, palette}] <- :ets.lookup(table, key) do
      if palette == :unavailable, do: nil, else: palette
    else
      _ -> nil
    end
  end

  def cached_terminal_palette(_terminal), do: nil

  @spec probe_status(%Termite.Terminal{} | nil) :: :ready | :pending | :unavailable
  def probe_status(%Termite.Terminal{} = terminal) do
    cond do
      cached_palette_status(terminal) == :pending -> :pending
      cached_palette_status(terminal) == :ready -> :ready
      true -> :unavailable
    end
  end

  def probe_status(_terminal), do: :unavailable

  @spec ensure_runtime_palette_async(%Termite.Terminal{} | nil, pid()) :: :ok
  def ensure_runtime_palette_async(%Termite.Terminal{} = terminal, notify_pid)
      when is_pid(notify_pid) do
    case terminal_cache_key(terminal) do
      {:ok, key} ->
        ensure_palette_cache_table()
        ensure_palette_waiters_table()

        case :ets.lookup(@palette_cache_table, key) do
          [{^key, palette}] when is_map(palette) ->
            send(notify_pid, {:breeze_theme_palette, key, :ready})

          [{^key, :unavailable}] ->
            :ets.insert(@palette_cache_table, {key, :pending})
            :ets.insert(@palette_waiters_table, {key, notify_pid})

          [{^key, :pending}] ->
            :ets.insert(@palette_waiters_table, {key, notify_pid})

          [] ->
            :ets.insert(@palette_cache_table, {key, :pending})
            :ets.insert(@palette_waiters_table, {key, notify_pid})
        end

      :error ->
        :ok
    end

    :ok
  end

  def ensure_runtime_palette_async(_terminal, _notify_pid), do: :ok

  @spec start_runtime_palette_probe(%Termite.Terminal{} | nil) ::
          {:start, term(), binary()} | :ready | :pending | :unavailable | :error
  def start_runtime_palette_probe(%Termite.Terminal{} = terminal) do
    case terminal_cache_key(terminal) do
      {:ok, key} ->
        ensure_palette_cache_table()
        ensure_palette_waiters_table()

        case :ets.lookup(@palette_cache_table, key) do
          [{^key, palette}] when is_map(palette) ->
            :ready

          [{^key, :unavailable}] ->
            :ets.insert(@palette_cache_table, {key, :pending})
            {:start, key, palette_query_sequence()}

          [{^key, :pending}] ->
            {:start, key, palette_query_sequence()}

          [] ->
            :ets.insert(@palette_cache_table, {key, :pending})
            {:start, key, palette_query_sequence()}
        end

      :error ->
        :error
    end
  end

  def start_runtime_palette_probe(_terminal), do: :error

  @spec runtime_palette_probe_timeout_ms() :: pos_integer()
  def runtime_palette_probe_timeout_ms, do: @palette_probe_timeout_ms

  @spec merge_runtime_palette_data(binary(), map(), binary()) :: {map(), binary()}
  def merge_runtime_palette_data(buffer, palette, data)
      when is_binary(buffer) and is_map(palette) and is_binary(data) do
    extract_palette_responses(buffer <> data, palette)
  end

  @spec runtime_palette_probe_complete?(map()) :: boolean()
  def runtime_palette_probe_complete?(palette) when is_map(palette),
    do: palette_probe_complete?(palette)

  def runtime_palette_probe_complete?(_palette), do: false

  @spec finish_runtime_palette_probe(%Termite.Terminal{} | nil, map()) :: :ready | :unavailable
  def finish_runtime_palette_probe(%Termite.Terminal{} = terminal, palette)
      when is_map(palette) do
    case terminal_cache_key(terminal) do
      {:ok, key} ->
        ensure_palette_cache_table()
        ensure_palette_waiters_table()

        status =
          if palette_probe_complete?(palette) do
            :ets.insert(@palette_cache_table, {key, palette})
            :ready
          else
            :ets.insert(@palette_cache_table, {key, :unavailable})
            :unavailable
          end

        notify_palette_waiters(key, status)
        status

      :error ->
        :unavailable
    end
  end

  def finish_runtime_palette_probe(_terminal, _palette), do: :unavailable

  defp terminal_cache_key(%Termite.Terminal{reader: reader}) when not is_nil(reader),
    do: {:ok, {:reader, reader}}

  defp terminal_cache_key(_terminal), do: :error

  defp ensure_palette_cache_table do
    TableOwner.ensure_tables()
    @palette_cache_table
  end

  defp ensure_palette_waiters_table do
    TableOwner.ensure_tables()
    @palette_waiters_table
  end

  defp notify_palette_waiters(key, status) do
    waiters =
      @palette_waiters_table
      |> :ets.lookup(key)
      |> Enum.map(fn {^key, pid} -> pid end)

    :ets.delete(@palette_waiters_table, key)

    Enum.each(waiters, fn pid ->
      send(pid, {:breeze_theme_palette, key, status})
    end)
  end

  defp palette_query_sequence do
    foreground_background = ["\e]10;?\e\\", "\e]11;?\e\\"]

    indexed =
      Enum.map(@required_palette_indexes, fn index ->
        ["\e]4;", Integer.to_string(index), ";?\e\\"]
      end)

    IO.iodata_to_binary(foreground_background ++ indexed)
  end

  defp extract_palette_responses(buffer, palette) do
    case next_osc_sequence(buffer) do
      {:ok, sequence, rest} ->
        extract_palette_responses(rest, merge_palette_response(palette, sequence))

      :error ->
        {palette, trim_palette_buffer(buffer)}
    end
  end

  defp next_osc_sequence(buffer) do
    case :binary.match(buffer, "\e]") do
      {start, 2} ->
        slice = binary_part(buffer, start, byte_size(buffer) - start)

        case osc_terminator_index(slice) do
          {:ok, finish, length} ->
            sequence = binary_part(slice, 0, finish + length)
            rest = binary_part(slice, finish + length, byte_size(slice) - finish - length)
            {:ok, sequence, rest}

          :error ->
            :error
        end

      :nomatch ->
        :error
    end
  end

  defp osc_terminator_index(buffer) do
    bel = :binary.match(buffer, "\a")
    st = :binary.match(buffer, "\e\\")

    case {bel, st} do
      {{bel_pos, 1}, {st_pos, 2}} ->
        if bel_pos < st_pos, do: {:ok, bel_pos, 1}, else: {:ok, st_pos, 2}

      {{bel_pos, 1}, :nomatch} ->
        {:ok, bel_pos, 1}

      {:nomatch, {st_pos, 2}} ->
        {:ok, st_pos, 2}

      {:nomatch, :nomatch} ->
        :error
    end
  end

  defp trim_palette_buffer(buffer) when byte_size(buffer) > 512,
    do: binary_part(buffer, byte_size(buffer) - 512, 512)

  defp trim_palette_buffer(buffer), do: buffer

  defp merge_palette_response(palette, sequence) do
    case parse_palette_response(sequence) do
      {key, color} ->
        Map.put(palette, key, color)

      nil ->
        palette
    end
  end

  defp parse_palette_response(sequence) do
    cond do
      captures =
          Regex.run(~r/^\e\]10;rgb:([0-9A-Fa-f\/]+)(?:\a|\e\\)$/, sequence,
            capture: :all_but_first
          ) ->
        {:foreground, parse_osc_rgb!(hd(captures))}

      captures =
          Regex.run(~r/^\e\]11;rgb:([0-9A-Fa-f\/]+)(?:\a|\e\\)$/, sequence,
            capture: :all_but_first
          ) ->
        {:background, parse_osc_rgb!(hd(captures))}

      captures =
          Regex.run(~r/^\e\]4;(\d+);rgb:([0-9A-Fa-f\/]+)(?:\a|\e\\)$/, sequence,
            capture: :all_but_first
          ) ->
        [index, rgb] = captures
        {String.to_integer(index), parse_osc_rgb!(rgb)}

      true ->
        nil
    end
  end

  defp parse_osc_rgb!(value) do
    value
    |> String.split("/", trim: true)
    |> Enum.map(&parse_osc_channel!/1)
    |> List.to_tuple()
  end

  defp parse_osc_channel!(value) do
    {parsed, ""} = Integer.parse(value, 16)
    max_value = trunc(:math.pow(16, String.length(value))) - 1
    round(parsed * 255 / max(max_value, 1))
  end

  defp cached_palette_status(terminal) do
    with {:ok, key} <- terminal_cache_key(terminal),
         [{^key, value}] <- :ets.lookup(ensure_palette_cache_table(), key) do
      case value do
        palette when is_map(palette) -> :ready
        other -> other
      end
    else
      _ -> nil
    end
  end

  defp palette_probe_complete?(palette) when is_map(palette) do
    Enum.all?([:background, :foreground], &match?({_, _, _}, Map.get(palette, &1))) and
      Enum.all?(@required_palette_indexes, &match?({_, _, _}, Map.get(palette, &1)))
  end
end

defmodule Breeze.Theme.Probe.TableOwner do
  @moduledoc false

  use GenServer

  @palette_cache_table Breeze.Theme.Probe.PaletteCache
  @palette_waiters_table Breeze.Theme.Probe.PaletteWaiters

  def ensure_tables do
    case {
      Process.whereis(__MODULE__),
      :ets.whereis(@palette_cache_table),
      :ets.whereis(@palette_waiters_table)
    } do
      {pid, cache, waiters}
      when is_pid(pid) and cache != :undefined and waiters != :undefined ->
        :ok

      _ ->
        ensure_started()
        |> GenServer.call(:ensure_tables)
    end
  end

  @impl true
  def init(:ok), do: {:ok, ensure_tables_owned()}

  @impl true
  def handle_call(:ensure_tables, _from, _state) do
    {:reply, :ok, ensure_tables_owned()}
  end

  defp ensure_tables_owned do
    ensure_table(@palette_cache_table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true
    ])

    ensure_table(@palette_waiters_table, [:named_table, :public, :bag])
    nil
  end

  defp ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        case GenServer.start(__MODULE__, :ok, name: __MODULE__) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end

      pid ->
        pid
    end
  end

  defp ensure_table(name, options) do
    case :ets.whereis(name) do
      :undefined -> :ets.new(name, options)
      table -> table
    end
  end
end
