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

  def dispatch_input(pid, key) do
    GenServer.call(pid, {:input, key})
  end

  def dispatch_event(pid, change, event) do
    GenServer.call(pid, {:event, change, event})
  end

  def dispatch_info(pid, message, terminal \\ nil) do
    GenServer.call(pid, {:info, message, terminal})
  end

  @impl true
  def init(opts) do
    view = Keyword.fetch!(opts, :view)
    terminal = Keyword.get(opts, :terminal)
    start_opts = Keyword.get(opts, :start_opts, [])
    invalidate = Keyword.get(opts, :invalidate)
    global_keybindings = Keyword.get(opts, :global_keybindings, [])

    term = %Breeze.Term{
      view: view,
      terminal: terminal,
      global_keybindings: global_keybindings,
      assigns: %{__invalidate__: invalidate}
    }

    {:ok, term} = view.mount(start_opts, term)
    {:ok, term}
  end

  @impl true
  def handle_call(:metadata, _from, term) do
    {:reply, %{focused: term.focused, view: term.view}, term}
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

  def handle_call({:input, key}, _from, term) do
    touched_term = touch_interaction(term)
    reply_from_input_result(process_input(key, touched_term), touched_term)
  end

  def handle_call({:info, message, terminal}, _from, term) do
    term = maybe_put_terminal(term, terminal)
    reply_from_result(term.view.handle_info(message, term), term)
  end

  @impl true
  def handle_info(message, term) do
    term = maybe_put_terminal(term, term.terminal)

    case term.view.handle_info(message, term) do
      {:noreply, next_term} ->
        notify_invalidate(next_term)
        {:noreply, next_term}

      {:stop, next_term} ->
        notify_invalidate(next_term)
        {:stop, :normal, next_term}
    end
  end

  defp reply_from_result({:noreply, next_term}, _term) do
    notify_invalidate(next_term)
    {:reply, {:noreply, next_term.focused}, next_term}
  end

  defp reply_from_result({:stop, next_term}, _term) do
    notify_invalidate(next_term)
    {:stop, :normal, {:stop, next_term.focused}, next_term}
  end

  defp maybe_put_terminal(term, nil), do: term
  defp maybe_put_terminal(term, terminal), do: %{term | terminal: terminal}

  defp render_term(term, opts) do
    explicit_focus? = Keyword.has_key?(opts, :focused)
    term = maybe_put_terminal(term, Keyword.get(opts, :terminal))
    term = %{term | focused: Keyword.get(opts, :focused, term.focused)}
    implicit_state = Keyword.get(opts, :implicit_state, %{}) |> Map.merge(term.implicit_state)
    opts = Keyword.put(opts, :implicit_state, implicit_state)

    {term, _acc, _box} =
      render_with_reconciled_implicits(term, opts, fn current_term, current_opts ->
        {acc, box} = Breeze.Renderer.render(current_term.view, current_term.assigns, current_opts)
        current_term = Breeze.RenderState.build(current_term, acc)
        focus_meta = Breeze.Focus.build_meta(acc.elements, current_term.implicit_state)

        focus_memory =
          Breeze.Focus.remember_focus(
            current_term.focus_memory,
            current_term.focused,
            current_term.focus_meta
          )

        focused =
          if explicit_focus? do
            current_term.focused
          else
            trapped_scope = Breeze.Focus.trapped_scope?(acc.focusables, focus_meta)

            if current_term.allow_unfocused? and is_nil(current_term.focused) and
                 not trapped_scope do
              nil
            else
              Breeze.Focus.normalize_focus(
                current_term.focused,
                acc.focusables,
                focus_meta,
                focus_memory
              )
            end
          end

        current_term = %{
          current_term
          | focus_meta: focus_meta,
            focus_memory: focus_memory,
            focused: focused,
            allow_unfocused?: current_term.allow_unfocused? and is_nil(focused)
        }

        {current_term, acc, box}
      end)

    final_opts =
      opts
      |> Keyword.put(:focused, term.focused)
      |> Keyword.put(:implicit_state, term.implicit_state)
      |> Keyword.put(:implicit_meta, term.implicit_meta)
      |> Keyword.put(:last_render_at, term.last_render_at)
      |> Keyword.put(:last_interaction_at, term.last_interaction_at)
      |> Keyword.put(:animation_now, System.monotonic_time(:millisecond))

    {acc, box} = Breeze.Renderer.render(term.view, term.assigns, final_opts)
    term = Breeze.RenderState.build(term, acc)
    term = %{term | focus_meta: Breeze.Focus.build_meta(acc.elements, term.implicit_state)}
    decorations = extract_async_decorations(term)

    {term, acc, box, decorations}
  end

  defp render_with_reconciled_implicits(term, opts, render_fun, attempts \\ 2) do
    {term, acc, box} = render_fun.(term, opts)

    implicit_state =
      Breeze.RenderState.reconcile_implicits(term.implicit_state, term.elements)

    if attempts > 0 and implicit_state != term.implicit_state do
      term = %{term | implicit_state: implicit_state}
      opts = Keyword.put(opts, :implicit_state, implicit_state)
      render_with_reconciled_implicits(term, opts, render_fun, attempts - 1)
    else
      {term, acc, box}
    end
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

  defp process_input(key, term) do
    event = %{"key" => key}

    case Breeze.Server.dispatch_global_keybindings(event, term) do
      {:stop, term} ->
        {:stop, term}

      {:noreply, term} ->
        {:noreply, term}

      :continue ->
        handle_event(:ignore_me, event, term)
    end
  end

  defp handle_event(change, event, term) do
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

        if is_integer(every_ms) and every_ms > 0 and match?(%BackBreeze.Box{}, box) and
             function_exported?(mod, :animate, 5) do
          [
            %{
              id: id,
              mod: mod,
              state: implicit,
              box: box,
              flags: focus_flags(term, id),
              every_ms: every_ms,
              active_when_pending: get_in(term.implicit_meta, [id, :active_when_pending]) == true
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
    notify_invalidate(next_term)
    {:reply, {:noreply, next_term.focused, next_term != term}, next_term}
  end

  defp reply_from_input_result({:stop, next_term}, _term) do
    notify_invalidate(next_term)
    {:stop, :normal, {:stop, next_term.focused, true}, next_term}
  end

  defp notify_invalidate(term) do
    case Map.get(term.assigns, :__invalidate__) do
      fun when is_function(fun, 0) -> fun.()
      _ -> :ok
    end
  end
end
