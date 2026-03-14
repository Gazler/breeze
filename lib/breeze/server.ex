defmodule Breeze.Term do
  @moduledoc false

  defstruct [
    :view,
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
    decorations: [],
    children: %{},
    animation_timer: nil,
    next_tick_at: nil,
    global_keybindings: [],
    hide_cursor?: true,
    busy_delay_ms: 120,
    frame_delay_ms: 80
  ]

  @type option ::
          {:view, module()}
          | {:start_opts, keyword()}
          | {:hide_cursor, boolean()}
          | {:global_keybindings, list()}
          | {:frame_delay_ms, pos_integer()}

  @doc """
  Start the Breeze application.

  Valid options are:

    * `:view` - the view to run. This is required
    * `:hide_cursor` - hide the cursor on start. Defaults to `false`
    * `:global_keybindings` - app-wide keybindings checked before focused event handling

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc false
  def dispatch_global_keybindings(event, state) do
    case Enum.find(state.global_keybindings, fn {key, _fun} -> key == event["key"] end) do
      nil ->
        :continue

      {_key, fun} when is_function(fun, 2) ->
        case fun.(event, state) do
          :continue -> :continue
          {:stop, state} -> {:stop, state}
          {:noreply, state} -> {:noreply, state}
        end
    end
  end

  @impl true
  def init(opts) do
    view = Keyword.fetch!(opts, :view)
    start_opts = Keyword.get(opts, :start_opts, [])
    hide_cursor? = Keyword.get(opts, :hide_cursor, true)
    frame_delay_ms = Keyword.get(opts, :frame_delay_ms, 80)

    terminal = Termite.Terminal.start()
    terminal = if hide_cursor?, do: Termite.Screen.hide_cursor(terminal), else: terminal
    terminal = Termite.Screen.clear_screen(terminal)

    session = self()

    {:ok, view_pid} =
      Breeze.ChildServer.start(
        view: view,
        start_opts: start_opts,
        terminal: terminal,
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
      reader: terminal.reader,
      view_pid: view_pid,
      focused: focused,
      global_keybindings: Keyword.get(opts, :global_keybindings, []),
      hide_cursor?: hide_cursor?,
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
  def handle_info({reader, {:data, data}}, %{reader: reader} = state) do
    {:key, key} = decode_input(data)

    cond do
      stop_global_key?(key, state) ->
        stop(state)

      sync_input?(state, key) ->
        case process_input_batch(reader, data, state) do
          {:stop, state} -> stop(state)
          {:noreply, state} -> {:noreply, maybe_render_base(state)}
        end

      true ->
        {:noreply, start_async_input(key, state)}
    end
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

  def handle_info(:animation_tick, %{decorations: []} = state) do
    {:noreply, %{state | animation_timer: nil, next_tick_at: nil}}
  end

  def handle_info(:animation_tick, state) do
    state =
      state
      |> Map.put(:animation_timer, nil)
      |> Map.put(:next_tick_at, nil)
      |> advance_decorations()
      |> render_frame()
      |> schedule_animation()

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
        children =
          state.children
          |> Enum.reject(fn {_id, child} -> child.ref == ref end)
          |> Map.new()

        {:noreply, %{state | children: children}}

      _ ->
        {:noreply, state}
    end
  end

  defp process_input_batch(reader, data, state) do
    case handle_key(data, state) do
      {:stop, state} ->
        {:stop, state}

      {:noreply, state} ->
        drain_input_batch(reader, state)
    end
  end

  defp drain_input_batch(reader, state) do
    receive do
      {^reader, {:data, data}} ->
        process_input_batch(reader, data, state)
    after
      0 -> {:noreply, state}
    end
  end

  defp handle_key(raw_key, state) do
    {:key, key} = decode_input(raw_key)

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
    event = %{"key" => key}

    Enum.any?(state.global_keybindings, fn
      {^key, fun} when is_function(fun, 2) ->
        match?({:stop, _}, fun.(event, state))

      _ ->
        false
    end)
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

  defp start_async_input(_key, %{pending_ref: ref} = state) when not is_nil(ref), do: state

  defp start_async_input(key, state) do
    ref = make_ref()
    session = self()

    Task.start(fn ->
      reply = dispatch_input_hierarchy(state, key)
      send(session, {:event_reply, ref, reply})
    end)

    state
    |> Map.put(:pending_ref, ref)
    |> Map.put(:pending_started_at, System.monotonic_time(:millisecond))
    |> Map.put(:last_interaction_at, System.monotonic_time(:millisecond))
    |> render_frame()
    |> schedule_animation()
  end

  defp render_base(state, attempts \\ 1)

  defp render_base(state, attempts) do
    token = make_ref()
    collector = self()

    {:ok, _acc, box, decorations} =
      Breeze.ChildServer.render_snapshot(state.view_pid,
        implicit_state: %{},
        terminal: state.terminal,
        live_view: fn attrs, opts -> render_live_child(attrs, opts, state, collector, token) end
      )

    focused =
      case Breeze.ChildServer.metadata(state.view_pid) do
        %{focused: focused} -> focused
        _ -> state.focused
      end

    %{missing: missing, decorations: child_decorations} = collect_render_tracking(token)
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
          {base_output, decorations} = prepare_decorations(box.content, decorations, state)

          state
          |> Map.put(:base_output, base_output)
          |> Map.put(:decorations, decorations)
          |> Map.put(:focused, focused)
          |> Map.put(:last_render_at, System.monotonic_time(:millisecond))
          |> render_frame()
          |> schedule_animation()
      end
    end
  end

  defp maybe_render_base(%{view_pid: pid} = state) do
    if Process.alive?(pid), do: render_base(state), else: state
  end

  defp render_live_child(attrs, opts, state, collector, token) do
    id = fetch_live_attr!(attrs, :id)
    full_id = live_id(Keyword.get(opts, :live_prefix), id)
    preload_only = fetch_live_attr(attrs, :preload_only, false)

    case Map.get(state.children, full_id) do
      nil ->
        send(collector, {:breeze_live_track, token, :missing, {full_id, attrs}})
        if preload_only, do: :preloaded, else: :missing

      %{pid: pid} ->
        if preload_only do
          :preloaded
        else
          local_focused = strip_live_prefix(state.focused, full_id)

          {:ok, child_acc, child_box, child_decorations} =
            Breeze.ChildServer.render_snapshot(pid,
              focused: local_focused,
              implicit_state: %{},
              terminal: state.terminal,
              live_prefix: full_id,
              live_view: fn child_attrs, child_opts ->
                render_live_child(child_attrs, child_opts, state, collector, token)
              end
            )

          Enum.each(child_decorations, fn decoration ->
            send(
              collector,
              {:breeze_live_track, token, :decoration, namespace_decoration(decoration, full_id)}
            )
          end)

          {:rendered, id, child_acc, child_box}
        end
    end
  end

  defp render_frame(state) do
    {output, decorations} = apply_decorations(state.base_output, state.decorations, state)
    output = strip_private_use_chars(output)
    overlays = terminal_overlays(decorations, state)

    screen_height = state.terminal.size.height
    output_lines = length(String.split(output, "\n"))
    trailing = String.duplicate("\n\e[K", max(screen_height - output_lines, 0))
    output = "\e[K" <> String.replace(output, "\n", "\n\e[K") <> trailing
    terminal = Termite.Terminal.write(state.terminal, "\e[H" <> output)
    terminal = Breeze.TerminalOverlay.write_overlays(terminal, overlays)
    %{state | terminal: terminal, decorations: decorations}
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

      # TODO: Replace async decoration content by box coordinates instead of substring matching.
      {
        String.replace(acc, decoration.box.content, current_content, global: false),
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

        # TODO: Replace async decoration content by box coordinates instead of substring matching.
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

    {animated_box, animated_box.content, Map.get(animate_opts, :overlays, [])}
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
      |> Termite.Screen.clear_screen()
      |> Termite.Screen.show_cursor()
      |> Termite.Screen.exit_alt_screen()

    Termite.Terminal.write(terminal, "\r")
    System.halt()
  end

  defp decode_input(raw_key), do: {:key, Breeze.KeyDecoder.decode(raw_key)}

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
        terminal: terminal,
        invalidate: invalidate
      )

    ref = Process.monitor(pid)
    %{pid: pid, ref: ref, view: view, persistent: persistent}
  end

  defp collect_render_tracking(token) do
    receive do
      {:breeze_live_track, ^token, :missing, item} ->
        acc = collect_render_tracking(token)
        %{acc | missing: [item | acc.missing]}

      {:breeze_live_track, ^token, :decoration, decoration} ->
        acc = collect_render_tracking(token)
        %{acc | decorations: [decoration | acc.decorations]}
    after
      0 -> %{missing: [], decorations: []}
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
