defmodule Breeze.InputRouter do
  @moduledoc false

  use GenServer

  defstruct [:terminal, :reader, :server_pid, :halt_fun, global_keybindings: []]

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

    server_opts = Keyword.put(opts, :terminal, terminal)

    {:ok, server_pid} = Breeze.Server.start_app_link(server_opts)
    Process.monitor(server_pid)

    state = %__MODULE__{
      terminal: terminal,
      reader: reader,
      server_pid: server_pid,
      halt_fun: Keyword.get(opts, :halt_fun, fn -> System.halt() end),
      global_keybindings: Keyword.get(opts, :global_keybindings, [])
    }

    {:ok, state}
  end

  @impl true
  def handle_info({reader, {:data, data}}, %{reader: reader} = state) do
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

  def handle_info({reader, {:signal, :winch}} = message, %{reader: reader} = state) do
    send(state.server_pid, message)
    {:noreply, state}
  end

  def handle_info({reader, {:signal, :hup}}, %{reader: reader} = state) do
    stop(state)
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
    |> Termite.Screen.disable_mouse()
    |> Termite.Screen.clear_screen()
    |> Termite.Screen.show_cursor()
    |> Termite.Screen.exit_alt_screen()
    |> Termite.Terminal.write("\r")

    {:stop, :normal, state}
  end

  defp decode_input(raw_key) do
    Breeze.Input.decode(raw_key)
  end
end
