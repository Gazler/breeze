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

    term = %Breeze.Term{view: view, terminal: terminal, assigns: %{__invalidate__: invalidate}}
    {:ok, term} = view.mount(start_opts, term)
    {:ok, term}
  end

  @impl true
  def handle_call(:metadata, _from, term) do
    {:reply, %{focused: term.focused, view: term.view}, term}
  end

  def handle_call({:render, opts}, _from, term) do
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
            Breeze.Focus.normalize_focus(
              current_term.focused,
              acc.focusables,
              focus_meta,
              focus_memory
            )
          end

        current_term = %{
          current_term
          | focus_meta: focus_meta,
            focus_memory: focus_memory,
            focused: focused
        }

        {current_term, acc, box}
      end)

    final_opts =
      opts
      |> Keyword.put(:focused, term.focused)
      |> Keyword.put(:implicit_state, term.implicit_state)

    {acc, box} = Breeze.Renderer.render(term.view, term.assigns, final_opts)
    term = Breeze.RenderState.build(term, acc)
    term = %{term | focus_meta: Breeze.Focus.build_meta(acc.elements, term.implicit_state)}

    {:reply, {:ok, acc, box}, term}
  end

  def handle_call({:event, change, event}, _from, term) do
    {view_state, implicit_consumed, term} =
      Breeze.RenderState.dispatch_implicit_event(
        term,
        term.focused,
        event,
        &handle_implicit_change/4
      )

    cond do
      view_state == :stop ->
        notify_invalidate(term)
        {:stop, :normal, {:stop, term.focused}, term}

      implicit_consumed ->
        notify_invalidate(term)
        {:reply, {:noreply, term.focused}, term}

      true ->
        reply_from_result(term.view.handle_event(change, event, term), term)
    end
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

  defp handle_implicit_change(term, _id, change, event) do
    normalize_result(term.view.handle_event(change, event, term), term)
  end

  defp notify_invalidate(term) do
    case Map.get(term.assigns, :__invalidate__) do
      fun when is_function(fun, 0) -> fun.()
      _ -> :ok
    end
  end
end
