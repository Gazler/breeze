defmodule Breeze.InputRouter.CursorProbe do
  @moduledoc false

  @timeout_ms 200
  @report ~r/\e\[([0-9]{1,5});([0-9]{1,5})R/
  @partial ~r/\e(?:\[(?:[0-9]{0,5}(?:;[0-9]{0,5})?)?)?$/

  defstruct [:ref, :recipient, status: :active, buffer: "", deferred: []]

  def timeout_ms, do: @timeout_ms

  # Keep routing late reports after the querying process has timed out.
  def expiry_ms, do: @timeout_ms * 2

  def waiting, do: %__MODULE__{ref: make_ref(), status: :waiting}
  def draining, do: start(nil, make_ref(), nil)

  def start(previous, ref, recipient) do
    probe = previous || %__MODULE__{}
    %{probe | ref: ref, recipient: recipient, status: :active}
  end

  # Return effects to the router; state transitions do not send messages or
  # start timers, so buffering and expiration can be tested independently.
  def consume(nil, data), do: {nil, [data], nil}

  def consume(%{status: :waiting} = probe, data),
    do: {%{probe | deferred: [data | probe.deferred]}, [], nil}

  def consume(probe, data) when is_binary(data) do
    {position, input, buffer} = feed(probe.buffer, data)
    probe = %{probe | buffer: buffer, deferred: [input | probe.deferred]}

    if position do
      reply =
        if is_pid(probe.recipient),
          do: {probe.recipient, {:inline_cursor_reply, probe.ref, position}}

      {nil, release(probe), reply}
    else
      {probe, [], nil}
    end
  end

  def consume(probe, data), do: {probe, [data], nil}

  def expire(%{ref: ref} = probe, ref), do: {nil, release(probe)}
  def expire(probe, _ref), do: {probe, []}

  defp release(probe),
    do: Enum.reverse([probe.buffer | probe.deferred]) |> Enum.reject(&(&1 == ""))

  def query(terminal, router \\ nil) do
    ref = make_ref()
    if is_pid(router), do: send(router, {:inline_cursor_query, ref, self()})
    terminal = Termite.Terminal.write(terminal, "\e[6n")
    deadline = System.monotonic_time(:millisecond) + @timeout_ms
    {position, deferred} = collect(terminal.reader, ref, deadline, "", [])
    Enum.each(Enum.reverse(deferred), &send(self(), &1))
    {terminal, position}
  end

  # Only used while a query is pending: CPR shares a sequence with modified F3.
  # Preserve unrelated input, including input surrounding a fragmented report.
  def feed(buffer, data) do
    data = buffer <> data

    case Regex.run(@report, data, return: :index) do
      [{start, size}, row_range, col_range] ->
        row = data |> binary_part(elem(row_range, 0), elem(row_range, 1)) |> String.to_integer()
        col = data |> binary_part(elem(col_range, 0), elem(col_range, 1)) |> String.to_integer()

        input =
          binary_part(data, 0, start) <>
            binary_part(data, start + size, byte_size(data) - start - size)

        position = if row > 0 and col > 0, do: {row, col}
        {position, input, ""}

      nil ->
        case Regex.run(@partial, data, return: :index) do
          [{start, size}] -> {nil, binary_part(data, 0, start), binary_part(data, start, size)}
          nil -> {nil, data, ""}
        end
    end
  end

  defp collect(reader, ref, deadline, buffer, deferred) do
    timeout = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:inline_cursor_reply, ^ref, position} ->
        {position, defer(deferred, reader, buffer)}

      {^reader, {:data, data}} when is_binary(data) ->
        {position, input, buffer} = feed(buffer, data)
        deferred = defer(deferred, reader, input)

        if position,
          do: {position, deferred},
          else: collect(reader, ref, deadline, buffer, deferred)
    after
      timeout -> {nil, defer(deferred, reader, buffer)}
    end
  end

  defp defer(messages, _reader, ""), do: messages
  defp defer(messages, reader, data), do: [{reader, {:data, data}} | messages]
end
