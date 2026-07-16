defmodule Breeze.RemoteInspector.AppConnector do
  @moduledoc false

  use GenServer

  @retry_interval 250

  def start_link(app_pid, opts \\ []) when is_pid(app_pid) and is_list(opts) do
    GenServer.start_link(__MODULE__, {app_pid, opts})
  end

  def child_spec({app_pid, opts}) do
    %{
      id: {__MODULE__, app_pid},
      start: {__MODULE__, :start_link, [app_pid, opts]},
      restart: :transient,
      type: :worker
    }
  end

  @impl true
  def init({app_pid, opts}) do
    state = %{
      app_pid: app_pid,
      app_ref: Process.monitor(app_pid),
      inspector_ref: nil,
      resolver: Keyword.get(opts, :resolver, &Breeze.RemoteInspector.connect_app_to_inspector/0),
      retry_interval: Keyword.get(opts, :retry_interval, @retry_interval),
      snapshot_reader:
        Keyword.get(opts, :snapshot_reader, &Breeze.Server.Diagnostics.inspector_snapshot/1),
      publisher: Keyword.get(opts, :publisher, &Breeze.RemoteInspector.Server.publish/3)
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state), do: connect(state)

  @impl true
  def handle_info(:connect, state), do: connect(state)

  def handle_info(
        {:DOWN, app_ref, :process, app_pid, _reason},
        %{app_ref: app_ref, app_pid: app_pid} = state
      ) do
    {:stop, :normal, state}
  end

  def handle_info(
        {:DOWN, inspector_ref, :process, _pid, _reason},
        %{inspector_ref: inspector_ref} = state
      )
      when is_reference(inspector_ref) do
    connect(%{state | inspector_ref: nil})
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp connect(state) do
    case resolve(state.resolver) do
      {:ok, inspector_pid} when is_pid(inspector_pid) ->
        case publish_current_snapshot(inspector_pid, state) do
          :ok ->
            inspector_ref = Process.monitor(inspector_pid)
            {:noreply, %{state | inspector_ref: inspector_ref}}

          :retry ->
            retry_connect(state)
        end

      :disabled ->
        {:stop, :normal, state}

      _retry ->
        retry_connect(state)
    end
  end

  defp retry_connect(state) do
    Process.send_after(self(), :connect, state.retry_interval)
    {:noreply, state}
  end

  defp resolve(resolver), do: retry_on_failure(resolver)

  defp publish_current_snapshot(inspector_pid, state) do
    retry_on_failure(fn ->
      snapshot = state.snapshot_reader.(state.app_pid)
      publish_snapshot(snapshot, inspector_pid, state)
    end)
  end

  defp publish_snapshot(snapshot, inspector_pid, state) when is_map(snapshot) do
    case state.publisher.(inspector_pid, state.app_pid, snapshot) do
      :ok -> :ok
      _failure -> :retry
    end
  end

  defp publish_snapshot(_snapshot, _inspector_pid, _state), do: :retry

  defp retry_on_failure(fun) do
    fun.()
  rescue
    _error -> :retry
  catch
    _kind, _reason -> :retry
  end
end
