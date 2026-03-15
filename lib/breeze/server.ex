defmodule Breeze.Term do
  @moduledoc false

  defstruct [
    :view,
    :server,
    :terminal,
    :reader,
    last_render_at: nil,
    last_interaction_at: nil,
    assigns: %{},
    global_keybindings: [],
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
    render_timer: nil
  ]
end

defmodule Breeze.Server do
  @moduledoc """
  Public server entrypoint for Breeze applications.
  """

  use GenServer

  @render_tracking_table __MODULE__.RenderTracking
  @flush_input_batch :flush_input_batch

  defstruct [
    :terminal,
    :reader,
    :view_pid,
    :focused,
    :base_output,
    :pending_ref,
    :pending_started_at,
    :last_render_at,
    :last_interaction_at,
    queued_input: [],
    input_flush_scheduled?: false,
    decorations: [],
    children: %{},
    animation_timer: nil,
    next_tick_at: nil,
    global_keybindings: [],
    debug_subscribers: MapSet.new(),
    debug_stats: %{},
    debug_push_timer: nil,
    debug_push_interval_ms: 250,
    busy_delay_ms: 120,
    frame_delay_ms: 80
  ]

  @type option ::
          {:view, module()}
          | {:start_opts, keyword()}
          | {:hide_cursor, boolean()}
          | {:mouse, boolean() | keyword()}
          | {:global_keybindings, list()}
          | {:frame_delay_ms, pos_integer()}

  @doc """
  Start the Breeze application.

  Valid options are:

    * `:view` - the view to run. This is required
    * `:hide_cursor` - hide the cursor on start. Defaults to `false`
    * `:mouse` - enable mouse tracking. Defaults to `false`. Pass `true` for click mode or keyword options for `Termite.Screen.enable_mouse/2`
    * `:global_keybindings` - app-wide keybindings checked before focused event handling

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

  @spec subscribe_debug(pid(), pid()) :: :ok
  def subscribe_debug(pid, subscriber) do
    GenServer.cast(pid, {:subscribe_debug, subscriber})
  end

  @impl true
  def init(opts) do
    view = Keyword.fetch!(opts, :view)
    start_opts = Keyword.get(opts, :start_opts, [])
    frame_delay_ms = Keyword.get(opts, :frame_delay_ms, 80)
    terminal = Keyword.fetch!(opts, :terminal)

    session = self()

    {:ok, view_pid} =
      Breeze.ChildServer.start(
        view: view,
        start_opts: start_opts,
        terminal: terminal,
        server: self(),
        global_keybindings: Keyword.get(opts, :global_keybindings, []),
        invalidate: fn -> send(session, :child_invalidated) end
      )

    Process.monitor(view_pid)

    focused =
      case Breeze.ChildServer.metadata(view_pid) do
        %{focused: focused} -> focused
        _ -> nil
      end

    state = %__MODULE__{
      terminal: terminal,
      reader: Keyword.get(opts, :reader, terminal.reader),
      view_pid: view_pid,
      focused: focused,
      global_keybindings: Keyword.get(opts, :global_keybindings, []),
      busy_delay_ms: Keyword.get(opts, :busy_delay_ms, 120),
      frame_delay_ms: frame_delay_ms,
      base_output: "",
      pending_started_at: nil,
      last_render_at: System.monotonic_time(:millisecond),
      last_interaction_at: nil
    }

    {:ok, render_base(state)}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply,
     state.debug_stats
     |> Map.put(:focused, state.focused)
     |> Map.put(:pending?, not is_nil(state.pending_ref))
     |> Map.put(:screen, state.terminal.size), state}
  end

  @impl true
  def handle_cast({:subscribe_debug, subscriber}, state) do
    if is_pid(subscriber), do: Process.monitor(subscriber)

    state =
      state
      |> Map.update!(:debug_subscribers, &MapSet.put(&1, subscriber))
      |> push_debug_stats_now()

    {:noreply, state}
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
    terminal = Termite.Terminal.resize(state.terminal)
    state = %{state | terminal: terminal}

    case Breeze.ChildServer.dispatch_info(state.view_pid, :resize, terminal) do
      {:stop, _focused} ->
        stop(state)

      {:noreply, focused} ->
        {:noreply, maybe_render_base(%{state | focused: focused})}
    end
  end

  def handle_info(:child_invalidated, state) do
    {:noreply, maybe_render_base(state)}
  end

  def handle_info({:child_invalidated, _id}, state) do
    {:noreply, maybe_render_base(state)}
  end

  def handle_info(@flush_input_batch, state) do
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
    {:noreply, %{state | animation_timer: nil, next_tick_at: nil}}
  end

  def handle_info(:animation_tick, state) do
    started_at = System.monotonic_time(:microsecond)

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

  def handle_info({:event_reply, ref, reply}, %{pending_ref: ref} = state) do
    case reply do
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
          |> maybe_render_base()

        {:noreply, state}

      {:noreply, focused, _consumed} ->
        state =
          state
          |> Map.put(:pending_ref, nil)
          |> Map.put(:pending_started_at, nil)
          |> Map.put(:focused, focused)
          |> maybe_render_base()

        {:noreply, state}
    end
  end

  def handle_info({:event_reply, _ref, _reply}, state), do: {:noreply, state}

  def handle_info(message, state) do
    case message do
      {:DOWN, _, :process, pid, _reason} when pid == state.view_pid ->
        stop(state)

      {:DOWN, ref, :process, _pid, _reason} ->
        cond do
          MapSet.member?(state.debug_subscribers, elem(message, 3)) ->
            {:noreply,
             %{
               state
               | debug_subscribers: MapSet.delete(state.debug_subscribers, elem(message, 3))
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

  defp flush_input_batch(%{queued_input: []} = state), do: {:noreply, state}

  defp flush_input_batch(%{queued_input: [decoded | rest]} = state) do
    state = %{state | queued_input: rest}

    case process_batched_input(decoded, state) do
      {:stop, state} ->
        {:stop, state}

      {:noreply, state} ->
        continue_flushing_or_pause(state)
    end
  end

  defp process_batched_input({:mouse, %{button: button} = event}, state)
       when button in [:wheel_down, :wheel_up] do
    {event, state} = coalesce_wheel_events_from_queue(event, state, 1)
    handle_mouse(event, state)
  end

  defp process_batched_input(decoded, state), do: handle_deferred_or_sync_input(decoded, state)

  defp continue_flushing_or_pause(%{queued_input: [next | _]} = state) do
    if sync_input_message?(next, state) do
      flush_input_batch(state)
    else
      {:noreply, state}
    end
  end

  defp continue_flushing_or_pause(state), do: {:noreply, state}

  defp handle_deferred_or_sync_input(decoded, state) do
    if sync_input_message?(decoded, state) do
      handle_decoded_sync_input(decoded, state)
    else
      handle_deferred_input(decoded, state)
    end
  end

  defp handle_decoded_sync_input({:mouse, event}, state) do
    handle_mouse(event, state)
  end

  defp handle_decoded_sync_input({:key, key}, state) do
    case key do
      key when key in ["\t", "ShiftTab"] ->
        state
        |> touch_interaction()
        |> apply_input_reply(Breeze.ChildServer.dispatch_input(state.view_pid, key))

      key ->
        state
        |> touch_interaction()
        |> apply_input_reply(dispatch_input_hierarchy(state, key))
    end
  end

  defp handle_deferred_input({:key, _key}, %{pending_ref: ref} = state) when not is_nil(ref) do
    {:noreply, state}
  end

  defp handle_deferred_input({:key, key}, state) do
    {:noreply, start_async_dispatch(touch_interaction(state), key)}
  end

  defp handle_deferred_input(_decoded, state), do: {:noreply, state}

  defp sync_input_message?({:mouse, _event}, %{pending_ref: nil}), do: true
  defp sync_input_message?({:mouse, _event}, _state), do: false

  defp sync_input_message?({:key, key}, state) do
    stop_global_key?(key, state) or
      (is_nil(state.pending_ref) and
         (key in ["\t", "ShiftTab"] or sync_input?(state, key)))
  end

  defp sync_input_message?(_, _state), do: false

  defp coalesce_wheel_events_from_queue(event, %{queued_input: [next | rest]} = state, repeat) do
    case next do
      {:mouse, %{button: button} = next_event} ->
        if button == event.button and wheel_match?(event, next_event) do
          coalesce_wheel_events_from_queue(event, %{state | queued_input: rest}, repeat + 1)
        else
          {Map.put(event, :repeat, repeat), state}
        end

      _ ->
        {Map.put(event, :repeat, repeat), state}
    end
  end

  defp coalesce_wheel_events_from_queue(event, state, repeat),
    do: {Map.put(event, :repeat, repeat), state}

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

  defp sync_input?(state, key) do
    key in ["\t", "ShiftTab"] or focused_implicit?(state)
  end

  defp stop_global_key?(key, state) do
    Breeze.GlobalKeybindings.stop_action?(%{"key" => key}, state)
  end

  defp focused_implicit?(%{focused: nil}), do: false

  defp focused_implicit?(state) do
    case focused_child_chain(state) do
      [{_child_id, %{pid: pid}} | _] ->
        match?(%{focused_implicit_id: id} when not is_nil(id), Breeze.ChildServer.metadata(pid))

      [] ->
        match?(
          %{focused_implicit_id: id} when not is_nil(id),
          Breeze.ChildServer.metadata(state.view_pid)
        )
    end
  end

  defp handle_mouse(event, state) do
    state
    |> touch_interaction()
    |> apply_input_reply(Breeze.ChildServer.dispatch_input(state.view_pid, %{"mouse" => event}))
  end

  defp render_base(state, attempts \\ 1)

  defp render_base(state, attempts) do
    tracking_ref = begin_render_tracking()
    started_at = System.monotonic_time(:microsecond)
    profile_scope = make_ref()
    Breeze.DebugProfiler.reset(profile_scope)
    root_started_at = System.monotonic_time(:microsecond)

    {:ok, _acc, box, decorations} =
      Breeze.ChildServer.render_snapshot(state.view_pid,
        implicit_state: %{},
        terminal: state.terminal,
        render_tracking_ref: tracking_ref,
        profile_scope: profile_scope,
        profile_label: inspect(root_view_module(state)),
        live_view: fn attrs, opts ->
          render_live_child(attrs, opts, state, profile_scope, tracking_ref)
        end
      )

    root_snapshot_us = System.monotonic_time(:microsecond) - root_started_at

    focused =
      case Breeze.ChildServer.metadata(state.view_pid) do
        %{focused: focused} -> focused
        _ -> state.focused
      end

    %{
      missing: missing,
      decorations: child_decorations,
      child_timings: child_timings
    } = finish_render_tracking(tracking_ref)
    profile_entries = Breeze.DebugProfiler.snapshot(profile_scope)
    {state, started?} = ensure_children(state, missing)

    if started? do
      render_base(state, attempts)
    else
      cond do
        attempts > 0 and focused != state.focused ->
          render_base(%{state | focused: focused}, attempts - 1)

        true ->
          decorations = decorations ++ child_decorations
          state = %{state | focused: focused}
          prep_started_at = System.monotonic_time(:microsecond)
          {base_output, decorations} = prepare_decorations(box.content, decorations, state)
          prepare_decorations_us = System.monotonic_time(:microsecond) - prep_started_at

          state
          |> Map.put(:base_output, base_output)
          |> Map.put(:decorations, decorations)
          |> Map.put(:focused, focused)
          |> Map.put(:last_render_at, System.monotonic_time(:millisecond))
          |> put_debug_stat(:last_root_snapshot_us, root_snapshot_us)
          |> put_debug_stat(:last_live_children_us, sum_timing_us(child_timings))
          |> put_debug_stat(:last_live_children, normalize_child_timings(child_timings))
          |> put_debug_stat(:last_render_profile, summarize_profile(profile_entries))
          |> put_debug_stat(:last_reconcile_passes, 0)
          |> put_debug_stat(:last_reconcile_changed_ids, nil)
          |> put_debug_stat(:last_prepare_decorations_us, prepare_decorations_us)
          |> put_debug_stat(
            :last_render_base_us,
            System.monotonic_time(:microsecond) - started_at
          )
          |> render_frame()
          |> schedule_animation()
      end
    end
  end

  defp maybe_render_base(%{view_pid: pid} = state) do
    if Process.alive?(pid), do: render_base(state), else: state
  end

  defp maybe_render_after_input(%{pending_ref: ref} = state) when not is_nil(ref), do: state
  defp maybe_render_after_input(state), do: maybe_render_base(state)

  defp render_live_child(attrs, opts, state, profile_scope, tracking_ref) do
    id = fetch_live_attr!(attrs, :id)
    full_id = live_id(Keyword.get(opts, :live_prefix), id)
    preload_only = fetch_live_attr(attrs, :preload_only, false)

    case Map.get(state.children, full_id) do
      nil ->
        track_missing_live_child(tracking_ref, {full_id, attrs})
        if preload_only, do: :preloaded, else: :missing

      %{pid: pid} ->
        if preload_only do
          :preloaded
        else
          local_focused = strip_live_prefix(state.focused, full_id)
          child_started_at = System.monotonic_time(:microsecond)

          {:ok, child_acc, child_box, child_decorations} =
            Breeze.ChildServer.render_snapshot(pid,
              focused: local_focused,
              implicit_state: %{},
              terminal: state.terminal,
              live_prefix: full_id,
              render_tracking_ref: tracking_ref,
              profile_scope: profile_scope,
              profile_label: "#{full_id} #{inspect(state.children[full_id].view)}",
              live_view: fn child_attrs, child_opts ->
                render_live_child(child_attrs, child_opts, state, profile_scope, tracking_ref)
              end
            )

          track_child_timing(tracking_ref, %{
            id: full_id,
            view: state.children[full_id].view,
            us: System.monotonic_time(:microsecond) - child_started_at
          })

          Enum.each(child_decorations, fn decoration ->
            track_render_decoration(tracking_ref, namespace_decoration(decoration, full_id))
          end)

          {:rendered, id, child_acc, child_box}
        end
    end
  end

  defp render_frame(state) do
    started_at = System.monotonic_time(:microsecond)
    {output, decorations} = apply_decorations(state.base_output, state.decorations, state)
    output = strip_private_use_chars(output)
    overlays = terminal_overlays(decorations, state)

    screen_height = state.terminal.size.height
    output_lines = length(String.split(output, "\n"))
    trailing = String.duplicate("\n\e[K", max(screen_height - output_lines, 0))
    output = "\e[K" <> String.replace(output, "\n", "\n\e[K") <> trailing
    composed_at = System.monotonic_time(:microsecond)
    terminal = Termite.Terminal.write(state.terminal, "\e[H" <> output)
    terminal = Breeze.TerminalOverlay.write_overlays(terminal, overlays)
    written_at = System.monotonic_time(:microsecond)

    state
    |> Map.put(:terminal, terminal)
    |> Map.put(:decorations, decorations)
    |> put_debug_stat(:last_frame_compose_us, composed_at - started_at)
    |> put_debug_stat(:last_terminal_write_us, written_at - composed_at)
    |> put_debug_stat(:last_frame_us, System.monotonic_time(:microsecond) - started_at)
    |> put_debug_stat(:last_frame_bytes, byte_size(output))
    |> put_debug_stat(:overlay_count, length(overlays))
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
        String.replace(acc, rendered_fragment(decoration.box, state), current_content, global: false),
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

  defp namespace_decoration(decoration, full_id) do
    Map.update(decoration, :owner_id, full_id, &namespace_live_id(&1, full_id))
  end

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
    decorations
    |> Enum.filter(&decoration_active?(&1, state))
    |> Enum.flat_map(&Map.get(&1, :current_overlays, []))
    |> Enum.reject(&is_nil/1)
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

    Termite.Terminal.write(terminal, "\r")
    System.halt()
  end

  defp ensure_children(state, missing) do
    Enum.reduce(missing, {state, false}, fn {id, attrs}, {state, started?} ->
      if Map.has_key?(state.children, id) do
        {state, started?}
      else
        child = start_child!(attrs, state.terminal)
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

  defp put_debug_stat(state, key, value) do
    state
    |> Map.update(:debug_stats, %{key => value}, &Map.put(&1, key, value))
    |> schedule_debug_push()
  end

  defp push_debug_stats_now(state) do
    stats =
      state.debug_stats
      |> Map.put(:focused, state.focused)
      |> Map.put(:pending?, not is_nil(state.pending_ref))
      |> Map.put(:screen, state.terminal.size)

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

  defp start_child!(attrs, terminal) do
    view = fetch_live_attr!(attrs, :view)
    start_opts = fetch_live_attr(attrs, :start_opts, [])
    persistent = fetch_live_attr(attrs, :persistent, false)
    parent = self()
    child_id = fetch_live_attr!(attrs, :id)
    invalidate = fn -> send(parent, {:child_invalidated, child_id}) end

    {:ok, pid} =
      Breeze.ChildServer.start(
        view: view,
        start_opts: start_opts,
        server: self(),
        terminal: terminal,
        invalidate: invalidate
      )

    ref = Process.monitor(pid)
    %{pid: pid, ref: ref, view: view, persistent: persistent}
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
        decorations: Enum.reverse(tracking.decorations),
        child_timings: Enum.reverse(tracking.child_timings)
      }
    end)
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

  defp enqueue_input(state, decoded) do
    update_in(state.queued_input, &(&1 ++ [decoded]))
  end

  defp schedule_input_flush(%{input_flush_scheduled?: true} = state), do: state

  defp schedule_input_flush(state) do
    send(self(), @flush_input_batch)
    %{state | input_flush_scheduled?: true}
  end
  defp sum_timing_us(child_timings) do
    Enum.reduce(child_timings, 0, fn %{us: us}, acc -> acc + us end)
  end

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
    case Breeze.ChildServer.metadata(state.view_pid) do
      %{view: view} -> view
      _ -> nil
    end
  end

  defp dispatch_input_hierarchy(state, key) do
    child_reply =
      state
      |> focused_child_chain()
      |> Enum.reduce_while(nil, fn {child_id, %{pid: pid}}, _acc ->
        reply = Breeze.ChildServer.dispatch_input(pid, key) |> namespace_child_reply(child_id)

        case reply do
          {:noreply, _focused, true} -> {:halt, reply}
          {:stop, _focused, _consumed} -> {:halt, reply}
          _ -> {:cont, nil}
        end
      end)

    child_reply || Breeze.ChildServer.dispatch_input(state.view_pid, key)
  end

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
