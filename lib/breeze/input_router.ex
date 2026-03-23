defmodule Breeze.InputRouter do
  @moduledoc false

  use GenServer

  defstruct [
    :terminal,
    :reader,
    :server_pid,
    :halt_fun,
    :theme_probe,
    global_keybindings: []
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    hide_cursor? = Keyword.get(opts, :hide_cursor, true)
    mouse = Keyword.get(opts, :mouse, false)
    terminal = build_terminal(opts)
    reader = terminal.reader
    terminal = if hide_cursor?, do: Termite.Screen.hide_cursor(terminal), else: terminal
    terminal = enable_mouse(terminal, mouse)
    terminal = Termite.Screen.clear_screen(terminal)

    {terminal, deferred_messages} =
      maybe_complete_initial_theme_probe(terminal, Keyword.get(opts, :theme))

    server_opts =
      opts
      |> Keyword.put(:terminal, terminal)
      |> Keyword.put(:input_router, self())

    {:ok, server_pid} = Breeze.Server.start_app_link(server_opts)
    Process.monitor(server_pid)

    state = %__MODULE__{
      terminal: terminal,
      reader: reader,
      server_pid: server_pid,
      halt_fun: Keyword.get(opts, :halt_fun, fn -> System.halt() end),
      global_keybindings: Keyword.get(opts, :global_keybindings, [])
    }

    Enum.each(Enum.reverse(deferred_messages), &send(self(), &1))

    {:ok, state, {:continue, {:maybe_start_theme_probe, Keyword.get(opts, :theme)}}}
  end

  @impl true
  def handle_continue({:maybe_start_theme_probe, theme}, state) do
    {:noreply, maybe_start_theme_probe(state, theme)}
  end

  @impl true
  def handle_info({reader, {:data, data}}, %{reader: reader} = state) do
    cond do
      is_map(state.theme_probe) and is_binary(data) and String.starts_with?(data, "\e]") ->
        {:noreply, consume_theme_probe_reply(state, data)}

      true ->
        case decode_input(data) do
          {:key, key} ->
            if stop_global_key?(key, state) do
              stop(state)
            else
              send(state.server_pid, {reader, {:data, data}})
              {:noreply, state}
            end

          _decoded ->
            send(state.server_pid, {reader, {:data, data}})
            {:noreply, state}
        end
    end
  end

  def handle_info({reader, {:signal, :winch}} = message, %{reader: reader} = state) do
    send(state.server_pid, message)
    {:noreply, state}
  end

  def handle_info({reader, {:signal, :hup}}, %{reader: reader} = state) do
    stop(state)
  end

  def handle_info({:ensure_runtime_palette, :system}, state) do
    {:noreply, maybe_start_theme_probe(state, :system)}
  end

  def handle_info(
        {:theme_probe_timeout, key},
        %{theme_probe: %{key: key, palette: palette}} = state
      ) do
    Breeze.Theme.finish_runtime_palette_probe(state.terminal, palette)
    {:noreply, %{state | theme_probe: nil}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{server_pid: pid} = state) do
    stop(state)
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, Breeze.Server.stats(state.server_pid), state}
  end

  @impl true
  def terminate(_reason, state) do
    state.halt_fun.()
    :ok
  end

  defp stop_global_key?(key, state),
    do: Breeze.GlobalKeybindings.stop_action?(%{"key" => key}, state)

  defp maybe_start_theme_probe(%{theme_probe: probe} = state, _theme) when is_map(probe),
    do: state

  defp maybe_start_theme_probe(state, theme) do
    if requested_system_theme?(theme) do
      case Breeze.Theme.start_runtime_palette_probe(state.terminal) do
        {:start, key, query} ->
          terminal = Termite.Terminal.write(state.terminal, query)

          timer =
            Process.send_after(
              self(),
              {:theme_probe_timeout, key},
              Breeze.Theme.runtime_palette_probe_timeout_ms()
            )

          %{
            state
            | terminal: terminal,
              theme_probe: %{key: key, buffer: "", palette: %{}, timer: timer}
          }

        _ ->
          state
      end
    else
      state
    end
  end

  defp requested_system_theme?(:system), do: true

  defp requested_system_theme?(%Breeze.Theme{mode: :system}), do: true

  defp requested_system_theme?(%Breeze.Theme{variables: %{requested_theme: :system}}), do: true

  defp requested_system_theme?(_theme), do: false

  defp consume_theme_probe_reply(%{theme_probe: probe} = state, data) do
    {palette, buffer} = Breeze.Theme.merge_runtime_palette_data(probe.buffer, probe.palette, data)

    probe = %{probe | palette: palette, buffer: buffer}

    if Breeze.Theme.runtime_palette_probe_complete?(palette) do
      Process.cancel_timer(probe.timer)
      Breeze.Theme.finish_runtime_palette_probe(state.terminal, palette)
      %{state | theme_probe: nil}
    else
      %{state | theme_probe: probe}
    end
  end

  defp maybe_complete_initial_theme_probe(terminal, theme) do
    if requested_system_theme?(theme) do
      case Breeze.Theme.start_runtime_palette_probe(terminal) do
        {:start, _key, query} ->
          terminal = Termite.Terminal.write(terminal, query)

          {palette, deferred_messages} =
            collect_initial_theme_probe_replies(
              terminal.reader,
              System.monotonic_time(:millisecond) +
                Breeze.Theme.runtime_palette_probe_timeout_ms(),
              "",
              %{},
              []
            )

          _status = Breeze.Theme.finish_runtime_palette_probe(terminal, palette)
          {terminal, deferred_messages}

        _ ->
          {terminal, []}
      end
    else
      {terminal, []}
    end
  end

  defp collect_initial_theme_probe_replies(reader, deadline, buffer, palette, deferred_messages) do
    if Breeze.Theme.runtime_palette_probe_complete?(palette) do
      {palette, deferred_messages}
    else
      timeout = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {^reader, {:data, data}} = message when is_binary(data) ->
          if String.starts_with?(data, "\e]") do
            {palette, buffer} = Breeze.Theme.merge_runtime_palette_data(buffer, palette, data)

            collect_initial_theme_probe_replies(
              reader,
              deadline,
              buffer,
              palette,
              deferred_messages
            )
          else
            collect_initial_theme_probe_replies(
              reader,
              deadline,
              buffer,
              palette,
              [message | deferred_messages]
            )
          end

        message ->
          collect_initial_theme_probe_replies(
            reader,
            deadline,
            buffer,
            palette,
            [message | deferred_messages]
          )
      after
        timeout ->
          {palette, deferred_messages}
      end
    end
  end

  defp enable_mouse(terminal, false), do: terminal
  defp enable_mouse(terminal, nil), do: terminal
  defp enable_mouse(terminal, true), do: Termite.Screen.enable_mouse(terminal)

  defp enable_mouse(terminal, opts) when is_list(opts),
    do: Termite.Screen.enable_mouse(terminal, opts)

  defp build_terminal(opts) do
    case Keyword.get(opts, :terminal) do
      %Termite.Terminal{} = terminal ->
        terminal

      nil ->
        Termite.Terminal.start(Keyword.get(opts, :terminal_opts, []))
    end
  end

  defp stop(state) do
    if Process.alive?(state.server_pid) do
      GenServer.stop(state.server_pid, :normal, 1_000)
    end

    {:stop, :normal, state}
  end

  defp decode_input(raw_key) do
    Breeze.Input.decode(raw_key)
  end
end
