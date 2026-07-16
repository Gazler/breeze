defmodule Breeze.Test do
  @moduledoc """
  Public helpers for deterministic Breeze view tests.

  `Breeze.Test` can render a view against a fixed terminal size, dispatch input
  and events without starting the interactive server.

  ## Example

  ```elixir
  defmodule MyApp.CounterTest do
    use ExUnit.Case, async: true

    test "counter snapshot" do
      session = Breeze.Test.start!(MyApp.CounterView, size: {30, 5})
      on_exit(fn -> Breeze.Test.stop(session) end)

      assert Breeze.Test.render!(session) =~ "Counter: 0"

      assert {:noreply, _focused, true} = Breeze.Test.input(session, "ArrowUp")
      assert Breeze.Test.render!(session) =~ "Counter: 1"
    end
  end
  ```
  """

  defstruct [:pid, :terminal]

  alias Breeze.ChildServer

  @typedoc "A deterministic view-test session."
  @type t :: %__MODULE__{pid: pid(), terminal: %Termite.Terminal{}}

  @default_size %{width: 80, height: 24}

  @doc """
  Starts a deterministic test session for `view`.

  Options include:

    * `:size` - terminal size as `{width, height}` or a dimensions map. Defaults
      to `80x24`.
    * `:terminal` - an existing `%Termite.Terminal{}`. Takes precedence over
      `:size`.
    * `:theme` - the theme used to render the view.
    * `:start_opts` - options passed to the view's `mount/2` callback.
    * `:global_keybindings` - keybindings active for the test session.
  """
  @spec start(module(), keyword()) :: {:ok, t()} | {:error, term()}
  def start(view, opts \\ []) do
    terminal =
      Keyword.get(opts, :terminal, build_terminal(Keyword.get(opts, :size, @default_size)))

    child_opts = [
      view: view,
      terminal: terminal,
      theme: Keyword.get(opts, :theme),
      theme_source: Keyword.get(opts, :theme),
      apply_theme_defaults?: Breeze.Theme.defaults_enabled?(Keyword.get(opts, :theme)),
      start_opts: Keyword.get(opts, :start_opts, []),
      global_keybindings: Keyword.get(opts, :global_keybindings, [])
    ]

    with {:ok, pid} <- ChildServer.start(child_opts) do
      {:ok, %__MODULE__{pid: pid, terminal: terminal}}
    end
  end

  @doc "Starts a deterministic test session and returns it, raising on failure."
  @spec start!(module(), keyword()) :: t()
  def start!(view, opts \\ []) do
    {:ok, session} = start(view, opts)
    session
  end

  @doc "Renders the current view state and returns its terminal content."
  @spec render(t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def render(%__MODULE__{} = session, opts \\ []) do
    render_opts =
      opts
      |> Keyword.put_new(:terminal, session.terminal)
      |> Keyword.put_new(:implicit_state, %{})
      |> Keyword.put_new(:theme_source, Keyword.get(opts, :theme))

    case ChildServer.render_snapshot(session.pid, render_opts) do
      {:ok, _acc, box, _decorations} -> {:ok, box.content}
      other -> other
    end
  end

  @doc "Renders the current view state, raising on failure."
  @spec render!(t(), keyword()) :: String.t()
  def render!(%__MODULE__{} = session, opts \\ []) do
    {:ok, content} = render(session, opts)
    content
  end

  @doc "Dispatches a decoded key or input event to the view."
  @spec input(t(), term()) :: term()
  def input(%__MODULE__{} = session, key) do
    ChildServer.dispatch_input(session.pid, key)
  end

  @doc "Dispatches a named event and unrestricted payload directly to the view."
  @spec event(t(), Breeze.View.event_name(), Breeze.View.named_event_payload()) :: term()
  def event(%__MODULE__{} = session, change, event) do
    ChildServer.dispatch_event(session.pid, change, event)
  end

  @doc "Dispatches a message to the view's `handle_info/2` callback."
  @spec info(t(), term()) :: term()
  def info(%__MODULE__{} = session, message) do
    ChildServer.dispatch_info(session.pid, message, session.terminal)
  end

  @doc "Returns the current metadata for the view session."
  @spec metadata(t()) :: term()
  def metadata(%__MODULE__{} = session) do
    ChildServer.metadata(session.pid)
  end

  @doc "Stops a test session."
  @spec stop(t()) :: :ok
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
