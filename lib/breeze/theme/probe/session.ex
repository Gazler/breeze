defmodule Breeze.Theme.Probe.Session do
  @moduledoc """
  Palette probing for custom transports that bypass `Breeze.InputRouter`.

  Most applications do not need this module. With `theme: :system`, normal
  startup through `Breeze.Server.start_link/1` probes the terminal automatically
  via `Breeze.InputRouter`, handles replies, and falls back when the terminal
  does not respond. No manual probe setup is required.

  Use this API only when a custom transport starts `Breeze.Server.start_app_link/1`
  directly and owns the raw input stream instead of using the input router.
  For example, a transport may route some input to Breeze navigation and other
  input directly to an embedded shell. The transport must consume palette
  replies before making that routing decision. Using SSH or WebSockets alone
  does not require bypassing the input router.

  Call `start_probe/2` in the transport owner before starting a system-themed view.
  Pass raw terminal bytes through `feed/2` before decoding keyboard input and
  forward only the returned input. Store the returned session, including `nil`.
  Forward `{:theme_probe_timeout, key, ref}`, `{:theme_probe_drain_timeout, key, ref}`,
  and `{:theme_probe_escape_timeout, key, ref}` messages to `handle_timeout/2`, routing
  any returned input normally. Results populate Breeze's terminal palette cache
  and notify waiting views automatically.

  Keep feeding the session after its status becomes `:closed`: late replies are
  still consumed, including replies split across the drain deadline. Closing
  freezes the palette; `finished?` indicates whether a complete palette arrived.
  A standalone Escape is released after 50 ms so it cannot remain buffered
  indefinitely while waiting to distinguish it from an OSC reply prefix.
  """
  alias Breeze.Theme.Probe

  @escape_timeout_ms 50

  @doc "Starts a probe, writing queries and scheduling timeouts in the calling process."
  def start_probe(terminal, opts \\ []) do
    case Probe.start_runtime_palette_probe(terminal) do
      {:start, key, query} ->
        terminal = Termite.Terminal.write(terminal, query)
        ref = make_ref()
        timeout = Keyword.get(opts, :timeout, Probe.runtime_palette_probe_timeout_ms())
        timer = Process.send_after(self(), {:theme_probe_timeout, key, ref}, timeout)

        %{
          terminal: terminal,
          key: key,
          ref: ref,
          buffer: "",
          palette: %{},
          timeout: timeout,
          timer: timer,
          escape_ref: nil,
          escape_timer: nil,
          status: :active,
          finished?: false
        }

      _ ->
        nil
    end
  end

  @doc "Consumes palette replies, retaining fragmented replies and returning ordinary input."
  def feed(nil, data), do: {nil, data}

  def feed(%{status: :closed} = probe, data) do
    {nil, buffer, input} = consume(probe.buffer <> data, nil, "")
    {put_buffer(probe, buffer), input}
  end

  def feed(probe, data) do
    {palette, buffer, input} = consume(probe.buffer <> data, probe.palette, "")
    probe = put_buffer(%{probe | palette: palette}, buffer)

    if Probe.runtime_palette_probe_complete?(palette) and not probe.finished? do
      Probe.finish_runtime_palette_probe(probe.terminal, palette)
      {drain(%{probe | finished?: true}), input}
    else
      {probe, input}
    end
  end

  @doc "Handles timeout messages. Stale messages leave the session unchanged."
  def handle_timeout(
        %{key: key, ref: ref, status: :active} = probe,
        {:theme_probe_timeout, key, ref}
      ),
      do: {drain(probe), ""}

  def handle_timeout(
        %{key: key, ref: ref, status: :draining} = probe,
        {:theme_probe_drain_timeout, key, ref}
      ) do
    Process.cancel_timer(probe.timer)
    unless probe.finished?, do: Probe.finish_runtime_palette_probe(probe.terminal, probe.palette)
    # Retain the prefix even when the rest of a reply arrives after the deadline.
    {put_buffer(%{probe | status: :closed, timer: nil}, probe.buffer), ""}
  end

  def handle_timeout(
        %{key: key, escape_ref: ref, buffer: "\e"} = probe,
        {:theme_probe_escape_timeout, key, ref}
      )
      when is_reference(ref) do
    {put_buffer(probe, ""), "\e"}
  end

  def handle_timeout(probe, _message), do: {probe, ""}

  defp put_buffer(probe, buffer) do
    if timer = Map.get(probe, :escape_timer), do: Process.cancel_timer(timer)

    {ref, timer} =
      if buffer == "\e" do
        ref = make_ref()

        timer =
          Process.send_after(
            self(),
            {:theme_probe_escape_timeout, probe.key, ref},
            @escape_timeout_ms
          )

        {ref, timer}
      else
        {nil, nil}
      end

    Map.merge(probe, %{buffer: buffer, escape_ref: ref, escape_timer: timer})
  end

  defp drain(%{status: :draining} = probe), do: probe

  defp drain(probe) do
    Process.cancel_timer(probe.timer)

    timer =
      Process.send_after(
        self(),
        {:theme_probe_drain_timeout, probe.key, probe.ref},
        probe.timeout
      )

    %{probe | status: :draining, timer: timer}
  end

  defp consume("", palette, input), do: {palette, "", input}
  defp consume("\e", palette, input), do: {palette, "\e", input}

  defp consume("\e]" <> _ = data, palette, input) do
    case :binary.match(data, ["\a", "\e\\"]) do
      {offset, length} ->
        size = offset + length
        <<sequence::binary-size(^size), rest::binary>> = data

        if Regex.match?(~r/^\e\](?:10;|11;|4;\d+;)rgb:/, sequence) do
          palette =
            if is_map(palette) do
              {palette, _} = Probe.merge_runtime_palette_data("", palette, sequence)
              palette
            end

          consume(rest, palette, input)
        else
          consume(rest, palette, input <> sequence)
        end

      :nomatch when byte_size(data) <= 4096 ->
        {palette, data, input}

      :nomatch ->
        {palette, "", input <> data}
    end
  end

  defp consume(<<byte, rest::binary>>, palette, input),
    do: consume(rest, palette, input <> <<byte>>)
end
