defmodule Breeze.ChildServer do
  @moduledoc false

  use GenServer

  def start(opts) do
    GenServer.start(__MODULE__, opts)
  end

  def metadata(pid) do
    GenServer.call(pid, :metadata)
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

    term = %Breeze.Term{
      view: view,
      server: Keyword.get(opts, :server),
      terminal: terminal,
      theme: theme,
      theme_source: theme_input,
      apply_theme_defaults?: apply_theme_defaults?,
      global_keybindings: global_keybindings,
      assigns: %{__invalidate__: invalidate}
    }

    {:ok, term} = view.mount(start_opts, term)
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

  @impl true
  def handle_info({:breeze_theme_palette, _key, _status}, %{theme_source: :system} = term) do
    theme = Breeze.Theme.new(:system, terminal: term.terminal)
    next_term = %{term | theme: theme} |> sync_theme_assigns()
    notify_invalidate(next_term)
    {:noreply, next_term}
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

  defp maybe_put_theme_assign(assigns, key, value) do
    if Map.has_key?(assigns, key), do: Map.put(assigns, key, value), else: assigns
  end

  defp render_term(term, opts) do
    explicit_focus? = Keyword.has_key?(opts, :focused)
    term = maybe_put_terminal(term, Keyword.get(opts, :terminal))

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
    event = %{"key" => key}

    case Breeze.GlobalKeybindings.dispatch(event, term) do
      {:stop, term} ->
        {:stop, term}

      {:noreply, term} ->
        {:noreply, term}

      :continue ->
        handle_event(:ignore_me, event, term)
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

  defp reply_from_input_result({:stop, next_term}, term) do
    next_term = apply_focus_transitions(term, next_term)
    notify_invalidate(next_term)
    {:stop, :normal, {:stop, next_term.focused, true}, next_term}
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
