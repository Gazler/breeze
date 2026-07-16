defmodule Breeze.RemoteInspector.Supervisor do
  @moduledoc false

  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, :ok, opts)
  end

  def start_connector(supervisor, app_pid, opts \\ [])
      when is_pid(supervisor) and is_pid(app_pid) and is_list(opts) do
    DynamicSupervisor.start_child(
      supervisor,
      {Breeze.RemoteInspector.AppConnector, {app_pid, opts}}
    )
  end

  def stop(supervisor) when is_pid(supervisor) do
    if Process.alive?(supervisor), do: DynamicSupervisor.stop(supervisor, :normal)
    :ok
  catch
    :exit, _reason -> :ok
  end

  def stop(_supervisor), do: :ok

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
