defmodule Breeze.Server.FrameDisplay do
  @moduledoc false

  alias Breeze.Server.Frame

  @sys_timeout 1_000

  def normalize(%{lines: lines} = frame) when is_list(lines) do
    width = Map.get(frame, :width, 0)
    height = Map.get(frame, :height, length(lines))
    overlays = Map.get(frame, :overlays, [])

    if valid_dimension?(width) and valid_dimension?(height) and valid_overlays?(overlays) do
      {:ok,
       %{
         width: width,
         height: height,
         lines: Enum.map(lines, fn line -> if is_binary(line), do: line, else: "" end),
         overlays: overlays
       }}
    else
      {:error, :invalid_frame}
    end
  end

  def normalize(_frame), do: {:error, :invalid_frame}

  def activate(state, frame, owner) do
    state
    |> suspend_runtime()
    |> put_owner(owner)
    |> update_input(
      pending_ref: nil,
      pending_started_at: nil,
      pending_sync_child_render_id: nil,
      queued_input: :queue.new(),
      flush_scheduled?: false,
      render_after_flush?: false
    )
    |> update_frame(display: frame, resume_on_input?: false, last_payload: nil)
    |> cancel_animation()
  end

  def clear(
        %{
          frame: %{
            display: nil,
            display_owner_ref: nil,
            display_suspended_pids: [],
            resume_on_input?: false
          }
        } = state
      ) do
    state
  end

  def clear(state) do
    state
    |> release()
    |> update_input(
      pending_ref: nil,
      pending_started_at: nil,
      pending_sync_child_render_id: nil,
      queued_input: :queue.new(),
      flush_scheduled?: false,
      render_after_flush?: false
    )
    |> update_frame(
      display: nil,
      display_owner: nil,
      display_owner_ref: nil,
      display_suspended_pids: [],
      resume_on_input?: false,
      last_payload: nil,
      last_lines: nil,
      last_overlays: []
    )
  end

  def release(state) do
    demonitor_owner(state.frame.display_owner_ref)

    state.frame.display_suspended_pids
    |> Enum.reverse()
    |> Enum.each(&safe_resume/1)

    update_frame(state,
      display: nil,
      display_owner: nil,
      display_owner_ref: nil,
      display_suspended_pids: [],
      resume_on_input?: false
    )
  end

  def discard(state) do
    demonitor_owner(state.frame.display_owner_ref)

    state
    |> cancel_animation()
    |> update_frame(
      display: nil,
      display_owner: nil,
      display_owner_ref: nil,
      display_suspended_pids: [],
      resume_on_input?: false
    )
  end

  def pause_current(state) do
    display = %{
      width: Map.get(state.terminal.size, :width, 0),
      height: Map.get(state.terminal.size, :height, 0),
      lines: state.frame.last_lines || [],
      overlays: state.frame.last_overlays || []
    }

    state
    |> cancel_animation()
    |> suspend_runtime()
    |> update_frame(
      display: display,
      display_owner: nil,
      display_owner_ref: nil,
      resume_on_input?: true
    )
  end

  def cancel_animation(state) do
    cancel_timer(state.frame.animation_timer)

    update_frame(state,
      animation_timer: nil,
      animation_generation: nil,
      next_tick_at: nil
    )
  end

  def resolve(
        %{
          frame: %{display: %{lines: lines} = display},
          terminal: %{size: %{width: width, height: height}}
        },
        _live_lines,
        _live_overlays
      )
      when is_list(lines) do
    width = historical_dimension(Map.get(display, :width), width)
    frame_height = historical_dimension(Map.get(display, :height), height)

    lines =
      lines
      |> Enum.take(frame_height)
      |> Frame.fit_lines(width)

    lines =
      lines
      |> Kernel.++(List.duplicate("", max(height - length(lines), 0)))
      |> Enum.take(max(height, 0))

    overlays =
      display
      |> Map.get(:overlays, [])
      |> Enum.filter(fn overlay ->
        Map.get(overlay, :x, width) < width and Map.get(overlay, :y, frame_height) < frame_height
      end)

    {lines, overlays}
  end

  def resolve(_state, live_lines, live_overlays), do: {live_lines, live_overlays}

  defp valid_dimension?(dimension), do: is_integer(dimension) and dimension >= 0

  defp valid_overlays?(overlays) when is_list(overlays),
    do: Enum.all?(overlays, &valid_overlay?/1)

  defp valid_overlays?(_overlays), do: false

  defp valid_overlay?(%{x: x, y: y} = overlay)
       when is_integer(x) and x >= 0 and is_integer(y) and y >= 0 do
    valid_overlay_content?(overlay) and valid_overlay_height?(overlay) and
      renderable_overlay?(overlay)
  end

  defp valid_overlay?(_overlay), do: false

  defp valid_overlay_content?(%{content: content}), do: is_binary(content)
  defp valid_overlay_content?(%{char: char}), do: is_binary(char)
  defp valid_overlay_content?(_overlay), do: false

  defp valid_overlay_height?(%{height: height}), do: is_integer(height) and height > 0
  defp valid_overlay_height?(_overlay), do: true

  defp renderable_overlay?(overlay) do
    is_binary(Breeze.TerminalOverlay.render_overlay(overlay))
  rescue
    _error -> false
  catch
    _kind, _reason -> false
  end

  defp put_owner(state, owner) when is_pid(owner) do
    case state.frame do
      %{display_owner: ^owner, display_owner_ref: ref} when is_reference(ref) ->
        state

      frame ->
        demonitor_owner(frame.display_owner_ref)

        update_frame(state,
          display_owner: owner,
          display_owner_ref: Process.monitor(owner)
        )
    end
  end

  defp put_owner(state, _owner) do
    demonitor_owner(state.frame.display_owner_ref)
    update_frame(state, display_owner: nil, display_owner_ref: nil)
  end

  defp demonitor_owner(ref) when is_reference(ref), do: Process.demonitor(ref, [:flush])
  defp demonitor_owner(_ref), do: :ok

  defp suspend_runtime(%{frame: %{display_suspended_pids: [_ | _]}} = state), do: state

  defp suspend_runtime(state) do
    targets = runtime_pids(state)
    Enum.each(targets, &safe_suspend/1)
    update_frame(state, display_suspended_pids: targets)
  end

  defp runtime_pids(state) do
    direct_pids =
      [state.view_pid | Enum.map(Map.values(state.children || %{}), &Map.get(&1, :pid))]

    direct_pids
    |> Enum.flat_map(fn pid -> [pid | child_runtime_pids(pid)] end)
    |> Enum.filter(&(is_pid(&1) and &1 != self() and Process.alive?(&1)))
    |> Enum.uniq()
  end

  defp child_runtime_pids(pid) when is_pid(pid) do
    Breeze.ChildServer.runtime_pids(pid, @sys_timeout)
  catch
    :exit, _reason -> []
  end

  defp child_runtime_pids(_pid), do: []

  defp safe_suspend(pid) when is_pid(pid) do
    if pid != self() and Process.alive?(pid) do
      case :sys.suspend(pid, @sys_timeout) do
        :ok -> :ok
        _result -> :error
      end
    else
      :error
    end
  catch
    :exit, _reason -> :error
  end

  defp safe_resume(pid) when is_pid(pid) do
    if pid != self() and Process.alive?(pid) do
      case :sys.resume(pid, @sys_timeout) do
        :ok -> :ok
        _result -> :error
      end
    else
      :ok
    end
  catch
    :exit, _reason -> :error
  end

  defp safe_resume(_pid), do: :ok

  defp historical_dimension(captured, current) when is_integer(captured) and captured > 0,
    do: min(captured, max(current, 0))

  defp historical_dimension(_captured, current), do: max(current, 0)

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  defp update_input(state, updates), do: %{state | input: struct!(state.input, updates)}
  defp update_frame(state, updates), do: %{state | frame: struct!(state.frame, updates)}
end
