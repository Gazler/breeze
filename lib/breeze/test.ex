defmodule Breeze.Test do
  @moduledoc """
  Public helpers for deterministic Breeze view tests.

  `Breeze.Test` can render a view against a fixed terminal size, dispatch input
  and events without starting the interactive server.
  """

  defstruct [:pid, :terminal]

  alias Breeze.ChildServer

  @type t :: %__MODULE__{pid: pid(), terminal: Termite.Terminal.t()}

  @default_size %{width: 80, height: 24}

  def start(view, opts \\ []) do
    terminal =
      Keyword.get(opts, :terminal, build_terminal(Keyword.get(opts, :size, @default_size)))

    child_opts = [
      view: view,
      terminal: terminal,
      start_opts: Keyword.get(opts, :start_opts, []),
      global_keybindings: Keyword.get(opts, :global_keybindings, [])
    ]

    with {:ok, pid} <- ChildServer.start(child_opts) do
      {:ok, %__MODULE__{pid: pid, terminal: terminal}}
    end
  end

  def start!(view, opts \\ []) do
    {:ok, session} = start(view, opts)
    session
  end

  def render(%__MODULE__{} = session, opts \\ []) do
    render_opts =
      opts
      |> Keyword.put_new(:terminal, session.terminal)
      |> Keyword.put_new(:implicit_state, %{})

    case ChildServer.render_snapshot(session.pid, render_opts) do
      {:ok, _acc, box, _decorations} -> {:ok, box.content}
      other -> other
    end
  end

  def render!(%__MODULE__{} = session, opts \\ []) do
    {:ok, content} = render(session, opts)
    content
  end

  def input(%__MODULE__{} = session, key) do
    ChildServer.dispatch_input(session.pid, key)
  end

  def event(%__MODULE__{} = session, change, event) do
    ChildServer.dispatch_event(session.pid, change, event)
  end

  def info(%__MODULE__{} = session, message) do
    ChildServer.dispatch_info(session.pid, message, session.terminal)
  end

  def metadata(%__MODULE__{} = session) do
    ChildServer.metadata(session.pid)
  end

  def stop(%__MODULE__{pid: pid}) when is_pid(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    :ok
  end

  defp build_terminal({width, height}) when is_integer(width) and is_integer(height) do
    %Termite.Terminal{size: %{width: width, height: height}}
  end

  defp build_terminal(%{width: width, height: height})
       when is_integer(width) and is_integer(height) do
    %Termite.Terminal{size: %{width: width, height: height}}
  end
end
