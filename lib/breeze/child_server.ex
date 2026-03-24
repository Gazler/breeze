defmodule Breeze.ChildServer do
  @moduledoc false

  use GenServer

  def start(opts) do
    GenServer.start(__MODULE__, opts)
  end

  def metadata(pid) do
    GenServer.call(pid, :metadata)
  end

  def layout_snapshot(pid) do
    GenServer.call(pid, :layout_snapshot)
  end

  def render(pid, opts) do
    GenServer.call(pid, {:render, opts})
  end

  def render_snapshot(pid, opts) do
    GenServer.call(pid, {:render_snapshot, opts})
  end

  def dispatch_input(pid, input) do
    GenServer.call(pid, {:input, input})
  end

  def set_focus(pid, focused) do
    GenServer.call(pid, {:set_focus, focused})
  end

  def dispatch_event(pid, change, event) do
    GenServer.call(pid, {:event, change, event})
  end

  def update_assigns(pid, assigns) do
    GenServer.call(pid, {:update_assigns, assigns})
  end

  def dispatch_info(pid, message, terminal \\ nil) do
    GenServer.call(pid, {:info, message, terminal})
  end

  def put_global_keybindings(pid, keybindings) do
    GenServer.call(pid, {:put_global_keybindings, keybindings})
  end

  @impl true
  def init(opts) do
    view = Keyword.fetch!(opts, :view)
    terminal = Keyword.get(opts, :terminal)
    theme_input = Keyword.get(opts, :theme_source, Keyword.get(opts, :theme))
    theme = Breeze.Theme.new(theme_input, terminal: terminal)

    apply_theme_defaults? =
      Keyword.get(
        opts,
        :apply_theme_defaults?,
        Breeze.Theme.defaults_enabled?(theme_input)
      )

    start_opts = Keyword.get(opts, :start_opts, [])
    invalidate = Keyword.get(opts, :invalidate)
    global_keybindings = Keyword.get(opts, :global_keybindings, [])

    external_assigns =
      opts
      |> Keyword.get(:assigns, %{})
      |> Map.new()

    initial_assigns =
      external_assigns
      |> Map.put(:__invalidate__, invalidate)

    term = %Breeze.Term{
      view: view,
      server: Keyword.get(opts, :server),
      terminal: terminal,
      theme: theme,
      theme_source: theme_input,
      apply_theme_defaults?: apply_theme_defaults?,
      global_keybindings: global_keybindings,
      assigns: initial_assigns,
      external_assigns: external_assigns
    }

    term =
      if Code.ensure_loaded?(view) and function_exported?(view, :mount, 2) do
        {:ok, mounted_term} = view.mount(start_opts, term)
        mounted_term
      else
        term
      end

    maybe_probe_system_theme(term.theme_source, term.terminal, term.server)
    term = sync_theme_assigns(term)
    {:ok, term}
  end

  @impl true
  def handle_call(:metadata, _from, term) do
    {:reply,
     %{
       focused: term.focused,
       view: term.view,
       theme: term.theme,
       apply_theme_defaults?: term.apply_theme_defaults?,
       focused_implicit_id: focused_implicit_id(term, term.focused),
       focus_meta: term.focus_meta,
       implicit_state: term.implicit_state,
       implicit_meta: term.implicit_meta
     }, term}
  end

  def handle_call(:layout_snapshot, _from, term) do
    {:reply, %{elements: term.elements, mouse_targets: term.mouse_targets}, term}
  end

  def handle_call({:render, opts}, _from, term) do
    {term, acc, box, _decorations} = render_term(term, opts)
    {:reply, {:ok, acc, box}, term}
  end

  def handle_call({:render_snapshot, opts}, _from, term) do
    {term, acc, box, decorations} = render_term(term, opts)
    {:reply, {:ok, acc, box, decorations}, term}
  end

  def handle_call({:event, change, event}, _from, term) do
    touched_term = touch_interaction(term)
    reply_from_input_result(handle_event(change, event, touched_term), touched_term)
  end

  def handle_call({:input, input}, _from, term) do
    touched_term = touch_interaction(term)
    reply_from_input_result(process_input(input, touched_term), touched_term)
  end

  def handle_call({:set_focus, focused}, _from, term) do
    next_term =
      term
      |> Map.put(:focused, focused)
      |> Map.put(:allow_unfocused?, is_nil(focused))
      |> then(&apply_focus_transitions(term, &1))

    {:reply, {:noreply, next_term.focused, next_term != term}, next_term}
  end

  def handle_call({:info, message, terminal}, _from, term) do
    term = maybe_put_terminal(term, terminal)
    reply_from_result(term.view.handle_info(message, term), term)
  end

  def handle_call({:put_global_keybindings, keybindings}, _from, term) do
    {:reply, :ok, %{term | global_keybindings: keybindings}}
  end

  def handle_call({:update_assigns, assigns}, _from, term) do
    next_term =
      term
      |> apply_external_assigns(Map.new(assigns))
      |> sync_theme_assigns()

    notify_invalidate(next_term)
    {:reply, :ok, next_term}
  end

  @impl true
  def handle_info({:breeze_theme_palette, _key, _status}, %{theme_source: :system} = term) do
    theme = Breeze.Theme.new(:system, terminal: term.terminal)
    next_term = %{term | theme: theme} |> sync_theme_assigns()
    notify_invalidate(next_term)
    {:noreply, next_term}
  end

  def handle_info({:child_invalidated, _child_id}, term) do
    notify_invalidate(term)
    {:noreply, term}
  end

  def handle_info(message, term) do
    term = maybe_put_terminal(term, term.terminal)

    case term.view.handle_info(message, term) do
      {:noreply, next_term} ->
        notify_invalidate(next_term)
        {:noreply, next_term}

      {:noreply, next_term, opts} ->
        maybe_notify_invalidate(next_term, opts)
        {:noreply, next_term}

      {:stop, next_term} ->
        notify_invalidate(next_term)
        {:stop, :normal, next_term}

      {:stop, next_term, opts} ->
        maybe_notify_invalidate(next_term, opts)
        {:stop, :normal, next_term}
    end
  end

  defp reply_from_result({:noreply, next_term}, term) do
    next_term =
      term
      |> apply_focus_transitions(next_term)

    maybe_probe_system_theme(next_term.theme_source, next_term.terminal, next_term.server)
    next_term = sync_theme_assigns(next_term)
    notify_invalidate(next_term)
    {:reply, {:noreply, next_term.focused}, next_term}
  end

  defp reply_from_result({:noreply, next_term, opts}, term) do
    next_term =
      term
      |> apply_focus_transitions(next_term)

    maybe_probe_system_theme(next_term.theme_source, next_term.terminal, next_term.server)
    next_term = sync_theme_assigns(next_term)
    maybe_notify_invalidate(next_term, opts)
    {:reply, {:noreply, next_term.focused}, next_term}
  end

  defp reply_from_result({:stop, next_term}, term) do
    next_term =
      term
      |> apply_focus_transitions(next_term)
      |> sync_theme_assigns()

    notify_invalidate(next_term)
    {:stop, :normal, {:stop, next_term.focused}, next_term}
  end

  defp reply_from_result({:stop, next_term, opts}, term) do
    next_term =
      term
      |> apply_focus_transitions(next_term)
      |> sync_theme_assigns()

    maybe_notify_invalidate(next_term, opts)
    {:stop, :normal, {:stop, next_term.focused}, next_term}
  end

  defp maybe_put_terminal(term, nil), do: term
  defp maybe_put_terminal(term, terminal), do: %{term | terminal: terminal}

  defp maybe_probe_system_theme(:system, terminal, server) do
    if is_pid(server), do: send(server, {:ensure_runtime_palette, :system})
    Breeze.Theme.ensure_runtime_palette_async(terminal, self())
  end

  defp maybe_probe_system_theme(_theme_input, _terminal, _server), do: :ok

  defp sync_theme_assigns(%{theme: theme, assigns: assigns} = term) when is_map(assigns) do
    assigns =
      assigns
      |> maybe_put_theme_assign(:theme_status, Breeze.Theme.probe_status(theme) || :ready)
      |> maybe_put_theme_assign(:actual_theme_mode, theme.mode)

    %{term | assigns: assigns}
  end

  defp sync_theme_assigns(term), do: term

  defp apply_external_assigns(
         %{assigns: assigns, external_assigns: external_assigns} = term,
         next_external
       )
       when is_map(assigns) and is_map(external_assigns) do
    preserved = Map.drop(assigns, Map.keys(external_assigns))
    %{term | assigns: Map.merge(preserved, next_external), external_assigns: next_external}
  end

  defp apply_external_assigns(term, next_external), do: %{term | external_assigns: next_external}

  defp maybe_put_theme_assign(assigns, key, value) do
    if Map.has_key?(assigns, key), do: Map.put(assigns, key, value), else: assigns
  end

  defp render_term(term, opts) do
    explicit_focus? = Keyword.has_key?(opts, :focused)
    term = maybe_put_terminal(term, Keyword.get(opts, :terminal))
    term = prune_dead_children(term)

    theme =
      Breeze.Theme.new(term.theme_source || term.theme || Keyword.get(opts, :theme),
        terminal: term.terminal
      )

    term = %{term | theme: theme}
    term = %{term | focused: Keyword.get(opts, :focused, term.focused)}
    implicit_state = Keyword.get(opts, :implicit_state, %{}) |> Map.merge(term.implicit_state)

    opts =
      opts
      |> Keyword.put(:implicit_state, implicit_state)
      |> Keyword.put(:previous_elements, term.elements)
      |> Keyword.put(:theme, theme)
      |> Keyword.put(:theme_source, term.theme_source || term.theme)
      |> Keyword.put(:apply_theme_defaults, term.apply_theme_defaults?)

    profile_scope = Keyword.get(opts, :profile_scope)
    profile_label = profile_label(term, opts)

    final_opts =
      opts
      |> Keyword.put(:focused, term.focused)
      |> Keyword.put(:implicit_state, implicit_state)
      |> Keyword.put(:implicit_meta, term.implicit_meta)
      |> Keyword.put(:last_render_at, term.last_render_at)
      |> Keyword.put(:last_interaction_at, term.last_interaction_at)
      |> Keyword.put(:animation_now, System.monotonic_time(:millisecond))

    {term, final_opts} =
      if Keyword.has_key?(opts, :live_view) do
        {term, final_opts}
      else
        preload_and_attach_live_view(term, final_opts)
      end

    initial_implicit_meta = term.implicit_meta

    {term, acc, box} =
      render_pass(term, final_opts, profile_scope, profile_label, explicit_focus?)

    {term, acc, box} =
      if term.implicit_state != implicit_state or term.implicit_meta != initial_implicit_meta do
        rerender_opts =
          final_opts
          |> Keyword.put(:focused, term.focused)
          |> Keyword.put(:implicit_state, term.implicit_state)
          |> Keyword.put(:implicit_meta, term.implicit_meta)
          |> Keyword.put(:previous_elements, term.elements)

        render_pass(term, rerender_opts, profile_scope, profile_label, explicit_focus?)
      else
        {term, acc, box}
      end

    decorations =
      profile(profile_scope, profile_label, :decorations_us, fn ->
        extract_async_decorations(term)
      end)

    {term, acc, box, decorations}
  end

  defp render_pass(term, opts, profile_scope, profile_label, explicit_focus?) do
    {acc, box} =
      profile(profile_scope, profile_label, :child_render_us, fn ->
        Breeze.Renderer.render(term.view, term.assigns, opts)
      end)

    term =
      profile(profile_scope, profile_label, :render_state_us, fn ->
        Breeze.RenderState.build(term, acc)
      end)

    focus_meta = Breeze.Focus.build_meta(acc.elements, term.implicit_state)

    focus_memory =
      Breeze.Focus.remember_focus(
        term.focus_memory,
        term.focused,
        term.focus_meta
      )

    focused =
      if explicit_focus? do
        term.focused
      else
        trapped_scope = Breeze.Focus.trapped_scope?(acc.focusables, focus_meta)

        if term.allow_unfocused? and is_nil(term.focused) and not trapped_scope do
          nil
        else
          Breeze.Focus.normalize_focus(
            term.focused,
            acc.focusables,
            focus_meta,
            focus_memory
          )
        end
      end

    term = %{
      term
      | focus_meta: focus_meta,
        focus_memory: focus_memory,
        focused: focused,
        allow_unfocused?: term.allow_unfocused? and is_nil(focused)
    }

    {term, acc, box}
  end

  defp normalize_result({:noreply, next_term}, _term), do: {:noreply, next_term}
  defp normalize_result({:stop, next_term}, _term), do: {:stop, next_term}

  defp process_input("\t", term) do
    focusables = Breeze.Focus.active_focusables(term.focusables, term.focus_meta)
    index = Enum.find_index(focusables, &(&1 == term.focused))
    trapped_scope = Breeze.Focus.trapped_scope?(term.focusables, term.focus_meta)

    focused =
      cond do
        focusables == [] -> nil
        trapped_scope && is_integer(index) -> Enum.at(focusables, index + 1) || hd(focusables)
        is_integer(index) -> Enum.at(focusables, index + 1)
        true -> hd(focusables)
      end

    {:noreply, %{term | focused: focused, allow_unfocused?: is_nil(focused)}}
  end

  defp process_input("ShiftTab", term) do
    focusables = Breeze.Focus.active_focusables(term.focusables, term.focus_meta)
    index = Enum.find_index(focusables, &(&1 == term.focused))
    trapped_scope = Breeze.Focus.trapped_scope?(term.focusables, term.focus_meta)

    focused =
      cond do
        focusables == [] -> nil
        trapped_scope && index == 0 -> List.last(focusables)
        trapped_scope && is_integer(index) -> Enum.at(focusables, index - 1)
        index == 0 -> nil
        index == nil -> List.last(focusables)
        true -> Enum.at(focusables, index - 1)
      end

    {:noreply, %{term | focused: focused, allow_unfocused?: is_nil(focused)}}
  end

  defp process_input(%{"mouse" => mouse} = event, term) do
    case mouse_target(term, mouse) do
      nil ->
        normalize_result(term.view.handle_event(:ignore_me, event, term), term)

      target ->
        term =
          if focus_mouse_target?(target, mouse, term) do
            %{term | focused: target}
          else
            term
          end

        event =
          event
          |> Map.put("target", target)
          |> Map.put("row", mouse_row(term, target, mouse))
          |> Map.put("col", mouse_col(term, target, mouse))

        handle_event(:ignore_me, event, term, target)
    end
  end

  defp process_input(key, term) do
    event = normalize_key_event(key)

    case Breeze.GlobalKeybindings.dispatch(event, term) do
      {:stop, term} ->
        {:stop, term}

      {:noreply, term} ->
        {:noreply, term}

      :continue ->
        case dispatch_input_hierarchy(term, key) do
          nil ->
            handle_event(:ignore_me, event, term)

          reply ->
            reply
        end
    end
  end

  defp handle_event(change, event, term, target_id \\ nil) do
    target_id = target_id || term.focused

    {view_state, implicit_consumed, term} =
      Breeze.RenderState.dispatch_implicit_event(
        term,
        target_id,
        event,
        &handle_implicit_change/4
      )

    cond do
      view_state == :stop ->
        {:stop, term}

      implicit_consumed ->
        {:noreply, term}

      true ->
        normalize_result(term.view.handle_event(change, event, term), term)
    end
  end

  defp handle_implicit_change(term, _id, change, event) do
    normalize_result(term.view.handle_event(change, event, term), term)
  end

  defp dispatch_input_hierarchy(term, key) do
    term
    |> focused_child_chain()
    |> Enum.reduce_while(nil, fn {child_id, %{pid: pid}}, _acc ->
      local_focused = strip_live_prefix(term.focused, child_id)
      if local_focused, do: Breeze.ChildServer.set_focus(pid, local_focused)

      reply = Breeze.ChildServer.dispatch_input(pid, key) |> namespace_child_reply(child_id)

      case reply do
        {:noreply, _focused, true} -> {:halt, reply}
        {:stop, _focused, _consumed} -> {:halt, reply}
        _ -> {:cont, nil}
      end
    end)
  end

  defp normalize_key_event(%{"key" => _} = event), do: event
  defp normalize_key_event(key), do: %{"key" => key}

  defp preload_and_attach_live_view(term, opts) do
    collector_key = {__MODULE__, :live_children, make_ref()}
    Process.put(collector_key, [])

    preload_opts =
      Keyword.put(opts, :live_view, fn attrs, _child_opts ->
        id = fetch_live_attr!(attrs, :id)
        Process.put(collector_key, [{id, attrs} | Process.get(collector_key, [])])
        :preloaded
      end)

    _ = Breeze.Renderer.render(term.view, term.assigns, preload_opts)

    discovered =
      collector_key
      |> Process.get([])
      |> Enum.reverse()
      |> Enum.uniq_by(&elem(&1, 0))

    Process.delete(collector_key)

    term = ensure_children(term, discovered)

    live_view = fn attrs, child_opts ->
      render_live_child(attrs, child_opts, term)
    end

    {term, Keyword.put(opts, :live_view, live_view)}
  end

  defp ensure_children(term, live_children) do
    Enum.reduce(live_children, term, fn {id, attrs}, acc ->
      view = fetch_live_attr!(attrs, :view)
      start_opts = fetch_live_attr(attrs, :start_opts, [])
      assigns = fetch_live_attr(attrs, :assigns, %{}) |> Map.new()

      case Map.get(acc.children, id) do
        %{pid: pid, view: ^view, start_opts: ^start_opts} when is_pid(pid) ->
          cond do
            not Process.alive?(pid) ->
              put_in(acc.children[id], start_child!(id, attrs, acc))

            true ->
              if Map.get(acc.children[id], :assigns, %{}) == assigns do
                acc
              else
                :ok = update_assigns(pid, assigns)
                put_in(acc.children[id].assigns, assigns)
              end
          end

        %{pid: pid, ref: ref} ->
          if is_pid(pid) and Process.alive?(pid), do: Process.exit(pid, :normal)
          if is_reference(ref), do: Process.demonitor(ref, [:flush])
          put_in(acc.children[id], start_child!(id, attrs, acc))

        nil ->
          put_in(acc.children[id], start_child!(id, attrs, acc))
      end
    end)
  end

  defp start_child!(id, attrs, term) do
    view = fetch_live_attr!(attrs, :view)
    start_opts = fetch_live_attr(attrs, :start_opts, [])
    assigns = fetch_live_attr(attrs, :assigns, %{}) |> Map.new()
    parent = self()
    invalidate = fn -> send(parent, {:child_invalidated, id}) end

    {:ok, pid} =
      Breeze.ChildServer.start(
        view: view,
        start_opts: start_opts,
        assigns: assigns,
        server: term.server,
        terminal: term.terminal,
        theme: term.theme,
        theme_source: term.theme_source,
        global_keybindings: term.global_keybindings,
        apply_theme_defaults?: term.apply_theme_defaults?,
        invalidate: invalidate
      )

    %{pid: pid, ref: Process.monitor(pid), view: view, start_opts: start_opts, assigns: assigns}
  end

  defp render_live_child(attrs, child_opts, term) do
    id = fetch_live_attr!(attrs, :id)
    terminal = Keyword.get(child_opts, :live_terminal, term.terminal)
    full_prefix = live_id(Keyword.get(child_opts, :live_prefix), id)
    viewport = Keyword.get(child_opts, :live_viewport)

    case Map.get(term.children, id) do
      %{pid: pid} when is_pid(pid) ->
        if Process.alive?(pid) do
          case Breeze.ChildServer.render_snapshot(pid,
                 focused: strip_live_prefix(term.focused, id),
                 implicit_state: %{},
                 terminal: terminal,
                 theme: term.theme,
                 theme_source: term.theme_source || term.theme,
                 live_prefix: full_prefix
               ) do
            {:ok, child_acc, child_box, _decorations} ->
              layout_snapshot = Breeze.ChildServer.layout_snapshot(pid)

              {:rendered, id, child_acc, child_box,
               translate_live_dimensions(layout_snapshot.elements, viewport, full_prefix)}

            _ ->
              :preloaded
          end
        else
          :preloaded
        end

      _ ->
        :preloaded
    end
  end

  defp prune_dead_children(term) do
    alive_children =
      term.children
      |> Enum.filter(fn {_id, child} -> is_pid(child.pid) and Process.alive?(child.pid) end)
      |> Map.new()

    %{term | children: alive_children}
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

  defp translate_live_dimensions(elements, %{left: left, top: top} = viewport, prefix)
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

    Map.put(translated_elements, prefix, live_root_dimensions(translated_elements, viewport))
  end

  defp translate_live_dimensions(_elements, _viewport, _prefix), do: %{}

  defp live_root_dimensions(translated_elements, viewport) do
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
    end
  end

  defp fetch_live_attr!(attrs, key) do
    Map.get(attrs, key) || Map.fetch!(attrs, Atom.to_string(key))
  end

  defp fetch_live_attr(attrs, key, default) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key), default)
  end

  defp extract_async_decorations(term) do
    Enum.reduce(term.implicit_state, [], fn
      {id, {mod, implicit}}, acc ->
        every_ms = get_in(term.implicit_meta, [id, :rerender_every])
        box = Map.get(term.rendered_boxes, id)
        layout = Map.get(term.elements, id)

        if is_integer(every_ms) and every_ms > 0 and match?(%BackBreeze.Box{}, box) and
             function_exported?(mod, :animate, 5) do
          [
            %{
              id: id,
              owner_id: id,
              mod: mod,
              state: implicit,
              box: box,
              layout: layout,
              flags: focus_flags(term, id),
              every_ms: every_ms,
              active_when_pending: get_in(term.implicit_meta, [id, :active_when_pending]) == true,
              active_when_focused: get_in(term.implicit_meta, [id, :active_when_focused]) == true
            }
            | acc
          ]
        else
          acc
        end

      _, acc ->
        acc
    end)
    |> Enum.reverse()
  end

  defp focus_flags(term, id) do
    focused = term.focused == id

    if focused, do: [focused: true], else: []
  end

  defp touch_interaction(term) do
    %{term | last_interaction_at: System.monotonic_time(:millisecond)}
  end

  defp reply_from_input_result({:noreply, next_term}, term) do
    next_term = apply_focus_transitions(term, next_term)
    notify_invalidate(next_term)
    {:reply, {:noreply, next_term.focused, next_term != term}, next_term}
  end

  defp reply_from_input_result({:noreply, focused, consumed}, term) do
    next_term = %{term | focused: focused, allow_unfocused?: is_nil(focused)}
    notify_invalidate(next_term)
    {:reply, {:noreply, next_term.focused, consumed}, next_term}
  end

  defp reply_from_input_result({:stop, next_term}, term) do
    next_term = apply_focus_transitions(term, next_term)
    notify_invalidate(next_term)
    {:stop, :normal, {:stop, next_term.focused, true}, next_term}
  end

  defp reply_from_input_result({:stop, focused, consumed}, term) do
    next_term = %{term | focused: focused, allow_unfocused?: is_nil(focused)}
    notify_invalidate(next_term)
    {:stop, :normal, {:stop, next_term.focused, consumed}, next_term}
  end

  defp apply_focus_transitions(prev_term, next_term) do
    prev_implicit_id = focused_implicit_id(prev_term, prev_term.focused)
    next_implicit_id = focused_implicit_id(next_term, next_term.focused)

    next_term =
      if prev_implicit_id && prev_implicit_id != next_implicit_id do
        case Map.get(next_term.implicit_state, prev_implicit_id) do
          {mod, state} ->
            if function_exported?(mod, :blur, 1) do
              Breeze.RenderState.put_implicit_state(
                next_term,
                prev_implicit_id,
                mod,
                mod.blur(state)
              )
            else
              next_term
            end

          _ ->
            next_term
        end
      else
        next_term
      end

    next_term
  end

  defp focused_implicit_id(_term, nil), do: nil

  defp focused_implicit_id(term, focused) do
    cond do
      Map.has_key?(term.implicit_state, focused) ->
        focused

      true ->
        get_in(term.focus_meta, [focused, :implicit_owner])
    end
  end

  defp notify_invalidate(term) do
    case Map.get(term.assigns, :__invalidate__) do
      fun when is_function(fun, 0) -> fun.()
      _ -> :ok
    end
  end

  defp maybe_notify_invalidate(term, opts) do
    if Keyword.get(opts, :invalidate, true) do
      notify_invalidate(term)
    else
      :ok
    end
  end

  defp mouse_target(term, %{x: x, y: y}) do
    x = x - 1
    y = y - 1

    term.mouse_targets
    |> Enum.filter(fn {_id, bounds} ->
      is_integer(bounds[:left]) and is_integer(bounds[:right]) and is_integer(bounds[:top]) and
        is_integer(bounds[:bottom]) and x >= bounds.left and x <= bounds.right and
        y >= bounds.top and y <= bounds.bottom
    end)
    |> Enum.sort_by(fn {_id, bounds} ->
      area = (bounds.right - bounds.left + 1) * (bounds.bottom - bounds.top + 1)
      {area, bounds.top, bounds.left}
    end)
    |> List.first()
    |> case do
      {id, _bounds} -> id
      nil -> nil
    end
  end

  defp mouse_row(term, target, %{y: y}) do
    bounds = Map.fetch!(term.mouse_targets, target)
    box = Map.get(term.rendered_boxes, target)
    top_inset = border_inset(box, :top)
    max(y - 1 - bounds.top - top_inset, 0)
  end

  defp mouse_col(term, target, %{x: x}) do
    bounds = Map.fetch!(term.mouse_targets, target)
    box = Map.get(term.rendered_boxes, target)
    left_inset = border_inset(box, :left)
    max(x - 1 - bounds.left - left_inset, 0)
  end

  defp border_inset(%BackBreeze.Box{style: %{border: border}}, side) do
    if Map.get(border, side), do: 1, else: 0
  end

  defp border_inset(_, _side), do: 0

  defp focus_mouse_target?(target, %{button: :left, action: :press}, term) do
    target in term.focusables
  end

  defp focus_mouse_target?(_target, _mouse, _term), do: false

  defp profile_label(term, opts) do
    case Keyword.get(opts, :live_prefix) do
      nil -> inspect(term.view)
      prefix -> prefix <> " " <> inspect(term.view)
    end
  end

  defp profile(nil, _label, _metric, fun), do: fun.()

  defp profile(scope, label, metric, fun) do
    :telemetry.span(
      [:breeze, :render],
      %{scope: scope, label: label, metric: metric},
      fn ->
        result = fun.()
        {result, %{scope: scope, label: label, metric: metric}}
      end
    )
  end
end
