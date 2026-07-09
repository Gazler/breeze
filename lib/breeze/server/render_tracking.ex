defmodule Breeze.Server.RenderTracking do
  @moduledoc false

  @table __MODULE__

  def begin do
    if disabled?() do
      :disabled
    else
      ensure_table!()
      make_ref()
    end
  end

  def finish(:disabled) do
    empty()
  end

  def finish(ref) do
    ensure_table!()

    entries = :ets.take(@table, ref)

    Enum.reduce(entries, %{missing: [], decorations: [], child_timings: []}, fn
      {^ref, :missing, item}, tracking ->
        %{tracking | missing: [item | tracking.missing]}

      {^ref, :decoration, decoration}, tracking ->
        %{tracking | decorations: [decoration | tracking.decorations]}

      {^ref, :child_timing, child_timing}, tracking ->
        %{tracking | child_timings: [child_timing | tracking.child_timings]}
    end)
    |> then(fn tracking ->
      %{
        missing: Enum.reverse(tracking.missing),
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

  def track_decoration(ref, decoration) do
    track(ref, :decoration, decoration)
  end

  def track_child_timing(ref, child_timing) do
    track(ref, :child_timing, child_timing)
  end

  defp track(ref, kind, item) do
    if ref == :disabled or disabled?() do
      :ok
    else
      ensure_table!()
      true = :ets.insert(@table, {ref, kind, item})
    end

    :ok
  end

  defp disabled? do
    Application.get_env(:breeze, :disable_render_tracking, false)
  end

  defp empty do
    %{missing: [], decorations: [], child_timings: []}
  end

  defp tracked_decoration_identity(decoration) do
    {
      Map.get(decoration, :id),
      Map.get(decoration, :owner_id),
      Map.get(decoration, :mod)
    }
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :bag])
        rescue
          ArgumentError -> :ok
        end

      _tid ->
        :ok
    end
  end
end
