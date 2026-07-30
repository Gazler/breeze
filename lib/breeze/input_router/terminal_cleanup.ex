defmodule Breeze.InputRouter.TerminalCleanup do
  @moduledoc false

  defstruct [:guard, :terminal, alt_screen?: true, enhanced_keyboard?: true]

  def register(terminal, opts) do
    guard = :atomics.new(1, signed: false)
    :ok = :atomics.put(guard, 1, 1)

    cleanup = %__MODULE__{
      guard: guard,
      terminal: terminal,
      alt_screen?: Keyword.get(opts, :alt_screen?, true),
      enhanced_keyboard?: Keyword.get(opts, :enhanced_keyboard?, true)
    }

    register = Keyword.get(opts, :register, &System.at_exit/1)
    :ok = register.(fn _status -> restore_at_exit(cleanup) end)

    cleanup
  end

  def restore(%__MODULE__{} = cleanup, terminal \\ nil) do
    if claim(cleanup.guard) do
      terminal = terminal || cleanup.terminal
      {:restored, restore_terminal(terminal, cleanup)}
    else
      :already_restored
    end
  end

  defp claim(guard), do: :atomics.compare_exchange(guard, 1, 1, 0) == :ok

  defp restore_at_exit(cleanup) do
    _ = restore(cleanup)
    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp restore_terminal(terminal, cleanup) do
    terminal
    |> maybe_disable_enhanced_keyboard(cleanup.enhanced_keyboard?)
    |> Termite.Screen.disable_mouse()
    |> Termite.Screen.clear_screen()
    |> Termite.Screen.show_cursor()
    |> maybe_exit_alt_screen(cleanup.alt_screen?)
    |> Termite.Terminal.write("\r")
  end

  defp maybe_exit_alt_screen(terminal, true), do: Termite.Screen.exit_alt_screen(terminal)
  defp maybe_exit_alt_screen(terminal, false), do: terminal

  defp maybe_disable_enhanced_keyboard(terminal, true) do
    Termite.Screen.disable_enhanced_keyboard(terminal)
  end

  defp maybe_disable_enhanced_keyboard(terminal, false), do: terminal
end
