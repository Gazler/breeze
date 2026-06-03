defmodule Breeze.ChildServer do
  @moduledoc false

  use GenServer

  def start(opts) do
    GenServer.start(__MODULE__, opts)
  end

  def metadata(pid, opts \\ []) do
    GenServer.call(pid, {:metadata, opts})
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

  def dispatch_input(pid, input, opts \\ []) do
    GenServer.call(pid, {:input, input, opts})
  end

  def dispatch_global_keybindings(pid, input, opts \\ []) do
    GenServer.call(pid, {:global_input, input, opts})
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

  def put_theme(pid, theme, opts \\ []) do
    GenServer.call(pid, {:put_theme, theme, opts})
  end

  @impl true
  def init(opts) do
    apply_process_flags(Keyword.get(opts, :process_flags, []))

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
      |> Map.update(:breeze, %{keybindings: []}, fn
        breeze when is_map(breeze) -> Map.put_new(breeze, :keybindings, [])
        _ -> %{keybindings: []}
      end)
      |> Map.put(:__invalidate__, invalidate)

    term = %Breeze.Term{
      view: view,
      server: Keyword.get(opts, :server),
      terminal: terminal,
      theme: theme,
      theme_source: theme_input,
      apply_theme_defaults?: apply_theme_defaults?,
      render_tree?: Keyword.get(opts, :render_tree?, false) == true,
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

    maybe_probe_system_theme(term.theme, term.terminal, term.server)
    term = sync_theme_assigns(term)
    {:ok, term}
  end

  defp apply_process_flags(flags) when is_list(flags) do
    Enum.each(flags, fn
      {flag, value} when flag in [:min_heap_size, :min_bin_vheap_size, :fullsweep_after] ->
        Process.flag(flag, value)

      _flag ->
        :ok
    end)
  end

  defp apply_process_flags(_flags), do: :ok

  @impl true
  def handle_call({:metadata, opts}, _from, term) do
    metadata_term =
      if Keyword.has_key?(opts, :focused) do
        %{term | focused: Keyword.get(opts, :focused)}
      else
        term
      end

    {:reply,
     %{
       focused: metadata_term.focused,
       view: metadata_term.view,
       theme: metadata_term.theme,
       apply_theme_defaults?: metadata_term.apply_theme_defaults?,
       active_keybindings: active_keybindings(metadata_term),
       focused_implicit_id: focused_implicit_id(metadata_term, metadata_term.focused),
       focused_implicit_meta: focused_implicit_meta(metadata_term, metadata_term.focused),
       focus_meta: metadata_term.focus_meta,
       assigns: metadata_term.assigns,
       implicit_state: metadata_term.implicit_state,
       implicit_meta: metadata_term.implicit_meta
     }, term}
  end

  def handle_call(:layout_snapshot, _from, term) do
    {:reply, %{elements: term.elements, mouse_targets: term.mouse_targets}, term}
  end

  def handle_call({:render, opts}, _from, term) do
    {term, acc, box, _decorations} = render_term(term, opts)
    box = maybe_compact_snapshot_box(box, opts)
    {:reply, {:ok, acc, box}, term}
  end

  def handle_call({:render_snapshot, opts}, _from, term) do
    {term, acc, box, decorations} = render_term(term, opts)
    box = maybe_compact_snapshot_box(box, opts)
    {:reply, {:ok, acc, box, decorations}, term}
  end

  def handle_call({:event, change, event}, _from, term) do
    touched_term = touch_interaction(term)
    reply_from_input_result(handle_event(change, event, touched_term), touched_term)
  end

  def handle_call({:input, input, opts}, _from, term) do
    touched_term = touch_interaction(term)
    reply_from_input_result(process_input(input, touched_term, opts), touched_term, opts)
  end

  def handle_call({:global_input, input, opts}, _from, term) do
    touched_term = touch_interaction(term)
    event = normalize_key_event(input)

    case Breeze.GlobalKeybindings.dispatch(event, touched_term) do
      :continue ->
        {:reply, {:noreply, touched_term.focused, false}, touched_term}

      reply ->
        reply_from_input_result(reply, touched_term, opts)
    end
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
    reply_from_result(handle_view_info(term.view, message, term), term)
  end

  def handle_call({:put_global_keybindings, keybindings}, _from, term) do
    {:reply, :ok, %{term | global_keybindings: keybindings}}
  end

  def handle_call({:put_theme, theme_input, opts}, _from, term) do
    theme = Breeze.Theme.new(theme_input, terminal: term.terminal)

    next_term =
      %{
        term
        | theme: theme,
          theme_source: theme_input,
          apply_theme_defaults?:
            Keyword.get(opts, :apply_theme_defaults?, Breeze.Theme.defaults_enabled?(theme_input))
      }
      |> sync_theme_assigns()
      |> put_child_themes(theme_input)

    maybe_probe_system_theme(next_term.theme, next_term.terminal, next_term.server)

    if Keyword.get(opts, :notify?, true) do
      notify_invalidate(next_term)
    end

    {:reply, :ok, next_term}
  end

  def handle_call({:update_assigns, assigns}, _from, term) do
    next_term =
      term
      |> apply_external_assigns(Map.new(assigns))
      |> sync_theme_assigns()

    notify_invalidate(next_term)
    {:reply, :ok, next_term}
  end

  defp maybe_compact_snapshot_box(box, opts) do
    if Keyword.get(opts, :compact_snapshot, false) do
      %{box | layer_map: %{}}
    else
      box
    end
  end

  @impl true
  def handle_info({:breeze_theme_palette, key, _status}, term) do
    if requested_system_theme?(term.theme) and palette_notification_matches?(term.terminal, key) do
      theme =
        term.theme_source
        |> Kernel.||(term.theme)
        |> Breeze.Theme.normalize_requested_source()
        |> Breeze.Theme.new(terminal: term.terminal)

      next_term =
        %{term | theme: theme}
        |> sync_theme_assigns()
        |> cascade_theme_if_changed(term)

      notify_invalidate(next_term)
      {:noreply, next_term}
    else
      {:noreply, term}
    end
  end

  def handle_info({:child_invalidated, child_id}, term) do
    notify_invalidate(term, child_id)
    {:noreply, term}
  end

  def handle_info(message, term) do
    term = maybe_put_terminal(term, term.terminal)

    case handle_view_info(term.view, message, term) do
      {:noreply, next_term} ->
        next_term = cascade_info_theme_change(next_term, term)
        notify_invalidate(next_term)
        {:noreply, next_term}

      {:noreply, next_term, opts} ->
        next_term = cascade_info_theme_change(next_term, term)
        maybe_notify_invalidate(next_term, opts)
        {:noreply, next_term}

      {:stop, next_term} ->
        next_term = cascade_info_theme_change(next_term, term)
        notify_invalidate(next_term)
        {:stop, :normal, next_term}

      {:stop, next_term, opts} ->
        next_term = cascade_info_theme_change(next_term, term)
        maybe_notify_invalidate(next_term, opts)
        {:stop, :normal, next_term}
    end
  end

  defp reply_from_result({:noreply, next_term}, term) do
    next_term =
      term
      |> apply_focus_transitions(next_term)

    maybe_probe_system_theme(next_term.theme, next_term.terminal, next_term.server)

    next_term =
      next_term
      |> sync_theme_assigns()
      |> cascade_theme_if_changed(term)

    notify_invalidate(next_term)
    {:reply, {:noreply, next_term.focused}, next_term}
  end

  defp reply_from_result({:noreply, next_term, opts}, term) do
    next_term =
      term
      |> apply_focus_transitions(next_term)

    maybe_probe_system_theme(next_term.theme, next_term.terminal, next_term.server)

    next_term =
      next_term
      |> sync_theme_assigns()
      |> cascade_theme_if_changed(term)

    maybe_notify_invalidate(next_term, opts)
    {:reply, {:noreply, next_term.focused}, next_term}
  end

  defp reply_from_result({:stop, next_term}, term) do
    next_term =
      term
      |> apply_focus_transitions(next_term)
      |> sync_theme_assigns()
      |> cascade_theme_if_changed(term)

    notify_invalidate(next_term)
    {:stop, :normal, {:stop, next_term.focused}, next_term}
  end

  defp reply_from_result({:stop, next_term, opts}, term) do
    next_term =
      term
      |> apply_focus_transitions(next_term)
      |> sync_theme_assigns()
      |> cascade_theme_if_changed(term)

    maybe_notify_invalidate(next_term, opts)
    {:stop, :normal, {:stop, next_term.focused}, next_term}
  end

  defp maybe_put_terminal(term, nil), do: term
  defp maybe_put_terminal(term, terminal), do: %{term | terminal: terminal}

  defp handle_view_info(view, message, term) do
    if view_callback_exported?(view, :handle_info, 2) do
      view.handle_info(message, term)
    else
      {:noreply, term}
    end
  end

  defp handle_view_event(view, change, event, term) do
    if view_callback_exported?(view, :handle_event, 3) do
      normalize_result(view.handle_event(change, event, term), term)
    else
      {:noreply, term}
    end
  end

  defp view_callback_exported?(view, name, arity) do
    Code.ensure_loaded?(view) and function_exported?(view, name, arity)
  end

  defp maybe_probe_system_theme(theme, terminal, server) do
    if requested_system_theme?(theme) do
      if is_pid(server), do: send(server, {:ensure_runtime_palette, :system})
      Breeze.Theme.ensure_runtime_palette_async(terminal, self())
    else
      :ok
    end
  end

  defp requested_system_theme?(theme), do: Breeze.Theme.requested_system?(theme)

  defp palette_notification_matches?(%Termite.Terminal{reader: reader}, {:reader, reader})
       when not is_nil(reader),
       do: true

  defp palette_notification_matches?(_terminal, _key), do: false

  defp sync_theme_assigns(%{theme: theme, assigns: assigns} = term) when is_map(assigns) do
    assigns =
      assigns
      |> maybe_put_theme_assign(:theme_status, Breeze.Theme.probe_status(theme) || :ready)
      |> maybe_put_theme_assign(:actual_theme_mode, theme.mode)
      |> put_breeze_assign(:theme, breeze_theme_assign(term))
      |> put_breeze_assign(:keybindings, active_keybindings(term))

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

  defp put_breeze_assign(assigns, key, value) do
    Map.update(assigns, :breeze, %{key => value}, fn
      breeze when is_map(breeze) -> Map.put(breeze, key, value)
      _ -> %{key => value}
    end)
  end

  defp breeze_theme_assign(%{theme: theme, assigns: assigns}) do
    current = get_in(assigns, [:breeze, :theme]) || %{}
    name = Map.get(current, :name) || Map.get(current, "name") || theme.name || theme.mode

    %{
      name: name,
      actual_mode: theme.mode,
      status: Breeze.Theme.probe_status(theme) || :ready
    }
  end

  defp render_term(term, opts) do
    previous_term = term
    explicit_focus? = Keyword.has_key?(opts, :focused)
    term = maybe_put_terminal(term, Keyword.get(opts, :terminal))
    term = prune_dead_children(term)

    theme =
      Breeze.Theme.new(term.theme_source || term.theme || Keyword.get(opts, :theme),
        terminal: term.terminal
      )

    term = %{term | theme: theme}
    term = %{term | focused: Keyword.get(opts, :focused, term.focused)}

    initial_implicit_state =
      Keyword.get(opts, :implicit_state, %{})
      |> Map.merge(term.retained_implicit_state)
      |> Map.merge(term.implicit_state)

    previous_elements = Map.merge(term.retained_elements, term.elements)

    opts =
      opts
      |> Keyword.put(:implicit_state, initial_implicit_state)
      |> Keyword.put(:previous_elements, previous_elements)
      |> Keyword.put(:theme, theme)
      |> Keyword.put(:theme_source, term.theme_source || term.theme)
      |> Keyword.put(:apply_theme_defaults, term.apply_theme_defaults?)
      |> Keyword.put(:render_tree?, Keyword.get(opts, :render_tree?, term.render_tree?))

    profile_scope = Keyword.get(opts, :profile_scope)
    profile_label = profile_label(term, opts)

    final_opts =
      opts
      |> Keyword.put(:focused, term.focused)
      |> Keyword.put(:implicit_state, initial_implicit_state)
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

    {term, bootstrapped_initial_render_state?} =
      maybe_bootstrap_initial_render_state(
        term,
        final_opts,
        initial_implicit_state,
        explicit_focus?
      )

    first_pass_implicit_state =
      if bootstrapped_initial_render_state?, do: term.implicit_state, else: initial_implicit_state

    final_opts =
      final_opts
      |> Keyword.put(:focused, term.focused)
      |> Keyword.put(:implicit_state, first_pass_implicit_state)
      |> Keyword.put(:implicit_meta, term.implicit_meta)
      |> Keyword.put(:previous_elements, previous_elements)

    term = sync_theme_assigns(term)

    initial_implicit_state = term.implicit_state
    initial_implicit_meta = term.implicit_meta
    initial_focus = term.focused
    initial_keybindings = get_in(term.assigns, [:breeze, :keybindings]) || []

    {term, acc, box} =
      render_pass(term, final_opts, profile_scope, profile_label, explicit_focus?)

    term = sync_theme_assigns(term)

    {term, acc, box} =
      if implicit_state_rerender_needed?(
           term.implicit_state,
           initial_implicit_state,
           term.implicit_meta
         ) or
           term.implicit_meta != initial_implicit_meta or
           term.focused != initial_focus or
           layout_rerender_needed?(term, previous_elements) or
           (get_in(term.assigns, [:breeze, :keybindings]) || []) != initial_keybindings do
        rerender_keybindings = get_in(term.assigns, [:breeze, :keybindings]) || []

        rerender_opts =
          final_opts
          |> Keyword.put(:focused, term.focused)
          |> Keyword.put(:implicit_state, term.implicit_state)
          |> Keyword.put(:implicit_meta, term.implicit_meta)
          |> Keyword.put(:previous_elements, term.elements)

        {term, acc, box} =
          render_pass(term, rerender_opts, profile_scope, profile_label, explicit_focus?)

        term = sync_theme_assigns(term)

        if (get_in(term.assigns, [:breeze, :keybindings]) || []) != rerender_keybindings do
          final_rerender_opts =
            rerender_opts
            |> Keyword.put(:focused, term.focused)
            |> Keyword.put(:implicit_state, term.implicit_state)
            |> Keyword.put(:implicit_meta, term.implicit_meta)
            |> Keyword.put(:previous_elements, term.elements)

          render_pass(term, final_rerender_opts, profile_scope, profile_label, explicit_focus?)
        else
          {term, acc, box}
        end
      else
        {term, acc, box}
      end

    term = sync_theme_assigns(term)
    term = retain_inactive_render_state(previous_term, term)

    decorations =
      profile(profile_scope, profile_label, :decorations_us, fn ->
        extract_async_decorations(term)
      end)

    {term, acc, box, decorations}
  end

  defp maybe_bootstrap_initial_render_state(term, opts, implicit_state, explicit_focus?) do
    if term.implicit_state == %{} and term.implicit_meta == %{} do
      prepass_opts =
        opts
        |> Keyword.put(:implicit_state, implicit_state)
        |> Keyword.delete(:live_view)
        |> Keyword.put(:live_placeholder, true)
        |> Keyword.put(:layout_prepass, true)

      {acc, box} = Breeze.Renderer.render_tree(term.view, term.assigns, prepass_opts)

      %{dimensions: dimensions} = BackBreeze.Box.render_with_dimensions(box, prepass_opts)

      %{elements: elements, mouse_targets: mouse_targets} =
        Breeze.RenderState.build_layout(
          acc,
          dimensions,
          Map.get(acc, :live_dimensions, %{})
        )

      bootstrap =
        Breeze.RenderState.bootstrap(
          %{term | implicit_state: implicit_state},
          acc
        )

      focus_memory =
        Breeze.Focus.remember_focus(
          term.focus_memory,
          term.focused,
          bootstrap.focus_meta
        )

      focused =
        if explicit_focus? do
          term.focused
        else
          trapped_scope = Breeze.Focus.trapped_scope?(bootstrap.focusables, bootstrap.focus_meta)

          if term.allow_unfocused? and is_nil(term.focused) and not trapped_scope do
            nil
          else
            Breeze.Focus.normalize_focus(
              term.focused,
              bootstrap.focusables,
              bootstrap.focus_meta,
              focus_memory
            )
          end
        end

      {%{
         term
         | implicit_state: bootstrap.implicit_state,
           implicit_meta: bootstrap.implicit_meta,
           focusables: bootstrap.focusables,
           focus_meta: bootstrap.focus_meta,
           focus_memory: focus_memory,
           focused: focused,
           elements: elements,
           mouse_targets: mouse_targets
       }, true}
    else
      {term, false}
    end
  end

  defp implicit_state_rerender_needed?(next_state, previous_state, meta) do
    changed_ids =
      next_state
      |> Map.keys()
      |> Kernel.++(Map.keys(previous_state))
      |> Enum.uniq()

    Enum.any?(changed_ids, fn id ->
      Map.get(next_state, id) != Map.get(previous_state, id) and
        get_in(meta, [id, :state_change_requires_rerender]) != false
    end)
  end

  defp requires_layout_rerender?(term) do
    Enum.any?(term.implicit_meta, fn
      {_id, %{requires_layout_rerender: true}} -> true
      _ -> false
    end)
  end

  defp layout_rerender_needed?(term, previous_elements) do
    requires_layout_rerender?(term) and
      Enum.any?(term.implicit_meta, fn
        {id, %{requires_layout_rerender: true}} ->
          Map.get(term.elements, id) != Map.get(previous_elements, id)

        _ ->
          false
      end)
  end

  defp retain_inactive_render_state(previous_term, next_term) do
    retained_elements =
      previous_term.retained_elements
      |> Map.merge(previous_term.elements)
      |> Map.drop(Map.keys(next_term.elements))

    retained_implicit_state =
      previous_term.retained_implicit_state
      |> Map.merge(previous_term.implicit_state)
      |> Map.drop(Map.keys(next_term.implicit_state))

    %{
      next_term
      | retained_elements: retained_elements,
        retained_implicit_state: retained_implicit_state
    }
  end

  defp render_pass(term, opts, profile_scope, profile_label, explicit_focus?) do
    term = %{term | implicit_state: Keyword.get(opts, :implicit_state, term.implicit_state)}

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
  defp normalize_result({:noreply, next_term, opts}, _term), do: {:noreply, next_term, opts}
  defp normalize_result({:stop, next_term}, _term), do: {:stop, next_term}
  defp normalize_result({:stop, next_term, opts}, _term), do: {:stop, next_term, opts}

  defp process_input(%{"key" => key} = event, term, opts) when key in ["\t", "Tab"] do
    event
    |> Breeze.InputCapture.normalize_focus_key()
    |> process_input(term, opts)
  end

  defp process_input("\t", term, opts) do
    if focused_implicit_captures_key?("\t", term) do
      dispatch_key_input("\t", term, opts)
    else
      focus_next(term)
    end
  end

  defp process_input("ShiftTab", term, opts) do
    if focused_implicit_captures_key?("ShiftTab", term) do
      dispatch_key_input("ShiftTab", term, opts)
    else
      focus_previous(term)
    end
  end

  defp process_input(%{"mouse" => mouse} = event, term, _opts) do
    case mouse_target(term, mouse) do
      nil ->
        handle_view_event(term.view, :ignore_me, event, term)

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

  defp process_input(key, term, opts) do
    dispatch_key_input(key, term, opts)
  end

  defp dispatch_key_input(key, term, opts) do
    event = normalize_key_event(key)

    steps =
      cond do
        focused_implicit_captures_key?(event, term) ->
          [:hierarchy, :focused_implicit, :local, :global, :view_direct]

        printable_key?(event) ->
          [:hierarchy, :focused_implicit, :local, :global, :view_direct]

        true ->
          [:global, :hierarchy, :local, :view]
      end
      |> maybe_skip_global(Keyword.get(opts, :skip_global, false))

    dispatch_input_steps(steps, event, key, term)
  end

  defp focus_next(term) do
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

  defp focus_previous(term) do
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

  defp maybe_skip_global(steps, true), do: List.delete(steps, :global)
  defp maybe_skip_global(steps, _skip?), do: steps

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

      match?({:stop, opts} when is_list(opts), view_state) ->
        {:stop, term, elem(view_state, 1)}

      match?({:noreply, opts} when is_list(opts), view_state) and implicit_consumed ->
        {:noreply, term, elem(view_state, 1)}

      implicit_consumed ->
        {:noreply, term}

      true ->
        handle_view_event(term.view, change, event, term)
    end
  end

  defp handle_implicit_change(term, _id, change, event) do
    handle_view_event(term.view, change, event, term)
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

  defp dispatch_input_steps([:global | rest], event, key, term) do
    case Breeze.GlobalKeybindings.dispatch(event, term) do
      :continue -> dispatch_input_steps(rest, event, key, term)
      reply -> reply
    end
  end

  defp dispatch_input_steps([:hierarchy | rest], event, key, term) do
    case dispatch_input_hierarchy(term, key) do
      nil -> dispatch_input_steps(rest, event, key, term)
      reply -> reply
    end
  end

  defp dispatch_input_steps([:focused_implicit | rest], event, key, term) do
    case dispatch_focused_implicit_event(event, term) do
      :continue -> dispatch_input_steps(rest, event, key, term)
      reply -> reply
    end
  end

  defp dispatch_input_steps([:local | rest], event, key, term) do
    case dispatch_local_keybindings(event, term) do
      :continue -> dispatch_input_steps(rest, event, key, term)
      reply -> reply
    end
  end

  defp dispatch_input_steps([:view | _rest], event, _key, term) do
    handle_event(:ignore_me, event, term)
  end

  defp dispatch_input_steps([:view_direct | _rest], event, _key, term) do
    handle_view_event(term.view, :ignore_me, event, term)
  end

  defp dispatch_local_keybindings(event, term) do
    case Breeze.Keybindings.dispatch(event, current_view_keybindings(term), term) do
      :continue -> :continue
      {:stop, term} -> {:stop, term}
      {:noreply, term} -> {:noreply, term}
    end
  end

  defp dispatch_focused_implicit_event(event, term) do
    {view_state, implicit_consumed, term} =
      Breeze.RenderState.dispatch_implicit_event(
        term,
        term.focused,
        event,
        &handle_implicit_change/4
      )

    cond do
      view_state == :stop ->
        {:stop, term}

      match?({:stop, opts} when is_list(opts), view_state) ->
        {:stop, term, elem(view_state, 1)}

      match?({:noreply, opts} when is_list(opts), view_state) and implicit_consumed ->
        {:noreply, term, elem(view_state, 1)}

      implicit_consumed ->
        {:noreply, term}

      true ->
        :continue
    end
  end

  defp focused_implicit_captures_key?(event, term) do
    term
    |> focused_implicit_meta(term.focused)
    |> Breeze.InputCapture.captures_key?(event)
  end

  defp printable_key?(%{"key" => key} = event) when is_binary(key) do
    batched_printable_event?(event) or
      (not truthy_modifier?(Map.get(event, "ctrlKey")) and
         not truthy_modifier?(Map.get(event, "altKey")) and
         not truthy_modifier?(Map.get(event, "metaKey")) and
         printable_key?(key))
  end

  defp printable_key?(key) when is_binary(key) do
    String.length(key) == 1 and key not in ["\n", "\r", "\t", "\v", "\f"] and
      String.printable?(key) and not String.match?(key, ~r/[\x00-\x1F\x7F]/u)
  end

  defp printable_key?(_key), do: false

  defp batched_printable_event?(%{"__batched_printable__" => true, "key" => key})
       when is_binary(key) do
    key != "" and
      String.printable?(key) and
      Enum.all?(String.graphemes(key), fn grapheme ->
        grapheme not in ["\n", "\r", "\t", "\v", "\f"] and
          not String.match?(grapheme, ~r/[\x00-\x1F\x7F]/u)
      end)
  end

  defp batched_printable_event?(_event), do: false

  defp truthy_modifier?(value), do: value in [true, "true"]

  defp preload_and_attach_live_view(term, opts) do
    discovered =
      term.view.render(term.assigns)
      |> Breeze.Template.render_to_tree(term.assigns)
      |> collect_live_nodes([])
      |> Enum.reverse()
      |> Enum.uniq_by(&elem(&1, 0))

    term = ensure_children(term, discovered)

    if discovered == [] do
      {term, opts}
    else
      live_view = fn attrs, child_opts ->
        render_live_child(attrs, child_opts, term)
      end

      {term, Keyword.put(opts, :live_view, live_view)}
    end
  end

  defp collect_live_nodes(nodes, acc) when is_list(nodes) do
    Enum.reduce(nodes, acc, fn
      {:live, attrs}, acc ->
        [{fetch_live_attr!(attrs, :id), attrs} | acc]

      {:box, _attrs, children}, acc ->
        collect_live_nodes(children, acc)

      {_tag, _attrs, children}, acc when is_list(children) ->
        collect_live_nodes(children, acc)

      _other, acc ->
        acc
    end)
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

  defp put_child_themes(term, theme_input) do
    Enum.each(term.children, fn
      {_id, %{pid: pid}} when is_pid(pid) ->
        if Process.alive?(pid) do
          :ok =
            Breeze.ChildServer.put_theme(pid, theme_input,
              apply_theme_defaults?: term.apply_theme_defaults?,
              notify?: false
            )
        end

      _child ->
        :ok
    end)

    term
  end

  defp cascade_theme_if_changed(next_term, previous_term) do
    if theme_changed?(next_term, previous_term) do
      put_child_themes(next_term, next_term.theme_source || next_term.theme)
    else
      next_term
    end
  end

  defp theme_changed?(next_term, previous_term) do
    next_term.theme != previous_term.theme or next_term.theme_source != previous_term.theme_source or
      next_term.apply_theme_defaults? != previous_term.apply_theme_defaults?
  end

  defp cascade_info_theme_change(next_term, previous_term) do
    next_term
    |> sync_theme_assigns()
    |> cascade_theme_if_changed(previous_term)
  end

  defp start_child!(id, attrs, term) do
    view = fetch_live_attr!(attrs, :view)
    start_opts = fetch_live_attr(attrs, :start_opts, [])
    assigns = fetch_live_attr(attrs, :assigns, %{}) |> Map.new()
    parent = self()

    invalidate = fn
      nil -> send(parent, {:child_invalidated, id})
      child_id -> send(parent, {:child_invalidated, live_id(id, child_id)})
    end

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
        render_tree?: term.render_tree?,
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
                 render_tree?: Keyword.get(child_opts, :render_tree?, term.render_tree?),
                 live_prefix: full_prefix
               ) do
            {:ok, child_acc, child_box, _decorations} ->
              layout_snapshot = Breeze.ChildServer.layout_snapshot(pid)

              {:rendered, id, child_acc, child_box,
               translate_live_dimensions(
                 layout_snapshot.elements,
                 viewport,
                 full_prefix,
                 child_box
               )}

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

  defp active_keybindings(term) do
    Breeze.Keybindings.merge_visible([
      focused_child_keybindings(term),
      Breeze.Keybindings.visible(current_view_keybindings(term)),
      Breeze.GlobalKeybindings.visible(term)
    ])
  end

  defp focused_child_keybindings(term) do
    case focused_child_chain(term) do
      [{child_id, %{pid: pid}} | _] ->
        case safe_child_metadata(pid, focused: strip_live_prefix(term.focused, child_id)) do
          %{active_keybindings: keybindings} when is_list(keybindings) -> keybindings
          _ -> []
        end

      [] ->
        []
    end
  end

  defp current_view_keybindings(term) do
    local = Map.get(term, :local_keybindings, [])
    focused_local = get_in(term.focus_keybindings, [term.focused]) || []
    local ++ focused_local
  end

  defp safe_child_metadata(pid, opts) do
    Breeze.ChildServer.metadata(pid, opts)
  catch
    :exit, _reason -> %{}
  end

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

  defp reply_from_input_result(result, term, opts \\ [])

  defp reply_from_input_result({:noreply, next_term}, term, opts) do
    next_term =
      term
      |> apply_focus_transitions(next_term)

    maybe_probe_system_theme(next_term.theme, next_term.terminal, next_term.server)

    next_term =
      next_term
      |> sync_theme_assigns()
      |> cascade_theme_if_changed(term)

    maybe_notify_invalidate(next_term, opts)
    {:reply, {:noreply, next_term.focused, next_term != term}, next_term}
  end

  defp reply_from_input_result({:noreply, next_term, result_opts}, term, _opts)
       when is_list(result_opts) do
    next_term =
      term
      |> apply_focus_transitions(next_term)

    maybe_probe_system_theme(next_term.theme, next_term.terminal, next_term.server)

    next_term =
      next_term
      |> sync_theme_assigns()
      |> cascade_theme_if_changed(term)

    invalidate? = Keyword.get(result_opts, :invalidate, true)
    maybe_notify_invalidate(next_term, result_opts)
    {:reply, {:noreply, next_term.focused, invalidate? and next_term != term}, next_term}
  end

  defp reply_from_input_result({:noreply, focused, consumed}, term, opts) do
    next_term = %{term | focused: focused, allow_unfocused?: is_nil(focused)}
    maybe_notify_invalidate(next_term, opts)
    {:reply, {:noreply, next_term.focused, consumed}, next_term}
  end

  defp reply_from_input_result({:stop, next_term}, term, opts) do
    next_term =
      term
      |> apply_focus_transitions(next_term)
      |> sync_theme_assigns()
      |> cascade_theme_if_changed(term)

    maybe_notify_invalidate(next_term, opts)
    {:stop, :normal, {:stop, next_term.focused, true}, next_term}
  end

  defp reply_from_input_result({:stop, next_term, result_opts}, term, _opts)
       when is_list(result_opts) do
    next_term =
      term
      |> apply_focus_transitions(next_term)
      |> sync_theme_assigns()
      |> cascade_theme_if_changed(term)

    invalidate? = Keyword.get(result_opts, :invalidate, true)
    maybe_notify_invalidate(next_term, result_opts)
    {:stop, :normal, {:stop, next_term.focused, invalidate?}, next_term}
  end

  defp reply_from_input_result({:stop, focused, consumed}, term, opts) do
    next_term = %{term | focused: focused, allow_unfocused?: is_nil(focused)}
    maybe_notify_invalidate(next_term, opts)
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

  defp focused_implicit_meta(term, focused) do
    case focused_implicit_id(term, focused) do
      nil -> %{}
      id -> Map.get(term.implicit_meta, id, %{})
    end
  end

  defp notify_invalidate(term), do: notify_invalidate(term, nil)

  defp notify_invalidate(term, child_id) do
    case Map.get(term.assigns, :__invalidate__) do
      fun when is_function(fun, 1) -> fun.(child_id)
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
