defmodule Breeze.Clipboard.Probe do
  @moduledoc false

  @da1 "\e[c"
  @ms "\eP+q4d73\e\\"

  def new, do: %{phase: :da1, buffer: "", clipboard: %{osc52: :unknown, supported: false}}
  def query, do: @da1
  def timeout_ms, do: 250

  def feed(probe, data) when is_binary(data) do
    scan(%{probe | buffer: ""}, probe.buffer <> data, [], [])
  end

  def expire(probe), do: %{probe | phase: :done}

  def flush(probe) do
    # Preserve an ordinary Escape key; discard an incomplete capability reply.
    data = if probe.buffer in ["\e", "\e[", "\eP"], do: probe.buffer, else: ""
    {%{probe | buffer: ""}, data}
  end

  defp scan(probe, "", output, queries),
    do: {probe, output |> Enum.reverse() |> IO.iodata_to_binary(), Enum.reverse(queries)}

  defp scan(probe, data, output, queries) do
    case response(data) do
      {:reply, reply, rest} ->
        {probe, query} = accept(probe, reply)
        queries = if query, do: [query | queries], else: queries
        scan(probe, rest, output, queries)

      :partial ->
        {%{probe | buffer: data}, output |> Enum.reverse() |> IO.iodata_to_binary(),
         Enum.reverse(queries)}

      :ordinary ->
        size =
          case :binary.match(data, "\e") do
            :nomatch -> byte_size(data)
            {0, _} -> 1
            {index, _} -> index
          end

        chunk = binary_part(data, 0, size)
        rest = binary_part(data, size, byte_size(data) - size)
        scan(probe, rest, [chunk | output], queries)
    end
  end

  defp response(data) do
    cond do
      match = Regex.run(~r/^\e\[\?([0-9;]+)c/, data) ->
        [whole, params] = match
        {:reply, {:da1, String.split(params, ";")}, drop(data, whole)}

      match = Regex.run(~r/^\eP([01])\+r4[dD]73(?:=([0-9a-fA-F]*))?\e\\/, data) ->
        [whole, success | value] = match
        {:reply, {:ms, success, List.first(value) || ""}, drop(data, whole)}

      byte_size(data) <= 4096 and partial?(data) ->
        :partial

      true ->
        :ordinary
    end
  end

  defp partial?(data) do
    Enum.any?(["\e[?", "\eP1+r4d73", "\eP0+r4d73"], &String.starts_with?(&1, data)) or
      Regex.match?(~r/^\e\[\?[0-9;]*$/, data) or
      Regex.match?(~r/^\eP[01]\+r4[dD]73(?:=[0-9a-fA-F]*)?\e?$/, data)
  end

  defp drop(data, prefix),
    do: binary_part(data, byte_size(prefix), byte_size(data) - byte_size(prefix))

  defp accept(%{phase: :done} = probe, _reply), do: {probe, nil}

  defp accept(probe, {:da1, params}) do
    cond do
      "52" in params ->
        {%{probe | phase: :done, clipboard: %{osc52: :supported, supported: true}}, nil}

      probe.phase == :da1 ->
        {%{probe | phase: :ms}, @ms}

      true ->
        {probe, nil}
    end
  end

  defp accept(probe, {:ms, "1", encoded}) do
    case Base.decode16(encoded, case: :mixed) do
      {:ok, "\e]52;" <> _} ->
        {%{probe | phase: :done, clipboard: %{osc52: :supported, supported: true}}, nil}

      _ ->
        {%{probe | phase: :done}, nil}
    end
  end

  defp accept(probe, {:ms, _, _}), do: {%{probe | phase: :done}, nil}
end
