defmodule Breeze.ChildViewSupervisor do
  @moduledoc false

  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, :ok, opts)
  end

  def start_child(supervisor, opts) when is_pid(supervisor) do
    child_spec = %{
      id: make_ref(),
      start: {Breeze.ChildServer, :start_link, [opts]},
      restart: :temporary,
      shutdown: 5_000,
      type: :worker
    }

    DynamicSupervisor.start_child(supervisor, child_spec)
  end

  def terminate_child(supervisor, pid) when is_pid(supervisor) and is_pid(pid) do
    case DynamicSupervisor.terminate_child(supervisor, pid) do
      :ok -> :ok
      {:error, :not_found} -> :ok
    end
  catch
    :exit, _reason -> :ok
  end

  def terminate_child(_supervisor, _pid), do: :ok

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
