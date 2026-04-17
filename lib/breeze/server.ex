defmodule Breeze.Term do
  @moduledoc false

  defstruct [
    :view,
    :server,
    :terminal,
    :theme,
    :theme_source,
    :reader,
    last_render_at: nil,
    last_interaction_at: nil,
    assigns: %{},
    external_assigns: %{},
    global_keybindings: [],
    local_keybindings: [],
    focus_keybindings: %{},
    focused: nil,
    allow_unfocused?: false,
    focusables: [],
    focus_meta: %{},
    focus_memory: %{},
    elements: %{},
    events: %{},
    implicit_state: %{},
    implicit_meta: %{},
    rendered_contents: %{},
    rendered_boxes: %{},
    mouse_targets: %{},
    children: %{},
    frame_delay_ms: 16,
    render_timer: nil,
    apply_theme_defaults?: false
  ]
end

defmodule Breeze.Server do
  @moduledoc """
  Public server entrypoint for Breeze applications.
  """

  use GenServer

  @render_tracking_table __MODULE__.RenderTracking
  @flush_input_batch :flush_input_batch
  @debug_window_size 20
  @debug_rate_window_ms 1_000

  defstruct [
    :terminal,
    :reader,
    :input_router,
    :view_pid,
    :view,
    :start_opts,
    :mouse_mode,
    :reload_opts,
    :reloader_pid,
    :focused,
    :theme,
    :apply_theme_defaults?,
    :crash,
    :base_output,
    :last_frame_payload,
    :last_frame_lines,
    :last_overlays,
    :pending_ref,
    :pending_started_at,
    :last_render_at,
    :last_interaction_at,
    queued_input: :queue.new(),
    input_flush_scheduled?: false,
    decorations: [],
    children: %{},
    rendered_boxes: %{},
    animation_timer: nil,
    next_tick_at: nil,
    global_keybindings: [],
    inspector: false,
    inspector_visible?: false,
    inspector_selected_id: nil,
    inspector_hovered_id: nil,
    inspector_panel_position: :bottom,
    debug_subscribers: MapSet.new(),
    inspector_subscribers: MapSet.new(),
    debug_stats: %{},
    debug_push_timer: nil,
    debug_push_interval_ms: 250,
    busy_delay_ms: 120,
    frame_delay_ms: 80,
    rendered_elements: %{},
    rendered_viewports: %{},
    rendered_mouse_targets: %{},
    rendered_flags: %{},
    rendered_focus_meta: %{},
    rendered_implicit_state: %{},
    rendered_implicit_meta: %{}
  ]

  @type option ::
          {:view, module()}
          | {:start_opts, keyword()}
          | {:hide_cursor, boolean()}
          | {:mouse, boolean() | keyword()}
          | {:reload, boolean() | keyword()}
          | {:theme, Breeze.Theme.t() | map() | keyword() | atom()}
          | {:global_keybindings, list()}
          | {:inspector, boolean() | keyword()}
          | {:debug_push_interval_ms, pos_integer()}
          | {:busy_delay_ms, non_neg_integer()}
          | {:frame_delay_ms, pos_integer()}

  @doc """
  Start the Breeze application.

  Valid options are:

    * `:view` - the view to run. This is required
    * `:hide_cursor` - hide the cursor on start. Defaults to `false`
    * `:mouse` - enable mouse tracking. Defaults to `false`. Pass `true` for click mode or keyword options for `Termite.Screen.enable_mouse/2`
    * `:global_keybindings` - app-wide keybindings checked before focused event handling
    * `:inspector` - opt-in inspector support. Defaults to `false`

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    Breeze.InputRouter.start_link(opts)
  end

  @doc false
  @spec start_app_link(keyword()) :: GenServer.on_start()
  def start_app_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec stats(pid()) :: map()
  def stats(pid) do
    GenServer.call(pid, :stats)
  end

  @doc false
  def focused_implicit_metadata(pid) do
    GenServer.call(pid, :focused_implicit_meta)
  end

  @spec inspector_snapshot(pid()) :: map()
  def inspector_snapshot(pid) do
    GenServer.call(pid, :inspector_snapshot)
  end

  @spec subscribe_debug(pid(), pid()) :: :ok
  def subscribe_debug(pid, subscriber) do
    GenServer.cast(pid, {:subscribe_debug, subscriber})
  end

  @spec subscribe_inspector(pid(), pid()) :: :ok
  def subscribe_inspector(pid, subscriber) do
    GenServer.cast(pid, {:subscribe_inspector, subscriber})
  end

  @impl true
  def init(opts) do
    view = Keyword.fetch!(opts, :view)
    start_opts = Keyword.get(opts, :start_opts, [])
    frame_delay_ms = Keyword.get(opts, :frame_delay_ms, 80)
    debug_push_interval_ms = Keyword.get(opts, :debug_push_interval_ms, 250)
    terminal = Keyword.fetch!(opts, :terminal)
    theme = Breeze.Theme.new(Keyword.get(opts, :theme), terminal: terminal)
    theme_source = Keyword.get(opts, :theme)
    apply_theme_defaults? = Breeze.Theme.defaults_enabled?(Keyword.get(opts, :theme))

    session = self()

    {:ok, view_pid} =
      Breeze.ChildServer.start(
        view: view,
        start_opts: start_opts,
        terminal: terminal,
        theme: theme,
        theme_source: theme_source,
        apply_theme_defaults?: apply_theme_defaults?,
        server: self(),
        global_keybindings: Keyword.get(opts, :global_keybindings, []),
        invalidate: fn -> send(session, :child_invalidated) end
      )

    Process.monitor(view_pid)

    {focused, theme} =
      case Breeze.ChildServer.metadata(view_pid) do
        %{focused: focused, theme: child_theme} -> {focused, child_theme}
        %{focused: focused} -> {focused, theme}
        _ -> {nil, theme}
      end

    state = %__MODULE__{
      terminal: terminal,
      reader: terminal.reader,
      input_router: Keyword.get(opts, :input_router),
      view_pid: view_pid,
      view: view,
      start_opts: start_opts,
      mouse_mode: Keyword.get(opts, :mouse, false),
      reload_opts:
        normalize_reload_opts(
          Keyword.get(opts, :reload, Application.get_env(:breeze, :reload, false))
        ),
      focused: focused,
      theme: theme,
      apply_theme_defaults?: apply_theme_defaults?,
      global_keybindings: Keyword.get(opts, :global_keybindings, []),
      inspector: Keyword.get(opts, :inspector, false),
      debug_push_interval_ms: debug_push_interval_ms,
      busy_delay_ms: Keyword.get(opts, :busy_delay_ms, 120),
      frame_delay_ms: frame_delay_ms,
      base_output: "",
      pending_started_at: nil,
      last_render_at: System.monotonic_time(:millisecond),
      last_interaction_at: nil,
      last_frame_lines: nil,
      last_overlays: []
    }

    state = maybe_start_reloader(state)
    if Breeze.Inspector.enabled?(state), do: Breeze.RemoteInspector.register_app(self())

    {:ok, render_base(state)}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, debug_stats_snapshot(state), state}
  end

  def handle_call(:inspector_snapshot, _from, state) do
    {:reply, Breeze.Inspector.snapshot(state), state}
  end

  def handle_call(:focused_implicit_meta, _from, state) do
    {:reply, focused_implicit_meta(state), state}
  end

  @impl true
  def handle_cast({:subscribe_debug, subscriber}, state) do
    if is_pid(subscriber), do: Process.monitor(subscriber)

    state = Map.update!(state, :debug_subscribers, &MapSet.put(&1, subscriber))

    state =
      if state.debug_stats == %{} do
        state
      else
        push_debug_stats_now(state)
      end

    {:noreply, state}
  end

  def handle_cast({:subscribe_inspector, subscriber}, state) do
    if is_pid(subscriber), do: Process.monitor(subscriber)

    state = Map.update!(state, :inspector_subscribers, &MapSet.put(&1, subscriber))
    {:noreply, push_inspector_snapshot_now(state)}
  end

  @impl true
  def handle_info({reader, {:data, data}}, %{reader: reader} = state) do
    started_at = System.monotonic_time(:microsecond)

    state =
      state
      |> enqueue_input(Breeze.Input.decode(data))
      |> put_debug_stat(:last_input_us, System.monotonic_time(:microsecond) - started_at)
      |> schedule_input_flush()

    {:noreply, state}
  end

  def handle_info({reader, {:signal, :winch}}, %{reader: reader} = state) do
    if crashed?(state) do
      terminal = Termite.Terminal.resize(state.terminal)
      {:noreply, render_crash(%{state | terminal: terminal})}
    else
      terminal = Termite.Terminal.resize(state.terminal)
      state = %{state | terminal: terminal}

      case safe_call(fn ->
             Breeze.ChildServer.dispatch_info(state.view_pid, :resize, terminal)
           end) do
        {:ok, {:stop, _focused}} ->
          stop(state)

        {:ok, {:noreply, focused}} ->
          {:noreply, force_full_redraw(%{state | focused: focused}, :resize)}

        {:crash, crash} ->
          {:noreply, enter_crash_state(state, crash)}
      end
    end
  end

  def handle_info({:ensure_runtime_palette, :system}, %{input_router: pid} = state)
      when is_pid(pid) do
    send(pid, {:ensure_runtime_palette, :system})
    {:noreply, state}
  end

  def handle_info(:child_invalidated, state) do
    if crashed?(state) do
      {:noreply, state}
    else
      state = increment_debug_stat(state, :child_invalidated_count)
      {:noreply, maybe_render_base(state, :child_invalidated)}
    end
  end

  def handle_info({:child_invalidated, child_id}, state) do
    if crashed?(state) do
      {:noreply, state}
    else
      state =
        if debug_child_id?(child_id) do
          state
        else
          increment_debug_stat(state, :child_invalidated_count)
        end

      {:noreply, maybe_render_invalidated_child(state, child_id)}
    end
  end

  def handle_info(@flush_input_batch, state) do
    state = increment_debug_stat(state, :flush_input_batch_count)
    state = %{state | input_flush_scheduled?: false}

    case flush_input_batch(state) do
      {:stop, state} ->
        stop(state)

      {:noreply, state} ->
        state =
          state
          |> maybe_render_after_input()
          |> schedule_input_flush()

        {:noreply, state}
    end
  end

  def handle_info(:animation_tick, %{decorations: []} = state) do
    state = increment_debug_stat(state, :animation_tick_count)
    {:noreply, %{state | animation_timer: nil, next_tick_at: nil}}
  end

  def handle_info(:animation_tick, state) do
    started_at = System.monotonic_time(:microsecond)
    state = increment_debug_stat(state, :animation_tick_count)

    state =
      state
      |> Map.put(:animation_timer, nil)
      |> Map.put(:next_tick_at, nil)
      |> advance_decorations()
      |> render_frame()
      |> put_debug_stat(:last_animation_us, System.monotonic_time(:microsecond) - started_at)
      |> schedule_animation()

    {:noreply, state}
  end

  def handle_info(:debug_push, state) do
    state =
      state
      |> Map.put(:debug_push_timer, nil)
      |> push_debug_stats_now()

    {:noreply, state}
  end

  def handle_info({:reload, :code_changed, _files}, state) do
    {:noreply, reload_after_code_change(state)}
  end

  def handle_info({:reload, :compile_error, reason, _files}, state) do
    shutdown_root_view(state.view_pid)
    {:noreply, enter_crash_state(state, crash_info(:error, reason, []))}
  end

  def handle_info({:event_reply, ref, reply}, %{pending_ref: ref} = state) do
    case reply do
      {:crash, crash} ->
        {:noreply, enter_crash_state(state, crash)}

      {:stop, _focused} ->
        stop(state)

      {:stop, _focused, _consumed} ->
        stop(state)

      {:noreply, focused} ->
        state =
          state
          |> Map.put(:pending_ref, nil)
          |> Map.put(:pending_started_at, nil)
          |> Map.put(:focused, focused)
          |> maybe_render_base(:event_reply)

        {:noreply, state}

      {:noreply, focused, _consumed} ->
        state =
          state
          |> Map.put(:pending_ref, nil)
          |> Map.put(:pending_started_at, nil)
          |> Map.put(:focused, focused)
          |> maybe_render_base(:event_reply)

        {:noreply, state}
    end
  end

  def handle_info({:event_reply, _ref, _reply}, state), do: {:noreply, state}

  def handle_info(message, state) do
    case message do
      {:DOWN, _, :process, pid, _reason} when pid == state.view_pid ->
        reason = elem(message, 4)

        cond do
          crashed?(state) ->
            {:noreply, state}

          reason == :normal ->
            stop(state)

          true ->
            {:noreply, enter_crash_state(state, crash_info(:exit, reason, []))}
        end

      {:DOWN, ref, :process, _pid, _reason} ->
        cond do
          MapSet.member?(state.debug_subscribers, elem(message, 3)) ->
            {:noreply,
             %{
               state
               | debug_subscribers: MapSet.delete(state.debug_subscribers, elem(message, 3))
             }}

          MapSet.member?(state.inspector_subscribers, elem(message, 3)) ->
            {:noreply,
             %{
               state
               | inspector_subscribers:
                   MapSet.delete(state.inspector_subscribers, elem(message, 3))
             }}

          true ->
            children =
              state.children
              |> Enum.reject(fn {_id, child} -> child.ref == ref end)
              |> Map.new()

            {:noreply, %{state | children: children}}
        end

      _ ->
        {:noreply, state}
    end
  end

  defp flush_input_batch(state) do
    case queue_out(state.queued_input) do
      {:empty, _queue} ->
        {:noreply, state}

      {{:value, decoded}, queue} ->
        state = %{state | queued_input: queue}

        case process_batched_input(decoded, state) do
          {:stop, state} ->
            {:stop, state}

          {:noreply, state} ->
            continue_flushing_or_pause(state)
        end
    end
  end

  defp process_batched_input({:mouse, %{button: button} = event}, state)
       when button in [:wheel_down, :wheel_up] do
    {event, state} = coalesce_wheel_events_from_queue(event, state, 1)
    handle_mouse(event, state)
  end

  defp process_batched_input({:key, key}, state) do
    if batchable_printable_input?(key, state) do
      {key, state} = coalesce_printable_keys_from_queue(key, state)
      handle_deferred_or_sync_input({:key, batched_printable_event(key)}, state)
    else
      {key, state} = coalesce_repeated_keys_from_queue(key, state)
      handle_deferred_or_sync_input({:key, key}, state)
    end
  end

  defp process_batched_input(decoded, state), do: handle_deferred_or_sync_input(decoded, state)

  defp continue_flushing_or_pause(state) do
    case queue_peek(state.queued_input) do
      {:value, next} ->
        if sync_input_message?(next, state) do
          flush_input_batch(state)
        else
          {:noreply, state}
        end

      :empty ->
        {:noreply, state}
    end
  end

  defp handle_deferred_or_sync_input(decoded, state) do
    if sync_input_message?(decoded, state) do
      handle_decoded_sync_input(decoded, state)
    else
      handle_deferred_input(decoded, state)
    end
  end

  defp handle_decoded_sync_input({:mouse, event}, state) do
    cond do
      crashed?(state) ->
        {:noreply, state}

      inspector_mouse_active?(state) ->
        {:noreply,
         state
         |> touch_interaction()
         |> maybe_select_inspector_target(event)
         |> maybe_render_base(:inspector_select)}

      true ->
        handle_mouse(event, state)
    end
  end

  defp handle_decoded_sync_input({:key, key}, state) do
    if crashed?(state) do
      {:noreply, dispatch_crash_input({:key, key}, touch_interaction(state))}
    else
      cond do
        inspector_toggle_key?(key, state) ->
          {:noreply,
           state
           |> touch_interaction()
           |> Breeze.Inspector.toggle()
           |> maybe_render_base(:inspector_toggle)}

        inspector_move_key?(key, state) ->
          {:noreply,
           state
           |> touch_interaction()
           |> Breeze.Inspector.toggle_position()
           |> maybe_render_base(:inspector_move)}

        true ->
          case key do
            key when key in ["\t", "ShiftTab"] ->
              state
              |> touch_interaction()
              |> safe_apply_input_reply(fn state ->
                Breeze.ChildServer.dispatch_input(state.view_pid, key)
              end)

            key ->
              state
              |> touch_interaction()
              |> safe_apply_input_reply(fn state ->
                dispatch_input_hierarchy(state, key)
              end)
          end
      end
    end
  end

  defp handle_deferred_input({:key, _key}, %{pending_ref: ref} = state) when not is_nil(ref) do
    {:noreply, state}
  end

  defp handle_deferred_input({:key, key}, state) do
    if crashed?(state) do
      {:noreply, dispatch_crash_input({:key, key}, touch_interaction(state))}
    else
      {:noreply, start_async_dispatch(touch_interaction(state), key)}
    end
  end

  defp handle_deferred_input(_decoded, state), do: {:noreply, state}

  defp sync_input_message?({:mouse, _event}, %{pending_ref: nil}), do: true
  defp sync_input_message?({:mouse, _event}, _state), do: false

  defp sync_input_message?({:key, _key}, %{crash: crash}) when not is_nil(crash), do: true

  defp sync_input_message?({:key, key}, state) do
    input_key = key_name(key)

    inspector_toggle_key?(input_key, state) or
      inspector_move_key?(input_key, state) or
      stop_global_key?(key, state) or
      (is_nil(state.pending_ref) and
         (input_key in ["\t", "ShiftTab"] or sync_input?(state, input_key)))
  end

  defp sync_input_message?(_, _state), do: false

  defp coalesce_wheel_events_from_queue(event, state, repeat) do
    case queue_out(state.queued_input) do
      {{:value, {:mouse, %{button: button} = next_event}}, queue} ->
        if button == event.button and wheel_match?(event, next_event) do
          coalesce_wheel_events_from_queue(event, %{state | queued_input: queue}, repeat + 1)
        else
          {Map.put(event, :repeat, repeat), state}
        end

      {{:value, _next}, _queue} ->
        {Map.put(event, :repeat, repeat), state}

      {:empty, _queue} ->
        {Map.put(event, :repeat, repeat), state}
    end
  end

  defp coalesce_printable_keys_from_queue(key, state) do
    case queue_out(state.queued_input) do
      {{:value, {:key, next_key}}, queue} ->
        if batchable_printable_input?(next_key, state) do
          coalesce_printable_keys_from_queue(key <> next_key, %{state | queued_input: queue})
        else
          {key, state}
        end

      {{:value, _next}, _queue} ->
        {key, state}

      {:empty, _queue} ->
        {key, state}
    end
  end

  defp coalesce_repeated_keys_from_queue(key, state) do
    case queue_out(state.queued_input) do
      {{:value, {:key, next_key}}, queue} ->
        if next_key == key and not batchable_printable_input?(next_key, state) do
          coalesce_repeated_keys_from_queue(key, %{state | queued_input: queue})
        else
          {key, state}
        end

      {{:value, _next}, _queue} ->
        {key, state}

      {:empty, _queue} ->
        {key, state}
    end
  end

  defp wheel_match?(left, right) do
    left.action == right.action and left.x == right.x and left.y == right.y and
      left.modifiers == right.modifiers
  end

  defp apply_input_reply(state, reply) do
    case reply do
      {:stop, _focused} ->
        {:stop, state}

      {:stop, _focused, _consumed} ->
        {:stop, state}

      {:noreply, focused} ->
        {:noreply, Map.put(state, :focused, focused)}

      {:noreply, focused, _consumed} ->
        {:noreply, Map.put(state, :focused, focused)}
    end
  end

  defp touch_interaction(state) do
    %{state | last_interaction_at: System.monotonic_time(:millisecond)}
  end

  defp inspector_mouse_active?(state) do
    Breeze.Inspector.picks_mouse?(state)
  end

  defp maybe_select_inspector_target(state, %{button: :left, action: :press} = event) do
    Breeze.Inspector.select_at(state, event)
  end

  defp maybe_select_inspector_target(state, %{action: :move} = event) do
    Breeze.Inspector.hover_at(state, event)
  end

  defp maybe_select_inspector_target(state, _event), do: state

  defp inspector_toggle_key?(key, state) do
    Breeze.Inspector.enabled?(state) and key == Breeze.Inspector.toggle_key(state)
  end

  defp inspector_move_key?(key, state) do
    Breeze.Inspector.enabled?(state) and state.inspector_visible? and
      key == Breeze.Inspector.move_key(state)
  end

  defp sync_input?(state, key) do
    key in ["\t", "ShiftTab"] or focused_implicit?(state)
  end

  defp batchable_printable_input?(key, state) do
    raw_printable_key?(key) and focused_implicit_captures_printable_key?(state, key)
  end

  defp stop_global_key?(key, state) do
    Breeze.GlobalKeybindings.stop_action?(%{"key" => key}, state)
  end

  defp focused_implicit?(%{focused: nil}), do: false

  defp focused_implicit?(state) do
    match?(%{focused_implicit_id: id} when not is_nil(id), focused_child_or_root_metadata(state))
  end

  defp focused_implicit_meta(%{focused: nil}), do: %{}

  defp focused_implicit_meta(state) do
    Map.get(focused_child_or_root_metadata(state), :focused_implicit_meta, %{})
  end

  defp focused_implicit_captures_printable_key?(state, key) when is_binary(key) do
    raw_printable_key?(key) and
      match?(%{captures_printable_keys: true}, focused_implicit_meta(state))
  end

  defp focused_implicit_captures_printable_key?(_state, _key), do: false

  defp focused_child_or_root_metadata(state) do
    case focused_child_chain(state) do
      [{_child_id, %{pid: pid}} | _] ->
        case safe_call(fn -> Breeze.ChildServer.metadata(pid) end) do
          {:ok, metadata} -> metadata
          {:crash, _crash} -> %{}
        end

      [] ->
        case safe_call(fn -> Breeze.ChildServer.metadata(state.view_pid) end) do
          {:ok, metadata} -> metadata
          {:crash, _crash} -> %{}
        end
    end
  end

  defp handle_mouse(event, state) do
    state
    |> touch_interaction()
    |> safe_apply_input_reply(fn state ->
      Breeze.ChildServer.dispatch_input(state.view_pid, %{"mouse" => event})
    end)
  end

  defp render_base(state, cause \\ :unknown, attempts \\ 1)

  defp render_base(state, cause, attempts) do
    if crashed?(state) do
      state
    else
      try do
        tracking_ref = begin_render_tracking()
        started_at = System.monotonic_time(:microsecond)
        profile_scope = make_ref()
        Breeze.DebugProfiler.reset(profile_scope)
        root_started_at = System.monotonic_time(:microsecond)

        {acc, box, decorations} =
          case safe_render_snapshot(state, tracking_ref, profile_scope) do
            {:ok, acc, box, decorations} ->
              {acc, box, decorations}

            :stopped ->
              throw({:stopped, state})
          end

        root_snapshot_us = System.monotonic_time(:microsecond) - root_started_at

        {metadata_focused, metadata_theme} = safe_focused_metadata(state)
        focused = metadata_focused || state.focused

        %{
          missing: missing,
          decorations: child_decorations,
          child_timings: child_timings
        } = finish_render_tracking(tracking_ref)

        profile_entries = Breeze.DebugProfiler.snapshot(profile_scope)
        {state, started?} = ensure_children(state, missing)

        if started? do
          render_base(state, cause, attempts)
        else
          cond do
            attempts > 0 and focused != state.focused ->
              render_base(%{state | focused: focused}, cause, attempts - 1)

            true ->
              decorations = dedupe_decorations(decorations ++ child_decorations)
              state = %{state | focused: focused, theme: metadata_theme}
              prep_started_at = System.monotonic_time(:microsecond)
              {base_output, decorations} = prepare_decorations(box.content, decorations, state)
              prepare_decorations_us = System.monotonic_time(:microsecond) - prep_started_at
              render_base_us = System.monotonic_time(:microsecond) - started_at

              debug_live_child_us = debug_live_child_us(child_timings)
              app_live_children = non_debug_child_timings(child_timings)

              state
              |> increment_debug_stat(:render_base_count)
              |> Map.put(:base_output, base_output)
              |> Map.put(:rendered_elements, viewports_from_acc(acc))
              |> Map.put(:rendered_boxes, acc.boxes)
              |> merge_inspector_render_data(acc)
              |> Map.put(:decorations, decorations)
              |> Map.put(:focused, focused)
              |> Map.put(:last_render_at, System.monotonic_time(:millisecond))
              |> put_debug_stat(:last_render_cause, cause)
              |> put_debug_stat(:last_root_snapshot_us, root_snapshot_us)
              |> put_debug_stat(
                :last_root_snapshot_app_us,
                max(root_snapshot_us - debug_live_child_us, 0)
              )
              |> put_debug_stat(:last_live_children_us, sum_timing_us(child_timings))
              |> put_debug_stat(:last_live_children_app_us, sum_timing_us(app_live_children))
              |> put_debug_stat(:last_live_children, normalize_child_timings(app_live_children))
              |> put_debug_stat(:last_render_profile, summarize_profile(profile_entries))
              |> put_debug_stat(:last_reconcile_passes, 0)
              |> put_debug_stat(:last_reconcile_changed_ids, nil)
              |> put_debug_stat(:last_prepare_decorations_us, prepare_decorations_us)
              |> put_debug_stat(:last_render_base_us, render_base_us)
              |> put_debug_stat(
                :last_render_base_app_us,
                max(render_base_us - debug_live_child_us, 0)
              )
              |> render_frame()
              |> schedule_animation()
          end
        end
      catch
        {:stopped, state} -> state
        {:crash_state, crash_state} -> crash_state
      end
    end
  end

  defp maybe_render_base(%{view_pid: pid} = state, cause) do
    state = prune_dead_children(state)

    if crashed?(state) do
      state
    else
      if Process.alive?(pid), do: render_base(state, cause), else: state
    end
  end

  defp maybe_render_invalidated_child(state, child_id) do
    case render_invalidated_child(state, child_id) do
      {:ok, state} -> state
      {:crash, state} -> state
      :error -> maybe_render_base(state, :child_invalidated)
    end
  end

  defp safe_render_snapshot(state, tracking_ref, profile_scope) do
    Breeze.ChildServer.render_snapshot(state.view_pid,
      implicit_state: %{},
      terminal: state.terminal,
      theme: state.theme,
      render_tracking_ref: tracking_ref,
      profile_scope: profile_scope,
      profile_label: inspect(root_view_module(state)),
      live_view: fn attrs, opts ->
        render_live_child(attrs, opts, state, profile_scope, tracking_ref)
      end
    )
    |> then(fn
      {:ok, acc, box, decorations} -> {:ok, acc, box, decorations}
      _ -> :stopped
    end)
  catch
    :exit, _reason -> :stopped
  end

  defp safe_focused_metadata(state) do
    case Breeze.ChildServer.metadata(state.view_pid) do
      %{focused: focused, theme: theme} -> {focused, theme}
      %{focused: focused} -> {focused, state.theme}
      _ -> {nil, state.theme}
    end
  catch
    :exit, _reason -> {nil, state.theme}
  end

  defp maybe_render_after_input(%{pending_ref: ref} = state) when not is_nil(ref), do: state
  defp maybe_render_after_input(state), do: maybe_render_base(state, :input_flush)

  defp force_full_redraw(state, cause) do
    state
    |> Map.put(:last_frame_payload, nil)
    |> Map.put(:last_frame_lines, nil)
    |> Map.put(:last_overlays, [])
    |> maybe_render_base(cause)
  end

  defp render_live_child(attrs, opts, state, profile_scope, tracking_ref) do
    id = fetch_live_attr!(attrs, :id)
    full_id = live_id(Keyword.get(opts, :live_prefix), id)
    preload_only = fetch_live_attr(attrs, :preload_only, false)
    expected_view = fetch_live_attr!(attrs, :view)
    expected_assigns = fetch_live_attr(attrs, :assigns, %{}) |> Map.new()

    expected_start_opts =
      child_start_opts(fetch_live_attr(attrs, :start_opts, []), expected_view, state)

    child_terminal = Keyword.get(opts, :live_terminal, state.terminal)
    viewport = Keyword.get(opts, :live_viewport)

    case Map.get(state.children, full_id) do
      nil ->
        track_missing_live_child(tracking_ref, {full_id, attrs})
        if preload_only, do: :preloaded, else: :missing

      %{pid: pid, view: view, start_opts: start_opts, assigns: assigns} ->
        cond do
          not Process.alive?(pid) ->
            track_missing_live_child(tracking_ref, {full_id, attrs})
            if preload_only, do: :preloaded, else: :missing

          view != expected_view or start_opts != expected_start_opts ->
            track_missing_live_child(tracking_ref, {full_id, attrs})
            if preload_only, do: :preloaded, else: :missing

          assigns != expected_assigns ->
            track_missing_live_child(tracking_ref, {full_id, attrs})
            if preload_only, do: :preloaded, else: :missing

          preload_only ->
            :preloaded

          true ->
            local_focused = strip_live_prefix(state.focused, full_id)
            child_started_at = System.monotonic_time(:microsecond)

            case safe_call(fn ->
                   Breeze.ChildServer.render_snapshot(pid,
                     focused: local_focused,
                     implicit_state: %{},
                     terminal: child_terminal,
                     theme: state.theme,
                     live_prefix: full_id,
                     render_tracking_ref: tracking_ref,
                     profile_scope: profile_scope,
                     profile_label: "#{full_id} #{inspect(state.children[full_id].view)}",
                     live_view: fn child_attrs, child_opts ->
                       render_live_child(
                         child_attrs,
                         child_opts,
                         state,
                         profile_scope,
                         tracking_ref
                       )
                     end
                   )
                 end) do
              {:ok, {:ok, child_acc, child_box, child_decorations}} ->
                track_child_timing(tracking_ref, %{
                  id: full_id,
                  view: state.children[full_id].view,
                  us: System.monotonic_time(:microsecond) - child_started_at
                })

                Enum.each(child_decorations, fn decoration ->
                  track_render_decoration(
                    tracking_ref,
                    namespace_decoration(decoration, full_id, viewport)
                  )
                end)

                child_dimensions =
                  case safe_call(fn -> Breeze.ChildServer.layout_snapshot(pid) end) do
                    {:ok, snapshot} ->
                      translate_live_dimensions(snapshot.elements, viewport, full_id, child_box)

                    _ ->
                      %{}
                  end

                {:rendered, id, child_acc, child_box, child_dimensions}

              {:crash, %{reason: {:noproc, _}}} ->
                track_missing_live_child(tracking_ref, {full_id, attrs})
                if preload_only, do: :preloaded, else: :missing

              {:crash, crash} ->
                throw({:crash_state, enter_crash_state(state, crash)})
            end
        end
    end
  end

  defp render_invalidated_child(state, child_id) do
    try do
      with true <- patchable_live_child?(child_id),
           %{pid: pid, view: view} <- Map.get(state.children, child_id),
           %Breeze.Viewport{} = viewport <- Map.get(state.rendered_elements, child_id) do
        tracking_ref = begin_render_tracking()
        profile_scope = make_ref()
        Breeze.DebugProfiler.reset(profile_scope)
        started_at = System.monotonic_time(:microsecond)

        {:ok, _child_acc, child_box, child_decorations} =
          case safe_call(fn ->
                 Breeze.ChildServer.render_snapshot(pid,
                   focused: strip_live_prefix(state.focused, child_id),
                   implicit_state: %{},
                   terminal: state.terminal,
                   theme: state.theme,
                   live_prefix: child_id,
                   render_tracking_ref: tracking_ref,
                   profile_scope: profile_scope,
                   profile_label: "#{child_id} #{inspect(view)}",
                   live_view: fn child_attrs, child_opts ->
                     render_live_child(
                       child_attrs,
                       child_opts,
                       state,
                       profile_scope,
                       tracking_ref
                     )
                   end
                 )
               end) do
            {:ok, result} -> result
            {:crash, crash} -> throw({:crash_state, enter_crash_state(state, crash)})
          end

        child_render_us = System.monotonic_time(:microsecond) - started_at

        %{missing: missing, decorations: tracked_decorations, child_timings: child_timings} =
          finish_render_tracking(tracking_ref)

        cond do
          missing != [] ->
            :error

          child_decorations != [] or tracked_decorations != [] or child_timings != [] ->
            :error

          true ->
            fragment =
              child_box
              |> wrap_child_fragment(viewport)
              |> BackBreeze.Box.render(terminal: state.terminal)
              |> Map.fetch!(:content)

            composed_at = System.monotonic_time(:microsecond)
            payload = child_patch_payload(fragment, viewport)
            terminal = Termite.Terminal.write(state.terminal, payload)
            written_at = System.monotonic_time(:microsecond)
            total_us = written_at - started_at
            write_us = written_at - composed_at
            profile_entries = Breeze.DebugProfiler.snapshot(profile_scope)

            next_state =
              state
              |> Map.put(:terminal, terminal)
              |> Map.put(:last_frame_payload, nil)
              |> Map.put(:last_frame_lines, nil)
              |> Map.put(:last_overlays, [])

            next_state =
              if debug_child_id?(child_id) do
                next_state
              else
                next_state
                |> put_debug_stat(:last_render_cause, :child_patch)
                |> put_debug_stat(:last_root_snapshot_us, 0)
                |> put_debug_stat(:last_root_snapshot_app_us, 0)
                |> put_debug_stat(:last_live_children_us, child_render_us)
                |> put_debug_stat(:last_live_children_app_us, child_render_us)
                |> put_debug_stat(
                  :last_live_children,
                  normalize_child_timings([%{id: child_id, view: view, us: child_render_us}])
                )
                |> put_debug_stat(:last_render_profile, summarize_profile(profile_entries))
                |> put_debug_stat(:last_reconcile_passes, 1)
                |> put_debug_stat(:last_reconcile_changed_ids, [child_id])
                |> put_debug_stat(:last_prepare_decorations_us, 0)
                |> put_debug_stat(:last_render_base_us, total_us)
                |> put_debug_stat(:last_render_base_app_us, total_us)
                |> put_debug_stat(:last_frame_compose_us, composed_at - started_at)
                |> put_debug_stat(:last_terminal_write_us, write_us)
                |> put_debug_stat(:last_frame_us, total_us)
                |> put_debug_stat(:last_frame_bytes, byte_size(fragment))
                |> put_debug_stat(:overlay_count, 0)
              end

            {:ok, next_state}
        end
      else
        _ -> :error
      end
    catch
      {:crash_state, crash_state} -> {:crash, crash_state}
    end
  end

  defp render_frame(state) do
    started_at = System.monotonic_time(:microsecond)
    {output, decorations} = apply_decorations(state.base_output, state.decorations, state)
    output = strip_private_use_chars(output)
    overlays = terminal_overlays(decorations, state)

    lines =
      output
      |> normalize_frame_lines(state.terminal.size.height)

    frame_payload =
      build_frame_payload(
        state.last_frame_lines,
        lines,
        state.last_overlays || [],
        overlays,
        state.terminal.size.width
      )

    composed_at = System.monotonic_time(:microsecond)

    {terminal, write_duration} =
      if frame_payload == state.last_frame_payload do
        {state.terminal, 0}
      else
        terminal = Termite.Terminal.write(state.terminal, frame_payload)
        written_at = System.monotonic_time(:microsecond)
        {terminal, written_at - composed_at}
      end

    state
    |> Map.put(:terminal, terminal)
    |> Map.put(:decorations, decorations)
    |> Map.put(:last_frame_payload, frame_payload)
    |> Map.put(:last_frame_lines, lines)
    |> Map.put(:last_overlays, overlays)
    |> put_debug_stat(:last_frame_compose_us, composed_at - started_at)
    |> put_debug_stat(:last_terminal_write_us, write_duration)
    |> put_debug_stat(:last_frame_us, System.monotonic_time(:microsecond) - started_at)
    |> put_debug_stat(:last_frame_bytes, byte_size(frame_payload))
    |> put_debug_stat(:overlay_count, length(overlays))
    |> push_inspector_snapshot_now()
  end

  defp normalize_frame_lines(output, screen_height) do
    output
    |> :binary.split("\n", [:global])
    |> then(fn lines ->
      lines = if lines == [], do: [""], else: lines
      lines ++ List.duplicate("", max(screen_height - length(lines), 0))
    end)
    |> Enum.take(screen_height)
  end

  defp build_frame_payload(nil, lines, _prev_overlays, overlays, screen_width) do
    full_redraw_payload(lines, overlays, screen_width)
  end

  defp build_frame_payload(prev_lines, lines, prev_overlays, overlays, screen_width) do
    changed_rows =
      changed_base_rows(prev_lines, lines)
      |> MapSet.union(changed_overlay_rows(prev_overlays, overlays))

    if MapSet.size(changed_rows) == 0 do
      ""
    else
      IO.iodata_to_binary([
        row_patch_payload(lines, changed_rows, screen_width),
        overlay_patch_payload(overlays, changed_rows)
      ])
    end
  end

  defp full_redraw_payload(lines, overlays, screen_width) do
    output =
      lines
      |> Enum.with_index()
      |> Enum.map(fn {line, row} ->
        write_row_payload(row, line, screen_width)
      end)
      |> IO.iodata_to_binary()

    overlay_output = Breeze.TerminalOverlay.render_overlays(overlays)
    IO.iodata_to_binary(["\e[2J\e[H", output, overlay_output])
  end

  defp changed_base_rows(prev_lines, lines) do
    lines
    |> Enum.zip(prev_lines)
    |> Enum.with_index()
    |> Enum.reduce(MapSet.new(), fn
      {{line, line}, _row}, acc -> acc
      {_pair, row}, acc -> MapSet.put(acc, row)
    end)
  end

  defp changed_overlay_rows(prev_overlays, overlays) do
    prev_map = overlay_row_map(prev_overlays)
    next_map = overlay_row_map(overlays)

    Map.keys(prev_map)
    |> Kernel.++(Map.keys(next_map))
    |> MapSet.new()
    |> Enum.reduce(MapSet.new(), fn row, acc ->
      if Map.get(prev_map, row, MapSet.new()) == Map.get(next_map, row, MapSet.new()) do
        acc
      else
        MapSet.put(acc, row)
      end
    end)
  end

  defp overlay_row_map(overlays) do
    Enum.reduce(overlays, %{}, fn overlay, acc ->
      row = Map.get(overlay, :y, 0)
      sig = overlay_signature(overlay)
      Map.update(acc, row, MapSet.new([sig]), &MapSet.put(&1, sig))
    end)
  end

  defp overlay_signature(overlay) do
    {Map.get(overlay, :x), Map.get(overlay, :y), Breeze.TerminalOverlay.render_overlay(overlay)}
  end

  defp row_patch_payload(lines, changed_rows, screen_width) do
    changed_rows
    |> Enum.sort()
    |> Enum.map(fn row ->
      line = Enum.at(lines, row, "")
      write_row_payload(row, line, screen_width)
    end)
    |> IO.iodata_to_binary()
  end

  defp write_row_payload(row, line, screen_width) do
    visible_width = visible_width(line)

    if visible_width >= screen_width do
      [
        "\e[",
        Integer.to_string(row + 1),
        ";1H",
        line
      ]
    else
      [
        "\e[",
        Integer.to_string(row + 1),
        ";1H",
        line,
        "\e[",
        Integer.to_string(row + 1),
        ";",
        Integer.to_string(visible_width + 1),
        "H\e[K"
      ]
    end
  end

  defp visible_width(line) when is_binary(line) do
    BackBreeze.Utils.string_length(line)
  end

  defp overlay_patch_payload(overlays, changed_rows) do
    overlays
    |> Enum.filter(&MapSet.member?(changed_rows, Map.get(&1, :y, 0)))
    |> Breeze.TerminalOverlay.render_overlays()
  end

  defp initialize_decorations(decorations) do
    Enum.map(decorations, fn decoration ->
      decoration
      |> Map.put_new(:frame_index, 0)
      |> Map.put_new(:every_ms, 500)
    end)
  end

  defp prepare_decorations(output, decorations, state) do
    decorations
    |> initialize_decorations()
    |> Enum.reduce({output, []}, fn decoration, {acc, updated} ->
      {_animated_box, current_content, current_overlays} = render_decoration(decoration, state)

      {
        String.replace(acc, rendered_fragment(decoration.box, state), current_content,
          global: false
        ),
        [
          decoration
          |> Map.put(:current_content, current_content)
          |> Map.put(:current_overlays, current_overlays)
          | updated
        ]
      }
    end)
    |> then(fn {prepared_output, updated} -> {prepared_output, Enum.reverse(updated)} end)
  end

  defp advance_decorations(state) do
    Map.update!(state, :decorations, fn decorations ->
      Enum.map(decorations, fn decoration ->
        if decoration_active?(decoration, state) do
          Map.update(decoration, :frame_index, 1, &(&1 + 1))
        else
          decoration
        end
      end)
    end)
  end

  defp apply_decorations(output, decorations, state) do
    Enum.reduce(decorations, {output, []}, fn decoration, {acc, updated} ->
      if decoration_active?(decoration, state) do
        {_animated_box, current_content, current_overlays} = render_decoration(decoration, state)

        {
          String.replace(acc, decoration.current_content, current_content, global: false),
          [
            decoration
            |> Map.put(:current_content, current_content)
            |> Map.put(:current_overlays, current_overlays)
            | updated
          ]
        }
      else
        {acc, [decoration | updated]}
      end
    end)
    |> then(fn {final_output, updated} -> {final_output, Enum.reverse(updated)} end)
  end

  defp render_decoration(decoration, state) do
    now = System.monotonic_time(:millisecond)

    ctx = decoration_ctx(decoration, state, now)

    {animated_box, animate_opts} =
      if function_exported?(decoration.mod, :animate, 5) do
        decoration.mod
        |> apply(:animate, [:root, decoration.box, decoration.flags, decoration.state, ctx])
        |> normalize_animation_result()
      else
        {decoration.box, %{}}
      end

    {animated_box, rendered_fragment(animated_box, state), Map.get(animate_opts, :overlays, [])}
  end

  defp decoration_ctx(decoration, state, now) do
    %{
      phase: :async,
      frame: decoration.frame_index,
      now: now,
      pending?: pending_active?(state),
      focused?: (decoration[:owner_id] || decoration.id) == state.focused,
      last_render_at: state.last_render_at,
      last_interaction_at: state.last_interaction_at,
      theme: state.theme,
      id: decoration.id,
      layout: decoration[:layout]
    }
  end

  defp strip_private_use_chars(output) do
    output
    |> String.to_charlist()
    |> Enum.reject(&(&1 in 0xE000..0xF8FF))
    |> List.to_string()
  end

  defp rendered_fragment(box, state) do
    box
    |> BackBreeze.Box.render(terminal: state.terminal)
    |> Map.get(:content)
  end

  defp schedule_animation(%{decorations: []} = state), do: state

  defp schedule_animation(%{animation_timer: nil} = state) do
    case next_tick_delay(state) do
      nil ->
        %{state | next_tick_at: nil}

      delay ->
        timer = Process.send_after(self(), :animation_tick, delay)

        %{
          state
          | animation_timer: timer,
            next_tick_at: System.monotonic_time(:millisecond) + delay
        }
    end
  end

  defp schedule_animation(state), do: state

  defp next_tick_delay(state) do
    state.decorations
    |> Enum.map(&decoration_delay(&1, state))
    |> Enum.reject(&is_nil/1)
    |> Enum.min(fn -> nil end)
  end

  defp namespace_decoration(decoration, full_id, viewport) do
    decoration
    |> Map.update(:id, nil, &namespace_live_id(&1, full_id))
    |> Map.update(:owner_id, full_id, &namespace_live_id(&1, full_id))
    |> Map.update(:layout, nil, &translate_decoration_layout(&1, viewport))
  end

  defp translate_decoration_layout(%Breeze.Viewport{} = layout, %{left: left, top: top}) do
    %{layout | left: layout.left + left, top: layout.top + top}
  end

  defp translate_decoration_layout(layout, _viewport), do: layout

  defp translate_live_dimensions(elements, %{left: left, top: top} = viewport, prefix, child_box)
       when is_map(elements) do
    translated_elements =
      Map.new(elements, fn {id, viewport} ->
        translated_id =
          case id do
            value when is_binary(value) ->
              if String.starts_with?(value, prefix <> "::"),
                do: value,
                else: prefix <> "::" <> value
          end

        {translated_id,
         %{
           left: left + Map.get(viewport, :left, 0),
           top: top + Map.get(viewport, :top, 0),
           width: Map.get(viewport, :width, 0),
           height: Map.get(viewport, :height, 0),
           viewport_width: Map.get(viewport, :viewport_width, 0),
           viewport_height: Map.get(viewport, :viewport_height, 0),
           content_width: Map.get(viewport, :content_width, 0),
           content_height: Map.get(viewport, :content_height, 0)
         }}
      end)

    Map.put(
      translated_elements,
      prefix,
      live_root_dimensions(translated_elements, viewport, child_box)
    )
  end

  defp translate_live_dimensions(_elements, _viewport, _prefix, _child_box), do: %{}

  defp live_root_dimensions(translated_elements, viewport, child_box) do
    width = Map.get(viewport, :width, 0)
    height = Map.get(viewport, :height, 0)

    if width > 0 and height > 0 do
      %{
        left: Map.get(viewport, :left, 0),
        top: Map.get(viewport, :top, 0),
        width: width,
        height: height,
        viewport_width: Map.get(viewport, :viewport_width, width),
        viewport_height: Map.get(viewport, :viewport_height, height),
        content_width: Map.get(viewport, :content_width, width),
        content_height: Map.get(viewport, :content_height, height)
      }
    else
      case child_root_dimensions(viewport, child_box) do
        nil ->
          translated_elements
          |> Map.values()
          |> Enum.reduce(nil, fn dims, acc ->
            left = Map.get(dims, :left, 0)
            top = Map.get(dims, :top, 0)
            right = left + max(Map.get(dims, :width, 0) - 1, 0)
            bottom = top + max(Map.get(dims, :height, 0) - 1, 0)

            case acc do
              nil ->
                %{left: left, top: top, right: right, bottom: bottom}

              acc ->
                %{
                  left: min(acc.left, left),
                  top: min(acc.top, top),
                  right: max(acc.right, right),
                  bottom: max(acc.bottom, bottom)
                }
            end
          end)
          |> case do
            nil ->
              %{
                left: Map.get(viewport, :left, 0),
                top: Map.get(viewport, :top, 0),
                width: 0,
                height: 0,
                viewport_width: 0,
                viewport_height: 0,
                content_width: 0,
                content_height: 0
              }

            bounds ->
              width = max(bounds.right - bounds.left + 1, 0)
              height = max(bounds.bottom - bounds.top + 1, 0)

              %{
                left: bounds.left,
                top: bounds.top,
                width: width,
                height: height,
                viewport_width: width,
                viewport_height: height,
                content_width: width,
                content_height: height
              }
          end

        root_dims ->
          root_dims
      end
    end
  end

  defp child_root_dimensions(%{left: left, top: top}, %{width: width, height: height})
       when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    %{
      left: left,
      top: top,
      width: width,
      height: height,
      viewport_width: width,
      viewport_height: height,
      content_width: width,
      content_height: height
    }
  end

  defp child_root_dimensions(_viewport, _child_box), do: nil

  defp namespace_live_id(nil, _full_id), do: nil
  defp namespace_live_id(id, full_id), do: full_id <> "::" <> id

  defp decoration_active?(decoration, state) do
    cond do
      decoration[:active_when_pending] ->
        pending_active?(state)

      decoration[:active_when_focused] ->
        (decoration[:owner_id] || decoration[:id]) == state.focused

      true ->
        true
    end
  end

  defp pending_active?(%{pending_ref: nil}), do: false

  defp pending_active?(%{pending_started_at: started_at, busy_delay_ms: delay})
       when is_integer(started_at) do
    System.monotonic_time(:millisecond) - started_at >= delay
  end

  defp pending_active?(_state), do: false

  defp decoration_delay(decoration, state) do
    cond do
      decoration[:active_when_pending] && is_nil(state.pending_ref) ->
        nil

      decoration[:active_when_pending] && pending_active?(state) ->
        Map.get(decoration, :every_ms, state.frame_delay_ms)

      decoration[:active_when_pending] ->
        remaining_busy_delay(state)

      decoration_active?(decoration, state) ->
        Map.get(decoration, :every_ms, state.frame_delay_ms)

      true ->
        nil
    end
  end

  defp remaining_busy_delay(%{pending_started_at: started_at, busy_delay_ms: delay})
       when is_integer(started_at) do
    max(delay - (System.monotonic_time(:millisecond) - started_at), 0)
  end

  defp remaining_busy_delay(_state), do: nil

  defp terminal_overlays(decorations, state) do
    decoration_overlays =
      decorations
      |> Enum.filter(&decoration_active?(&1, state))
      |> Enum.flat_map(&Map.get(&1, :current_overlays, []))
      |> Enum.reject(&is_nil/1)

    decoration_overlays ++ Breeze.Inspector.overlays(state)
  end

  defp normalize_animation_result({:ok, %BackBreeze.Box{} = box, opts}) when is_list(opts) do
    {box, Map.new(opts)}
  end

  defp normalize_animation_result({:ok, %BackBreeze.Box{} = box}) do
    {box, %{}}
  end

  defp normalize_animation_result(%BackBreeze.Box{} = box) do
    {box, %{}}
  end

  defp viewports_from_acc(acc) do
    acc
    |> Breeze.RenderState.build_dimensions()
    |> Map.merge(Map.get(acc, :live_dimensions, %{}))
    |> Map.new(fn {id, dims} -> {id, Breeze.Viewport.from_dimensions(dims)} end)
  end

  defp patchable_live_child?(child_id) when is_binary(child_id), do: true
  defp patchable_live_child?(_child_id), do: false

  defp debug_child_id?("debug"), do: true
  defp debug_child_id?(_child_id), do: false

  defp wrap_child_fragment(child_box, viewport) do
    BackBreeze.Box.new(
      style: %{width: viewport.width, height: viewport.height, overflow: :hidden},
      children: [child_box]
    )
  end

  defp child_patch_payload(fragment, viewport) do
    fragment
    |> :binary.split("\n", [:global])
    |> Enum.with_index()
    |> Enum.map(fn {line, row_offset} ->
      row = Integer.to_string(viewport.top + row_offset + 1)
      col = Integer.to_string(viewport.left + 1)
      width = Integer.to_string(viewport.width)

      [
        "\e[",
        row,
        ";",
        col,
        "H",
        "\e[",
        width,
        "X",
        "\e[",
        row,
        ";",
        col,
        "H",
        line
      ]
    end)
    |> IO.iodata_to_binary()
  end

  defp stop(state) do
    if Process.alive?(state.view_pid) do
      Process.exit(state.view_pid, :normal)
    end

    terminal =
      state.terminal
      |> Termite.Screen.disable_mouse()
      |> Termite.Screen.clear_screen()
      |> Termite.Screen.show_cursor()
      |> Termite.Screen.exit_alt_screen()

    terminal = Termite.Terminal.write(terminal, "\r")
    {:stop, :normal, %{state | terminal: terminal}}
  end

  defp crashed?(%{crash: crash}), do: not is_nil(crash)

  defp safe_apply_input_reply(state, fun) do
    case safe_call(fn -> fun.(state) end) do
      {:ok, {:crash, crash}} -> {:noreply, enter_crash_state(state, crash)}
      {:ok, reply} -> apply_input_reply(state, reply)
      {:crash, crash} -> {:noreply, enter_crash_state(state, crash)}
    end
  end

  defp safe_call(fun) when is_function(fun, 0) do
    try do
      {:ok, fun.()}
    rescue
      exception ->
        {:crash, crash_info(:error, exception, __STACKTRACE__)}
    catch
      :exit, reason ->
        {:crash, crash_info(:exit, reason, __STACKTRACE__)}

      kind, reason ->
        {:crash, crash_info(kind, reason, __STACKTRACE__)}
    end
  end

  defp crash_info(kind, reason, stacktrace) do
    %{
      kind: kind,
      reason: reason,
      stacktrace: stacktrace,
      selected_index: nil,
      focused: "error-stacktrace",
      implicit_state: %{}
    }
  end

  defp enter_crash_state(state, crash) do
    cancel_timer(state.animation_timer)
    terminal = apply_mouse_mode(state.terminal, false)
    crash = Breeze.ErrorView.prepare_crash(state.view, crash, terminal.size)

    state
    |> Map.put(:terminal, terminal)
    |> Map.put(:crash, crash)
    |> Map.put(:pending_ref, nil)
    |> Map.put(:pending_started_at, nil)
    |> Map.put(:input_flush_scheduled?, false)
    |> Map.put(:queued_input, :queue.new())
    |> Map.put(:animation_timer, nil)
    |> Map.put(:next_tick_at, nil)
    |> Map.put(:decorations, [])
    |> put_debug_stat(:last_render_cause, :crash)
    |> render_crash()
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  defp render_crash(state) do
    crash = Breeze.ErrorView.prepare_crash(state.view, state.crash, state.terminal.size)

    content =
      Breeze.ErrorView.render_assigns(state.view, crash, state.terminal.size)
      |> then(
        &Breeze.Renderer.render_to_string(Breeze.ErrorView, &1,
          terminal: state.terminal,
          focused: crash.focused,
          implicit_state: crash.implicit_state
        )
      )

    state
    |> Map.put(:crash, crash)
    |> Map.put(:base_output, content)
    |> Map.put(:last_frame_payload, nil)
    |> Map.put(:last_frame_lines, nil)
    |> Map.put(:last_overlays, [])
    |> render_frame()
  end

  defp dispatch_crash_input(input, %{crash: crash} = state) do
    case Breeze.ErrorView.handle_input(state.view, crash, input, state.terminal.size) do
      :restart ->
        restart_root(state, :restart)

      {:update, updated_crash} ->
        state |> Map.put(:crash, updated_crash) |> render_crash()
    end
  end

  defp reload_after_code_change(state) do
    state = prune_dead_children(state)

    case refresh_reload_state(state) do
      {:ok, state} ->
        maybe_render_base(state, :reload)

      {:restart, state} ->
        restart_root(state, :reload)

      {:error, crash} ->
        enter_crash_state(state, crash)
    end
  end

  defp restart_root(state, cause) do
    state = %{state | terminal: apply_mouse_mode(state.terminal, state.mouse_mode)}
    shutdown_root_view(state.view_pid)

    case start_root_view(state) do
      {:ok, pid, focused, theme} ->
        state
        |> Map.put(:view_pid, pid)
        |> Map.put(:focused, focused)
        |> Map.put(:theme, theme)
        |> Map.put(:crash, nil)
        |> Map.put(:children, %{})
        |> Map.put(:decorations, [])
        |> Map.put(:base_output, "")
        |> Map.put(:last_frame_payload, nil)
        |> Map.put(:last_frame_lines, nil)
        |> Map.put(:last_overlays, [])
        |> Map.put(:pending_ref, nil)
        |> Map.put(:pending_started_at, nil)
        |> Map.put(:queued_input, :queue.new())
        |> Map.put(:input_flush_scheduled?, false)
        |> maybe_render_base(cause)

      {:error, crash} ->
        enter_crash_state(state, crash)
    end
  end

  defp apply_mouse_mode(terminal, false), do: Termite.Screen.disable_mouse(terminal)
  defp apply_mouse_mode(terminal, nil), do: Termite.Screen.disable_mouse(terminal)
  defp apply_mouse_mode(terminal, true), do: Termite.Screen.enable_mouse(terminal)

  defp apply_mouse_mode(terminal, opts) when is_list(opts),
    do: Termite.Screen.enable_mouse(terminal, opts)

  defp start_root_view(state) do
    session = self()

    case safe_call(fn ->
           Breeze.ChildServer.start(
             view: state.view,
             start_opts: state.start_opts || [],
             terminal: state.terminal,
             theme: state.theme,
             server: self(),
             global_keybindings: state.global_keybindings || [],
             invalidate: fn -> send(session, :child_invalidated) end
           )
         end) do
      {:ok, {:ok, pid}} ->
        Process.monitor(pid)

        {focused, theme} =
          case safe_call(fn -> Breeze.ChildServer.metadata(pid) end) do
            {:ok, %{focused: focused, theme: child_theme}} -> {focused, child_theme}
            {:ok, %{focused: focused}} -> {focused, state.theme}
            _ -> {nil, state.theme}
          end

        {:ok, pid, focused, theme}

      {:ok, other} ->
        {:error,
         crash_info(
           :error,
           RuntimeError.exception("unexpected child start result: #{inspect(other)}"),
           []
         )}

      {:crash, crash} ->
        {:error, crash}
    end
  end

  defp shutdown_root_view(nil), do: :ok

  defp shutdown_root_view(pid) do
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal)
    else
      :ok
    end
  end

  defp refresh_reload_state(state) do
    case Keyword.get(state.reload_opts || [], :refresh_server_opts) do
      nil ->
        {:ok, state}

      refresh ->
        with {:ok, refreshed_opts} <- call_refresh_server_opts(refresh),
             {:ok, state} <- apply_refreshed_server_opts(state, refreshed_opts) do
          {:ok, state}
        else
          {:restart, state} -> {:restart, state}
          {:error, crash} -> {:error, crash}
        end
    end
  end

  defp call_refresh_server_opts({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args) do
    case safe_call(fn -> apply(module, function, args) end) do
      {:ok, opts} when is_list(opts) ->
        {:ok, opts}

      {:ok, other} ->
        {:error,
         crash_info(
           :error,
           RuntimeError.exception(
             "refresh_server_opts must return a keyword list, got: #{inspect(other)}"
           ),
           []
         )}

      {:crash, crash} ->
        {:error, crash}
    end
  end

  defp apply_refreshed_server_opts(state, refreshed_opts) do
    refreshed_view = Keyword.get(refreshed_opts, :view, state.view)
    refreshed_start_opts = Keyword.get(refreshed_opts, :start_opts, state.start_opts)

    if refreshed_view != state.view or refreshed_start_opts != state.start_opts do
      {:restart,
       state
       |> Map.put(:view, refreshed_view)
       |> Map.put(:start_opts, refreshed_start_opts)
       |> Map.put(:mouse_mode, Keyword.get(refreshed_opts, :mouse, state.mouse_mode))
       |> Map.put(
         :global_keybindings,
         Keyword.get(refreshed_opts, :global_keybindings, state.global_keybindings)
       )}
    else
      global_keybindings =
        Keyword.get(refreshed_opts, :global_keybindings, state.global_keybindings)

      mouse_mode = Keyword.get(refreshed_opts, :mouse, state.mouse_mode)

      terminal =
        if mouse_mode == state.mouse_mode,
          do: state.terminal,
          else: apply_mouse_mode(state.terminal, mouse_mode)

      case update_live_global_keybindings(state, global_keybindings) do
        :ok ->
          {:ok,
           state
           |> Map.put(:global_keybindings, global_keybindings)
           |> Map.put(:mouse_mode, mouse_mode)
           |> Map.put(:terminal, terminal)}

        {:error, crash} ->
          {:error, crash}
      end
    end
  end

  defp update_live_global_keybindings(state, global_keybindings) do
    if is_pid(state.view_pid) and Process.alive?(state.view_pid) do
      case safe_call(fn ->
             Breeze.ChildServer.put_global_keybindings(state.view_pid, global_keybindings)
           end) do
        {:ok, :ok} ->
          :ok

        {:ok, other} ->
          {:error,
           crash_info(
             :error,
             RuntimeError.exception("unexpected child update result: #{inspect(other)}"),
             []
           )}

        {:crash, crash} ->
          {:error, crash}
      end
    else
      :ok
    end
  end

  defp prune_dead_children(state) do
    alive_children =
      state.children
      |> Enum.filter(fn {_id, child} -> is_pid(child.pid) and Process.alive?(child.pid) end)
      |> Map.new()

    %{state | children: alive_children}
  end

  defp maybe_start_reloader(%{reload_opts: nil} = state), do: state

  defp maybe_start_reloader(state) do
    {:ok, pid} =
      Breeze.CodeReloader.start_link(Keyword.put(state.reload_opts, :server_pid, self()))

    %{state | reloader_pid: pid}
  end

  defp normalize_reload_opts(false), do: nil
  defp normalize_reload_opts(nil), do: nil

  defp normalize_reload_opts(true) do
    if reload_supported?(), do: [enabled?: true], else: nil
  end

  defp normalize_reload_opts(opts) when is_list(opts) do
    enabled? = Keyword.get(opts, :enabled?, true)
    force? = Keyword.get(opts, :force?, false)

    if enabled? and (force? or reload_supported?()) do
      opts
    else
      nil
    end
  end

  defp reload_supported? do
    Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :dev
  end

  defp ensure_children(state, missing) do
    Enum.reduce(missing, {state, false}, fn {id, attrs}, {state, started?} ->
      view = fetch_live_attr!(attrs, :view)
      start_opts = child_start_opts(fetch_live_attr(attrs, :start_opts, []), view, state)
      assigns = fetch_live_attr(attrs, :assigns, %{}) |> Map.new()

      case Map.get(state.children, id) do
        %{pid: pid, view: ^view, start_opts: ^start_opts} = child when is_pid(pid) ->
          if Process.alive?(pid) do
            if Map.get(child, :assigns, %{}) == assigns do
              {state, started?}
            else
              :ok = Breeze.ChildServer.update_assigns(pid, assigns)
              child = %{child | assigns: assigns}
              {%{state | children: Map.put(state.children, id, child)}, true}
            end
          else
            ref = Map.get(child, :ref)
            if is_reference(ref), do: Process.demonitor(ref, [:flush])

            child = start_child!(attrs, state.terminal, state.theme, state)
            {%{state | children: Map.put(state.children, id, child)}, true}
          end

        %{pid: pid, ref: ref} ->
          if is_pid(pid) and Process.alive?(pid), do: Process.exit(pid, :normal)
          if is_reference(ref), do: Process.demonitor(ref, [:flush])

          child = start_child!(attrs, state.terminal, state.theme, state)
          {%{state | children: Map.put(state.children, id, child)}, true}

        nil ->
          child = start_child!(attrs, state.terminal, state.theme, state)
          {%{state | children: Map.put(state.children, id, child)}, true}
      end
    end)
  end

  defp start_async_dispatch(state, key) do
    caller = self()
    ref = make_ref()

    Task.start(fn ->
      reply = dispatch_input_hierarchy(state, key)
      send(caller, {:event_reply, ref, reply})
    end)

    state
    |> Map.put(:pending_ref, ref)
    |> Map.put(:pending_started_at, System.monotonic_time(:millisecond))
    |> put_debug_stat(:last_async_key, key)
    |> schedule_animation()
  end

  defp key_name(%{"key" => key}) when is_binary(key), do: key
  defp key_name(key) when is_binary(key), do: key
  defp key_name(_), do: nil

  defp put_debug_stat(state, key, value) do
    state
    |> Map.update(:debug_stats, %{key => value}, &Map.put(&1, key, value))
    |> maybe_record_debug_sample(key, value)
    |> schedule_debug_push()
  end

  defp increment_debug_stat(state, key) do
    now = System.monotonic_time(:millisecond)

    state
    |> Map.update(:debug_stats, %{key => 1}, &Map.update(&1, key, 1, fn value -> value + 1 end))
    |> update_debug_rate(key, now)
    |> schedule_debug_push()
  end

  defp maybe_record_debug_sample(state, key, value) when is_integer(value) do
    if tracked_timing_key?(key) do
      state
      |> update_debug_history(key, value)
      |> update_debug_summary(key)
    else
      state
    end
  end

  defp maybe_record_debug_sample(state, _key, _value), do: state

  defp tracked_timing_key?(key) do
    key in [
      :last_root_snapshot_app_us,
      :last_live_children_app_us,
      :last_render_base_app_us,
      :last_prepare_decorations_us,
      :last_frame_compose_us,
      :last_terminal_write_us,
      :last_frame_us,
      :last_animation_us
    ]
  end

  defp update_debug_history(state, key, value) do
    history_key = {:history, key}

    Map.update(state, :debug_stats, %{history_key => [value]}, fn stats ->
      history =
        stats
        |> Map.get(history_key, [])
        |> Kernel.++([value])
        |> Enum.take(-@debug_window_size)

      Map.put(stats, history_key, history)
    end)
  end

  defp update_debug_summary(state, key) do
    history_key = {:history, key}
    avg_key = {:avg, key}
    max_key = {:max, key}

    Map.update!(state, :debug_stats, fn stats ->
      history = Map.get(stats, history_key, [])

      if history == [] do
        stats
      else
        avg = div(Enum.sum(history), length(history))
        max_value = Enum.max(history)

        stats
        |> Map.put(avg_key, avg)
        |> Map.put(max_key, max_value)
      end
    end)
  end

  defp update_debug_rate(state, key, now) do
    rate_key = {:rate, key}

    Map.update(state, :debug_stats, %{rate_key => 1}, fn stats ->
      timestamps =
        stats
        |> Map.get({:rate_window, key}, [])
        |> Kernel.++([now])
        |> Enum.filter(fn timestamp -> now - timestamp <= @debug_rate_window_ms end)

      stats
      |> Map.put({:rate_window, key}, timestamps)
      |> Map.put(rate_key, length(timestamps))
    end)
  end

  defp push_debug_stats_now(state) do
    stats = debug_stats_snapshot(state)

    Enum.each(state.debug_subscribers, fn subscriber ->
      if is_pid(subscriber) and Process.alive?(subscriber) do
        send(subscriber, {:debug_stats, stats})
      end
    end)

    state
  end

  defp schedule_debug_push(%{debug_push_timer: nil, debug_push_interval_ms: interval} = state) do
    %{state | debug_push_timer: Process.send_after(self(), :debug_push, interval)}
  end

  defp schedule_debug_push(state), do: state

  defp start_child!(attrs, terminal, theme, state) do
    view = fetch_live_attr!(attrs, :view)
    start_opts = child_start_opts(fetch_live_attr(attrs, :start_opts, []), view, state)
    assigns = fetch_live_attr(attrs, :assigns, %{}) |> Map.new()
    persistent = fetch_live_attr(attrs, :persistent, false)
    parent = self()
    child_id = fetch_live_attr!(attrs, :id)
    invalidate = fn -> send(parent, {:child_invalidated, child_id}) end

    {:ok, pid} =
      Breeze.ChildServer.start(
        view: view,
        start_opts: start_opts,
        assigns: assigns,
        server: self(),
        terminal: terminal,
        theme: theme,
        invalidate: invalidate
      )

    ref = Process.monitor(pid)

    %{
      pid: pid,
      ref: ref,
      view: view,
      start_opts: start_opts,
      assigns: assigns,
      persistent: persistent
    }
  end

  defp child_start_opts(start_opts, Breeze.Debug, state) do
    Keyword.put_new(start_opts, :stats, debug_stats_snapshot(state))
  end

  defp child_start_opts(start_opts, _view, _state), do: start_opts

  defp merge_inspector_render_data(%{inspector: false} = state, _acc), do: state

  defp merge_inspector_render_data(state, acc) do
    metadata = safe_root_metadata(state)
    %{viewports: viewports, bounds: bounds, flags: flags, boxes: boxes} = inspector_nodes(acc)

    state
    |> Map.put(:rendered_viewports, viewports)
    |> Map.put(:rendered_mouse_targets, bounds)
    |> Map.put(:rendered_flags, flags)
    |> Map.update(:rendered_boxes, boxes, &Map.merge(&1, boxes))
    |> Map.put(:rendered_focus_meta, Map.get(metadata, :focus_meta, %{}))
    |> Map.put(:rendered_implicit_state, Map.get(metadata, :implicit_state, %{}))
    |> Map.put(:rendered_implicit_meta, Map.get(metadata, :implicit_meta, %{}))
    |> Breeze.Inspector.sync_selected_id()
  end

  defp debug_stats_snapshot(state) do
    state.debug_stats
    |> Map.put(:focused, state.focused)
    |> Map.put(:pending?, not is_nil(state.pending_ref))
    |> Map.put(:screen, state.terminal.size)
  end

  defp safe_root_metadata(state) do
    case safe_call(fn -> Breeze.ChildServer.metadata(state.view_pid) end) do
      {:ok, metadata} -> metadata
      {:crash, _crash} -> %{}
    end
  end

  defp inspector_nodes(acc) do
    source_boxes = Map.get(acc, :boxes, %{})

    acc.elements
    |> Enum.sort()
    |> Enum.zip(acc.dimensions)
    |> Enum.reduce(%{viewports: %{}, bounds: %{}, flags: %{}, boxes: %{}}, fn {{idx, flags}, dims},
                                                                              node_acc ->
      key = inspector_node_key(idx, flags)
      viewport = Breeze.Viewport.from_dimensions(dims)

      width = max((viewport.width || 0) - 1, 0)
      height = max(viewport.height - 1, 0)
      normalized_flags = Keyword.put(flags, :__inspector_idx__, idx)

      bounds = %{
        left: viewport.left,
        top: viewport.top,
        right: viewport.left + width,
        bottom: viewport.top + height
      }

      %{
        viewports: Map.put(node_acc.viewports, key, viewport),
        bounds: Map.put(node_acc.bounds, key, bounds),
        flags: Map.put(node_acc.flags, key, normalized_flags),
        boxes:
          case Map.get(node_acc.boxes, key) do
            nil ->
              case Map.get(source_boxes, idx) || Map.get(source_boxes, Keyword.get(flags, :id)) do
                nil -> node_acc.boxes
                box -> Map.put(node_acc.boxes, key, box)
              end

            _box ->
              node_acc.boxes
          end
      }
    end)
  end

  defp inspector_node_key(idx, flags) do
    case Keyword.get(flags, :id) do
      id when is_binary(id) -> id
      _ -> "__inspector__" <> Integer.to_string(idx)
    end
  end

  defp push_inspector_snapshot_now(%{inspector: false} = state), do: state

  defp push_inspector_snapshot_now(%{inspector_subscribers: subscribers} = state) do
    snapshot = Breeze.Inspector.snapshot(state)
    Breeze.RemoteInspector.publish(snapshot)

    if MapSet.size(subscribers) > 0 do
      Enum.each(subscribers, fn subscriber ->
        if is_pid(subscriber), do: send(subscriber, {:inspector_snapshot, snapshot})
      end)
    end

    state
  end

  defp begin_render_tracking do
    ensure_render_tracking_table!()
    make_ref()
  end

  defp finish_render_tracking(ref) do
    ensure_render_tracking_table!()

    entries = :ets.take(@render_tracking_table, ref)

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

  defp dedupe_decorations(decorations) do
    decorations
    |> Enum.reverse()
    |> Enum.uniq_by(&tracked_decoration_identity/1)
    |> Enum.reverse()
  end

  defp tracked_decoration_identity(decoration) do
    {
      Map.get(decoration, :id),
      Map.get(decoration, :owner_id),
      Map.get(decoration, :mod)
    }
  end

  defp track_missing_live_child(ref, item) do
    ensure_render_tracking_table!()
    true = :ets.insert(@render_tracking_table, {ref, :missing, item})
    :ok
  end

  defp track_render_decoration(ref, decoration) do
    ensure_render_tracking_table!()
    true = :ets.insert(@render_tracking_table, {ref, :decoration, decoration})
    :ok
  end

  defp track_child_timing(ref, child_timing) do
    ensure_render_tracking_table!()
    true = :ets.insert(@render_tracking_table, {ref, :child_timing, child_timing})
    :ok
  end

  defp ensure_render_tracking_table! do
    case :ets.whereis(@render_tracking_table) do
      :undefined ->
        try do
          :ets.new(@render_tracking_table, [:named_table, :public, :bag])
        rescue
          ArgumentError -> :ok
        end

      _tid ->
        :ok
    end
  end

  defp enqueue_input(state, decoded), do: update_in(state.queued_input, &:queue.in(decoded, &1))

  defp schedule_input_flush(%{input_flush_scheduled?: true} = state), do: state

  defp schedule_input_flush(%{queued_input: {[], []}} = state), do: state

  defp schedule_input_flush(state) do
    send(self(), @flush_input_batch)
    %{state | input_flush_scheduled?: true}
  end

  defp sum_timing_us(child_timings) do
    Enum.reduce(child_timings, 0, fn %{us: us}, acc -> acc + us end)
  end

  defp debug_live_child_us(child_timings) do
    child_timings
    |> Enum.filter(&debug_child_timing?/1)
    |> sum_timing_us()
  end

  defp non_debug_child_timings(child_timings) do
    Enum.reject(child_timings, &debug_child_timing?/1)
  end

  defp debug_child_timing?(%{id: "debug"}), do: true
  defp debug_child_timing?(_timing), do: false

  defp normalize_child_timings(child_timings) do
    child_timings
    |> Enum.sort_by(& &1.us, :desc)
    |> Enum.take(5)
    |> Enum.map(fn timing ->
      timing
      |> Map.update!(:view, &inspect/1)
    end)
  end

  defp summarize_profile(entries) do
    entries
    |> Enum.filter(fn entry ->
      entry.metric in [
        :view_render_us,
        :template_tree_us,
        :build_tree_us,
        :layout_us,
        :render_with_dimensions_us,
        :item_render_us,
        :compose_us,
        :render_children_us,
        :container_render_self_us,
        :container_layer_map_us,
        :layer_maps_to_content_us
      ]
    end)
    |> Enum.take(6)
    |> Enum.map(fn %{label: label, metric: metric, value: value} ->
      %{label: shorten_label(label), metric: metric, value: value}
    end)
  end

  defp shorten_label(label) when is_binary(label) do
    if String.length(label) > 28 do
      String.slice(label, 0, 28)
    else
      label
    end
  end

  defp root_view_module(%{children: _} = state) do
    case safe_call(fn -> Breeze.ChildServer.metadata(state.view_pid) end) do
      {:ok, %{view: view}} -> view
      _ -> nil
    end
  catch
    :exit, _reason -> nil
  end

  defp dispatch_input_hierarchy(state, key) do
    child_reply =
      state
      |> focused_child_chain()
      |> Enum.reduce_while(nil, fn {child_id, %{pid: pid}}, _acc ->
        case safe_call(fn -> Breeze.ChildServer.dispatch_input(pid, key) end) do
          {:ok, reply} ->
            reply = namespace_child_reply(reply, child_id)

            case reply do
              {:noreply, _focused, true} -> {:halt, reply}
              {:stop, _focused, _consumed} -> {:halt, reply}
              _ -> {:cont, nil}
            end

          {:crash, crash} ->
            {:halt, {:crash, crash}}
        end
      end)

    case child_reply do
      {:crash, _crash} = crash ->
        crash

      nil ->
        case safe_call(fn -> Breeze.ChildServer.dispatch_input(state.view_pid, key) end) do
          {:ok, reply} -> reply
          {:crash, crash} -> {:crash, crash}
        end

      reply ->
        reply
    end
  end

  defp queue_out(queue), do: :queue.out(queue)

  defp queue_peek(queue) do
    case :queue.peek(queue) do
      :empty -> :empty
      value -> {:value, value}
    end
  end

  defp raw_printable_key?(key) when is_binary(key) do
    String.length(key) == 1 and key not in ["\n", "\r", "\t", "\v", "\f"] and
      String.printable?(key) and not String.match?(key, ~r/[\x00-\x1F\x7F]/u)
  end

  defp raw_printable_key?(_key), do: false

  defp batched_printable_event(key), do: %{"key" => key, "__batched_printable__" => true}

  defp focused_child_chain(%{focused: nil}), do: []

  defp focused_child_chain(%{focused: focused, children: children}) do
    children
    |> Enum.filter(fn {id, _child} ->
      focused == id or String.starts_with?(focused, id <> "::")
    end)
    |> Enum.sort_by(fn {id, _child} -> String.length(id) end, :desc)
  end

  defp namespace_child_reply({:stop, focused}, child_id),
    do: {:stop, namespace_child_focus(focused, child_id)}

  defp namespace_child_reply({:stop, focused, consumed}, child_id),
    do: {:stop, namespace_child_focus(focused, child_id), consumed}

  defp namespace_child_reply({:noreply, focused}, child_id),
    do: {:noreply, namespace_child_focus(focused, child_id)}

  defp namespace_child_reply({:noreply, focused, consumed}, child_id),
    do: {:noreply, namespace_child_focus(focused, child_id), consumed}

  defp namespace_child_focus(nil, _child_id), do: nil
  defp namespace_child_focus(focused, child_id), do: child_id <> "::" <> focused

  defp strip_live_prefix(nil, _live_id), do: nil

  defp strip_live_prefix(id, live_id) do
    prefix = live_id <> "::"

    if String.starts_with?(id, prefix) do
      String.replace_prefix(id, prefix, "")
    end
  end

  defp live_id(nil, id), do: id
  defp live_id(prefix, id), do: prefix <> "::" <> id

  defp fetch_live_attr!(attrs, key) do
    Map.get(attrs, key) || Map.fetch!(attrs, Atom.to_string(key))
  end

  defp fetch_live_attr(attrs, key, default) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key), default)
  end
end
