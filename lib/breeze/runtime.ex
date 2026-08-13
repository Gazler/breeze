defmodule Breeze.Runtime do
  @moduledoc """
  Generic runtime tooling for Breeze applications.

  Runtime state is an opaque in-VM value that can be captured, used to replace
  a running view tree, or started as an isolated runtime. Development tools can
  decide when to capture it through `Breeze.Runtime.Hook` without Breeze
  imposing storage, history, or debugger semantics.

  Pass the runtime controller PID to the server-oriented functions in this
  module. Runtime hooks and inspector snapshots report that PID; tooling that
  starts with a session can resolve it through `Breeze.Server.runtime_pid/1`.
  Root-view PIDs remain private and may change after state replacement.

  Runtime state can contain arbitrary application terms. It is intended for
  short-lived use in the same BEAM instance, not serialization, durable
  persistence, or transfer between Breeze versions.

  Replacing or starting from runtime state does not invoke `mount/2`.
  Replacement is transactional: Breeze keeps the current view tree active
  unless the candidate tree starts and renders successfully.
  """

  alias Breeze.Runtime.State

  @default_size %{width: 80, height: 24}

  defstruct [:pid, :terminal]

  @type t :: %__MODULE__{
          pid: pid(),
          terminal: %Termite.Terminal{}
        }

  @doc "Exports opaque state from a running Breeze session."
  @spec capture_state(pid(), keyword()) :: {:ok, State.t()} | {:error, term()}
  def capture_state(server_pid, opts \\ []) when is_pid(server_pid) and is_list(opts) do
    Breeze.Server.runtime_state(server_pid, opts)
  end

  @doc """
  Replaces a running Breeze application's view runtime with exported state.

  Returns an error without changing the running view tree when startup or the
  candidate render fails.
  """
  @spec replace_state(pid(), State.t()) :: :ok | {:error, term()}
  def replace_state(server_pid, %State{} = runtime_state) when is_pid(server_pid) do
    Breeze.Server.replace_state(server_pid, runtime_state)
  end

  @doc "Pauses the current runtime frame until the next application interaction."
  @spec pause(pid()) :: :ok | {:error, term()}
  def pause(server_pid) when is_pid(server_pid), do: Breeze.Server.pause_runtime(server_pid)

  @doc """
  Displays a frame in a running Breeze application.

  Pass `:live` as the frame to return to the application's current output.
  Displaying another frame pauses the view runtime until live output is
  restored.
  """
  @spec display_frame(pid(), :live | map(), keyword()) :: :ok | {:error, term()}
  def display_frame(server_pid, frame, opts \\ [])
      when is_pid(server_pid) and (frame == :live or is_map(frame)) and is_list(opts) do
    Breeze.Server.display_frame(server_pid, frame, opts)
  end

  @doc "Starts an isolated runtime from exported state."
  @spec start_from_state(State.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def start_from_state(%State{root: root} = runtime_state, opts \\ []) do
    terminal =
      Keyword.get_lazy(opts, :terminal, fn ->
        opts
        |> Keyword.get(:screen)
        |> memory_terminal()
      end)

    theme_override? = Keyword.has_key?(opts, :theme)
    theme = Keyword.get(opts, :theme, root.term.theme_source || root.term.theme)

    child_opts = [
      view: runtime_state.view,
      start_opts: runtime_state.start_opts,
      terminal: terminal,
      theme: theme,
      theme_source: Keyword.get(opts, :theme, root.term.theme_source),
      apply_theme_defaults?:
        if(theme_override?,
          do: Breeze.Theme.defaults_enabled?(theme),
          else: root.term.apply_theme_defaults?
        ),
      global_keybindings: root.term.global_keybindings,
      render_tree?: Keyword.get(opts, :render_tree?, false),
      runtime_state: root,
      restore_state_theme?: not theme_override?,
      invalidate: Keyword.get(opts, :invalidate, fn _child_id -> :ok end)
    ]

    with {:ok, pid} <- Breeze.ChildServer.start(child_opts) do
      {:ok, %__MODULE__{pid: pid, terminal: terminal}}
    end
  end

  @doc "Renders an isolated runtime and returns its terminal content."
  @spec render(t(), keyword()) :: {:ok, String.t()} | term()
  def render(%__MODULE__{} = runtime, opts \\ []) do
    render_opts =
      opts
      |> Keyword.put_new(:terminal, runtime.terminal)
      |> Keyword.put_new(:implicit_state, %{})

    case Breeze.ChildServer.render_snapshot(runtime.pid, render_opts) do
      {:ok, _acc, box, _decorations} -> {:ok, box.content}
      other -> other
    end
  end

  @doc "Returns rendered content, view metadata, and screen dimensions."
  @spec snapshot(t(), keyword()) :: {:ok, map()} | term()
  def snapshot(%__MODULE__{} = runtime, opts \\ []) do
    with {:ok, content} <- render(runtime, opts) do
      metadata = Breeze.ChildServer.metadata(runtime.pid)

      {:ok,
       %{
         content: content,
         metadata: metadata,
         screen: runtime.terminal.size
       }}
    end
  end

  @doc "Dispatches decoded terminal input to an isolated runtime."
  @spec input(t(), term(), keyword()) :: term()
  def input(%__MODULE__{} = runtime, input, opts \\ []) do
    Breeze.ChildServer.dispatch_input(runtime.pid, input, opts)
  end

  @doc "Dispatches a named event and payload to an isolated runtime."
  @spec event(t(), term(), map()) :: term()
  def event(%__MODULE__{} = runtime, change, event) do
    Breeze.ChildServer.dispatch_event(runtime.pid, change, event)
  end

  @doc "Dispatches a message to an isolated runtime's `handle_info/2` callback."
  @spec info(t(), term()) :: term()
  def info(%__MODULE__{} = runtime, message) do
    Breeze.ChildServer.dispatch_info(runtime.pid, message, runtime.terminal)
  end

  @doc "Stops an isolated runtime."
  @spec stop(t()) :: :ok
  def stop(%__MODULE__{pid: pid}) do
    if is_pid(pid) and Process.alive?(pid), do: GenServer.stop(pid, :normal)
    :ok
  end

  defp memory_terminal(size), do: %Termite.Terminal{size: normalize_size(size)}

  defp normalize_size({width, height}) when is_integer(width) and is_integer(height),
    do: %{width: width, height: height}

  defp normalize_size(%{width: width, height: height})
       when is_integer(width) and is_integer(height),
       do: %{width: width, height: height}

  defp normalize_size(_size), do: @default_size
end
