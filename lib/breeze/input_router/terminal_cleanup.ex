defmodule Breeze.InputRouter.TerminalCleanup do
  @moduledoc false

  defstruct [:guard, :terminal, alt_screen?: true, enhanced_keyboard?: true]

  def register(terminal, opts) do
    guard = :atomics.new(2, signed: false)
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

  # Shared with the runtime and the at-exit callback, even after the runtime exits.
  def preserve_screen(nil, _preserve?), do: :ok

  def preserve_screen(%__MODULE__{guard: guard}, preserve?) do
    :atomics.put(guard, 2, if(preserve?, do: 1, else: 0))
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
    preserve? = :atomics.get(cleanup.guard, 2) == 1

    terminal
    |> maybe_disable_enhanced_keyboard(cleanup.enhanced_keyboard?)
    |> Termite.Screen.disable_mouse()
    |> maybe_clear_screen(preserve?)
    |> Termite.Screen.show_cursor()
    |> maybe_exit_alt_screen(cleanup.alt_screen? and not preserve?)
    |> Termite.Terminal.write("\r")
  end

  defp maybe_clear_screen(terminal, true), do: terminal
  defp maybe_clear_screen(terminal, false), do: Termite.Screen.clear_screen(terminal)

  defp maybe_exit_alt_screen(terminal, true), do: Termite.Screen.exit_alt_screen(terminal)
  defp maybe_exit_alt_screen(terminal, false), do: terminal

  defp maybe_disable_enhanced_keyboard(terminal, true) do
    Termite.Screen.disable_enhanced_keyboard(terminal)
  end

  defp maybe_disable_enhanced_keyboard(terminal, false), do: terminal
end
