defmodule Breeze.Runtime.Context do
  @moduledoc """
  Read-only context passed to a runtime hook.

  A context represents one committed runtime lifecycle event. It is intended
  to be used only during the hook callback; tools should retain values read
  from it rather than the context itself.
  """

  alias Breeze.Runtime.State

  defstruct [:metadata, :capture_state, :frame, :inspector]

  @opaque t :: %__MODULE__{}

  @doc false
  def new(server_state, metadata) do
    screen = server_state.terminal.size || %{width: 0, height: 0}

    metadata =
      metadata
      |> Map.put_new(:server_pid, self())
      |> Map.put_new(:view, Map.get(server_state, :view))
      |> Map.put_new(:screen, screen)
      |> Map.put_new(:system_time, System.system_time(:millisecond))
      |> Map.put_new(:monotonic_time, System.monotonic_time(:millisecond))

    %__MODULE__{
      metadata: metadata,
      capture_state: fn opts -> State.capture_server(server_state, opts) end,
      frame: fn -> current_frame(server_state, screen) end,
      inspector: fn -> Breeze.Inspector.snapshot(server_state) end
    }
  end

  @doc "Returns metadata for the lifecycle event."
  @spec metadata(t()) :: map()
  def metadata(%__MODULE__{metadata: metadata}), do: metadata

  @doc "Returns the source server PID."
  @spec server_pid(t()) :: pid()
  def server_pid(%__MODULE__{} = context), do: context |> metadata() |> Map.fetch!(:server_pid)

  @doc "Returns the root view module."
  @spec view(t()) :: module()
  def view(%__MODULE__{} = context), do: context |> metadata() |> Map.fetch!(:view)

  @doc "Returns the terminal dimensions at this lifecycle point."
  @spec screen(t()) :: map()
  def screen(%__MODULE__{} = context), do: context |> metadata() |> Map.fetch!(:screen)

  @doc "Exports opaque runtime state at this lifecycle point."
  @spec capture_state(t(), keyword()) :: {:ok, State.t()} | {:error, term()}
  def capture_state(%__MODULE__{capture_state: capture}, opts \\ []) when is_list(opts),
    do: capture.(opts)

  @doc "Returns the terminal frame at this lifecycle point."
  @spec frame(t()) :: map()
  def frame(%__MODULE__{frame: frame}), do: frame.()

  @doc "Returns the inspector snapshot at this lifecycle point."
  @spec inspector(t()) :: map()
  def inspector(%__MODULE__{inspector: inspector}), do: inspector.()

  defp current_frame(state, screen) do
    %{
      width: Map.get(screen, :width, 0),
      height: Map.get(screen, :height, 0),
      lines: state.frame.last_lines || [],
      overlays: state.frame.last_overlays || []
    }
  end
end
