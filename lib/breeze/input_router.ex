defmodule Breeze.InputRouter do
  @moduledoc false

  use GenServer

  defstruct [
    :terminal,
    :reader,
    :server_pid,
    :halt_fun,
    :theme_probe,
    :render_mode,
    alt_screen?: true,
    enhanced_keyboard?: true,
    global_keybindings: []
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    render_mode = normalize_render_mode(Keyword.get(opts, :render_mode, :screen))
    alt_screen? = if render_mode == :inline, do: false, else: Keyword.get(opts, :alt_screen, true)
    hide_cursor? = Keyword.get(opts, :hide_cursor, true)
    enhanced_keyboard? = Keyword.get(opts, :enhanced_keyboard, true)
    mouse = Keyword.get(opts, :mouse, false)
    terminal = build_terminal(opts)
    reader = terminal.reader
    terminal = if alt_screen?, do: Termite.Screen.alt_screen(terminal), else: terminal
    terminal = if enhanced_keyboard?, do: enable_enhanced_keyboard(terminal), else: terminal
    terminal = if hide_cursor?, do: Termite.Screen.hide_cursor(terminal), else: terminal
    terminal = enable_mouse(terminal, mouse)
    terminal = maybe_clear_screen(terminal, render_mode)

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
      render_mode: render_mode,
      alt_screen?: alt_screen?,
      enhanced_keyboard?: enhanced_keyboard?,
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
    do:
      Breeze.GlobalKeybindings.stop_action?(normalize_key_event(key), state) and
        not focused_implicit_captures_printable_key?(key, state)

  defp focused_implicit_captures_printable_key?(key, state) do
    printable_key?(key) and
      match?(
        %{captures_printable_keys: true},
        Breeze.Server.focused_implicit_metadata(state.server_pid)
      )
  catch
    :exit, _reason -> false
  end

  defp printable_key?(%{"key" => key} = event) when is_binary(key) do
    not truthy_modifier?(Map.get(event, "ctrlKey")) and
      not truthy_modifier?(Map.get(event, "altKey")) and
      not truthy_modifier?(Map.get(event, "metaKey")) and
      printable_key?(key)
  end

  defp printable_key?(key) when is_binary(key) do
    String.length(key) == 1 and key not in ["\n", "\r", "\t", "\v", "\f"] and
      String.printable?(key) and not String.match?(key, ~r/[\x00-\x1F\x7F]/u)
  end

  defp printable_key?(_key), do: false

  defp truthy_modifier?(value), do: value in [true, "true"]

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

  defp requested_system_theme?(theme), do: Breeze.Theme.requested_system?(theme)

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
      Process.exit(state.server_pid, :normal)
    end

    state.terminal
    |> maybe_disable_enhanced_keyboard(state)
    |> Termite.Screen.disable_mouse()
    |> maybe_clear_screen(state.render_mode)
    |> Termite.Screen.show_cursor()
    |> maybe_exit_alt_screen(state)
    |> Termite.Terminal.write("\r")

    {:stop, :normal, state}
  end

  defp maybe_exit_alt_screen(terminal, %{alt_screen?: true}),
    do: Termite.Screen.exit_alt_screen(terminal)

  defp maybe_exit_alt_screen(terminal, _state), do: terminal

  defp maybe_clear_screen(terminal, :inline), do: terminal
  defp maybe_clear_screen(terminal, _mode), do: Termite.Screen.clear_screen(terminal)

  defp normalize_render_mode(:inline), do: :inline
  defp normalize_render_mode(:screen), do: :screen
  defp normalize_render_mode(nil), do: :screen

  defp normalize_render_mode(other) do
    raise ArgumentError, "invalid render_mode #{inspect(other)}. Expected :screen or :inline"
  end

  defp enable_enhanced_keyboard(terminal) do
    Termite.Screen.enable_enhanced_keyboard(terminal)
  end

  defp maybe_disable_enhanced_keyboard(terminal, %{enhanced_keyboard?: true}) do
    Termite.Screen.disable_enhanced_keyboard(terminal)
  end

  defp maybe_disable_enhanced_keyboard(terminal, _state), do: terminal

  defp decode_input(raw_key) do
    Breeze.Input.decode(raw_key)
  end

  defp normalize_key_event(%{"key" => _} = event), do: event
  defp normalize_key_event(key), do: %{"key" => key}
end
