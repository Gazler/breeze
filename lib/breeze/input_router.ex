defmodule Breeze.InputRouter do
  @moduledoc false

  use GenServer

  alias Breeze.InputRouter.{IExShellProxy, SilentGroupLeader, TerminalStart}
  alias Breeze.InputCapture

  defstruct [
    :terminal,
    :reader,
    :server_pid,
    :halt_fun,
    :theme_probe,
    :iex_shell_proxy,
    :silent_group_leader,
    alt_screen?: true,
    enhanced_keyboard?: true,
    global_keybindings: []
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def start(opts) do
    GenServer.start(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    opts = maybe_put_iex_terminal_size_override(opts)
    alt_screen? = Keyword.get(opts, :alt_screen, true)
    hide_cursor? = Keyword.get(opts, :hide_cursor, true)
    enhanced_keyboard? = Keyword.get(opts, :enhanced_keyboard, true)
    mouse = Keyword.get(opts, :mouse, false)

    %TerminalStart{
      terminal: terminal,
      iex_shell_proxy: iex_shell_proxy,
      silent_group_leader: silent_group_leader
    } = build_terminal(opts)

    reader = terminal.reader
    terminal = if alt_screen?, do: Termite.Screen.alt_screen(terminal), else: terminal
    terminal = if enhanced_keyboard?, do: enable_enhanced_keyboard(terminal), else: terminal
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
      halt_fun: Keyword.get_lazy(opts, :halt_fun, &default_halt_fun/0),
      alt_screen?: alt_screen?,
      enhanced_keyboard?: enhanced_keyboard?,
      iex_shell_proxy: iex_shell_proxy,
      silent_group_leader: silent_group_leader,
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
    if theme_probe_reply?(state, data) do
      {:noreply, consume_theme_probe_reply(state, data)}
    else
      route_reader_data(reader, data, state)
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
    IExShellProxy.stop(state.iex_shell_proxy)
    SilentGroupLeader.stop(state.silent_group_leader)
    state.halt_fun.()
    :ok
  end

  defp stop_global_key?(key, state),
    do:
      Breeze.GlobalKeybindings.stop_action?(normalize_key_event(key), state) and
        not focused_implicit_captures_key?(key, state)

  defp route_reader_data(reader, data, state) do
    decoded = decode_input(data)

    cond do
      forced_stop_input?(data, decoded) and
          not focused_implicit_captures_decoded_input?(decoded, state) ->
        stop(state)

      stop_decoded_input?(decoded, state) ->
        stop(state)

      true ->
        forward_reader_data(reader, data, state)
    end
  end

  defp forward_reader_data(reader, data, state) do
    send(state.server_pid, {reader, {:data, data}})
    {:noreply, state}
  end

  defp theme_probe_reply?(state, data) do
    is_map(state.theme_probe) and is_binary(data) and String.starts_with?(data, "\e]")
  end

  defp stop_decoded_input?({:key, key}, state), do: stop_global_key?(key, state)
  defp stop_decoded_input?(_decoded, _state), do: false

  defp forced_stop_input?("\x03", _decoded), do: true

  defp forced_stop_input?(_data, {:key, %{"ctrlKey" => true, "key" => key}}),
    do: key in ["c", "C"]

  defp forced_stop_input?(_data, {:key, %{"ctrlKey" => "true", "key" => key}}),
    do: key in ["c", "C"]

  defp forced_stop_input?(_data, _decoded), do: false

  defp focused_implicit_captures_decoded_input?({:key, key}, state),
    do: focused_implicit_captures_key?(key, state)

  defp focused_implicit_captures_decoded_input?(_decoded, _state), do: false

  defp focused_implicit_captures_key?(key, state) do
    state.server_pid
    |> Breeze.Server.focused_implicit_metadata()
    |> InputCapture.captures_key?(key)
  catch
    :exit, _reason -> false
  end

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
        %TerminalStart{terminal: terminal}

      nil ->
        %TerminalStart{terminal: terminal, silent_group_leader: silent_group_leader} =
          start_terminal(opts)

        iex_shell_proxy = maybe_replace_iex_shell_reader(terminal, opts)
        terminal = Termite.Terminal.resize(terminal)

        %TerminalStart{
          terminal: terminal,
          iex_shell_proxy: iex_shell_proxy,
          silent_group_leader: silent_group_leader
        }
    end
  end

  defp start_terminal(opts) do
    if Keyword.get(opts, :pause_iex, false) and iex_started?() do
      start_terminal_with_silent_group_leader(Keyword.get(opts, :terminal_opts, []))
    else
      %TerminalStart{terminal: Termite.Terminal.start(Keyword.get(opts, :terminal_opts, []))}
    end
  end

  defp maybe_put_iex_terminal_size_override(opts) do
    if Keyword.get(opts, :pause_iex, false) and iex_started?() do
      # IEx keeps the physical bottom row for prompt editing after a resize.
      # Let Breeze render inside the rows that remain stable while IEx is paused.
      Keyword.put_new(opts, :terminal_size_override, &reserve_iex_prompt_row/1)
    else
      opts
    end
  end

  defp reserve_iex_prompt_row(%{height: height} = size) when is_integer(height) do
    %{size | height: max(height - 1, 1)}
  end

  defp reserve_iex_prompt_row(size), do: size

  defp start_terminal_with_silent_group_leader(terminal_opts) do
    original_group_leader = Process.group_leader()

    {:ok, silent_group_leader} = SilentGroupLeader.start_link()

    try do
      Process.group_leader(self(), silent_group_leader)

      %TerminalStart{
        terminal: Termite.Terminal.start(terminal_opts),
        silent_group_leader: silent_group_leader
      }
    after
      Process.group_leader(self(), original_group_leader)
    end
  end

  defp maybe_replace_iex_shell_reader(
         %Termite.Terminal{
           adapter: {Termite.Terminal.Shell, %Termite.Terminal.Shell{pid: shell_pid}}
         },
         opts
       ) do
    if Keyword.get(opts, :pause_iex, false) and iex_started?() do
      replace_shell_reader(shell_pid)
    end
  end

  defp maybe_replace_iex_shell_reader(_terminal, _opts), do: nil

  defp replace_shell_reader(shell_pid) when is_pid(shell_pid) do
    with %{reader: reader} when is_pid(reader) <- :sys.get_state(shell_pid),
         true <- Process.alive?(reader),
         {:ok, iex_shell_proxy} <- IExShellProxy.start_link(shell_pid) do
      unlink_shell_reader(shell_pid, reader)
      Process.exit(reader, :kill)
      iex_shell_proxy
    else
      _ -> nil
    end
  catch
    _kind, _reason -> nil
  end

  defp unlink_shell_reader(shell_pid, reader) do
    :sys.replace_state(shell_pid, fn state ->
      Process.unlink(reader)
      state
    end)

    :ok
  catch
    _kind, _reason -> :ok
  end

  defp default_halt_fun do
    if iex_started?() do
      fn -> :ok end
    else
      fn -> System.halt() end
    end
  end

  defp iex_started? do
    Code.ensure_loaded?(IEx) and function_exported?(IEx, :started?, 0) and IEx.started?()
  end

  defp stop(state) do
    if Process.alive?(state.server_pid) do
      Process.unlink(state.server_pid)
      Process.exit(state.server_pid, :shutdown)
    end

    state.terminal
    |> maybe_disable_enhanced_keyboard(state)
    |> Termite.Screen.disable_mouse()
    |> Termite.Screen.clear_screen()
    |> Termite.Screen.show_cursor()
    |> maybe_exit_alt_screen(state)
    |> Termite.Terminal.write("\r")

    {:stop, :normal, state}
  end

  defp maybe_exit_alt_screen(terminal, %{alt_screen?: true}),
    do: Termite.Screen.exit_alt_screen(terminal)

  defp maybe_exit_alt_screen(terminal, _state), do: terminal

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
