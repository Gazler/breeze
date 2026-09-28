defmodule Breeze.InputRouter.JobControl do
  @moduledoc false

  alias Termite.Terminal.Shell.SignalHandler

  defstruct [
    :executable,
    :signal_handler,
    :signal_ref,
    :input_mode,
    :command,
    enhanced_keyboard?: true
  ]

  # Assume all adapters support suspension. Only enable it for local sessions;
  # remote sessions must never stop the VM serving their other sessions.
  def start(%Termite.Terminal{}, opts, iex_shell_proxy \\ nil) do
    with true <- local_terminal?(iex_shell_proxy),
         {:unix, _} <- :os.type(),
         true <- Code.ensure_loaded?(:shell) and function_exported?(:shell, :start_interactive, 1),
         true <- :prim_tty.isatty(:stdin),
         true <- :prim_tty.isatty(:stdout),
         executable when is_binary(executable) <- System.find_executable("kill") do
      # A distinct reference prevents duplicate suspension if the adapter also
      # subscribes to TSTP through its :signals option.
      signal_ref = make_ref()

      %__MODULE__{
        executable: executable,
        signal_ref: signal_ref,
        signal_handler: SignalHandler.install(self(), signal_ref, [:tstp]),
        input_mode: &set_input_mode(&1, iex_shell_proxy),
        command: &System.cmd/3,
        enhanced_keyboard?: Keyword.get(opts, :enhanced_keyboard, true)
      }
    else
      _ -> nil
    end
  end

  defp local_terminal?(nil) do
    not iex_started?() and node(Process.group_leader()) == node()
  end

  defp local_terminal?(%{user_drv: user_drv}) when is_pid(user_drv) do
    # The proxy itself is local even for remote IEx. Check the terminal driver,
    # otherwise Ctrl+Z could stop the server node instead of the terminal's VM.
    node(user_drv) == node() and user_drv == Process.whereis(:user_drv)
  end

  defp local_terminal?(_proxy), do: false

  defp set_input_mode(mode, iex_shell_proxy) do
    case :shell.start_interactive({:noshell, mode}) do
      {:error, :already_started} when not is_nil(iex_shell_proxy) ->
        # IEx owns raw mode. The parent job-control shell saves/restores termios
        # around suspension, and OTP reapplies IEx's mode on SIGCONT.
        :ok

      result ->
        result
    end
  end

  defp iex_started? do
    Code.ensure_loaded?(IEx) and function_exported?(IEx, :started?, 0) and IEx.started?()
  end

  def stop(nil), do: :ok
  def stop(%__MODULE__{signal_handler: handler}), do: SignalHandler.uninstall(handler)

  # Called synchronously by the render server, so no frames can be written
  # between handing the terminal back to the shell and reclaiming it.
  def suspend(job, terminal_state) do
    terminal = leave_terminal(terminal_state, job.enhanced_keyboard?)

    result =
      try do
        with :ok <- job.input_mode.(:cooked) do
          # STOP cannot be intercepted by our TSTP handler. Address only this VM,
          # not the signal-sending helper or unrelated processes in a pipeline.
          case job.command.(job.executable, ["-s", "STOP", System.pid()], stderr_to_stdout: true) do
            {_output, 0} -> :ok
            {output, status} -> {:error, {:kill_failed, status, String.trim(output)}}
          end
        end
      rescue
        error -> {:error, error}
      after
        # Reclaim input before emitting any application escape sequences.
        :ok = job.input_mode.(:raw)
      end

    terminal = enter_terminal(terminal, terminal_state, job.enhanced_keyboard?)
    {result, terminal}
  end

  defp leave_terminal(state, enhanced_keyboard?) do
    terminal = state.terminal

    terminal =
      if enhanced_keyboard?,
        do: Termite.Screen.disable_enhanced_keyboard(terminal),
        else: terminal

    terminal =
      terminal
      |> Termite.Screen.disable_mouse()
      |> Termite.Screen.show_cursor()
      |> Termite.Terminal.write(Termite.Style.reset_code())

    if state.alt_screen_active? do
      Termite.Screen.exit_alt_screen(terminal)
    else
      terminal
      |> Termite.Screen.cursor_position(1, terminal.size.height)
      |> Termite.Terminal.write("\r\n")
    end
  end

  defp enter_terminal(terminal, state, enhanced_keyboard?) do
    terminal =
      if state.alt_screen_active?, do: Termite.Screen.alt_screen(terminal), else: terminal

    terminal =
      if enhanced_keyboard?, do: Termite.Screen.enable_enhanced_keyboard(terminal), else: terminal

    terminal = if state.hide_cursor?, do: Termite.Screen.hide_cursor(terminal), else: terminal

    terminal =
      case state.mouse_mode do
        true -> Termite.Screen.enable_mouse(terminal)
        opts when is_list(opts) -> Termite.Screen.enable_mouse(terminal, opts)
        _ -> terminal
      end

    Termite.Screen.clear_screen(terminal)
  end
end
