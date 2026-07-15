defmodule Breeze.Server.RenderTracking do
  @moduledoc false

  def new_table do
    if not disabled?() do
      :ets.new(__MODULE__, [:public, :bag, write_concurrency: true])
    end
  end

  def begin(table) do
    if disabled?() do
      :disabled
    else
      {table, make_ref()}
    end
  end

  def finish(:disabled) do
    %{empty() | seen: :disabled}
  end

  def finish({table, ref}) do
    entries = :ets.take(table, ref)

    Enum.reduce(entries, %{missing: [], seen: [], decorations: [], child_timings: []}, fn
      {^ref, :missing, item}, tracking ->
        %{tracking | missing: [item | tracking.missing]}

      {^ref, :seen, item}, tracking ->
        %{tracking | seen: [item | tracking.seen]}

      {^ref, :decoration, decoration}, tracking ->
        %{tracking | decorations: [decoration | tracking.decorations]}

      {^ref, :child_timing, child_timing}, tracking ->
        %{tracking | child_timings: [child_timing | tracking.child_timings]}
    end)
    |> then(fn tracking ->
      %{
        missing: Enum.reverse(tracking.missing),
        seen: dedupe_live_children(tracking.seen),
        decorations: dedupe_decorations(tracking.decorations),
        child_timings: Enum.reverse(tracking.child_timings)
      }
    end)
  end

  def dedupe_decorations(decorations) do
    decorations
    |> Enum.reverse()
    |> Enum.uniq_by(&tracked_decoration_identity/1)
    |> Enum.reverse()
  end

  def track_missing_live_child(ref, item) do
    track(ref, :missing, item)
  end

  def track_seen_live_child(ref, item) do
    track(ref, :seen, item)
  end

  def track_decoration(ref, decoration) do
    track(ref, :decoration, decoration)
  end

  def track_child_timing(ref, child_timing) do
    track(ref, :child_timing, child_timing)
  end

  defp track(:disabled, _kind, _item), do: :ok

  defp track({table, ref}, kind, item) do
    unless disabled?() do
      :ets.insert(table, {ref, kind, item})
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  defp disabled? do
    Application.get_env(:breeze, :disable_render_tracking, false)
  end

  defp empty do
    %{missing: [], seen: [], decorations: [], child_timings: []}
  end

  defp dedupe_live_children(children) do
    children
    |> Enum.reverse()
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.reverse()
  end

  defp tracked_decoration_identity(decoration) do
    {
      Map.get(decoration, :id),
      Map.get(decoration, :owner_id),
      Map.get(decoration, :mod)
    }
  end
end
