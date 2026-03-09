defmodule Breeze.ChildServer do
  @moduledoc false

  use GenServer
  alias Breeze.Viewport

  def start(opts) do
    GenServer.start(__MODULE__, opts)
  end

  def snapshot(pid) do
    GenServer.call(pid, :snapshot)
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
  def handle_call(:snapshot, _from, term) do
    {:reply, %{focused: term.focused, view: term.view}, term}
  end

  def handle_call({:render, opts}, _from, term) do
    term = maybe_put_terminal(term, Keyword.get(opts, :terminal))
    term = %{term | focused: Keyword.get(opts, :focused, term.focused)}
    implicit_state = Keyword.get(opts, :implicit_state, %{}) |> Map.merge(term.implicit_state)
    opts = Keyword.put(opts, :implicit_state, implicit_state)

    {term, acc, box} =
      render_with_reconciled_implicits(term, opts, fn current_term, current_opts ->
        {acc, box} = Breeze.Renderer.render(current_term.view, current_term.assigns, current_opts)
        {put_render_state(current_term, acc), acc, box}
      end)

    {:reply, {:ok, acc, box}, term}
  end

  def handle_call({:event, change, event}, _from, term) do
    {view_state, implicit_consumed, term} =
      case Map.get(term.implicit_state, term.focused) do
        {mod, implicit} ->
          dispatch_implicit_event(term.focused, mod, implicit, event, term)

        nil ->
          {:noreply, false, term}
      end

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
    implicit_state = reconcile_scroll_implicits(term.implicit_state, term.elements)

    if attempts > 0 and implicit_state != term.implicit_state do
      term = %{term | implicit_state: implicit_state}
      opts = Keyword.put(opts, :implicit_state, implicit_state)
      render_with_reconciled_implicits(term, opts, render_fun, attempts - 1)
    else
      {term, acc, box}
    end
  end

  defp put_render_state(term, acc) do
    last = map_size(acc.elements)

    implicits =
      acc.elements
      |> Enum.sort()
      |> Enum.reduce({%{}, [], nil, nil, %{}}, fn {idx, elem},
                                                  {implicit_acc, current, mod, last_id,
                                                   root_attrs} ->
        elem = Map.new(elem) |> Map.delete(:focusable)
        {implicit, elem} = Map.pop(elem, :implicit)
        {id, elem} = Map.pop(elem, :id)
        {implicit_owner, elem} = Map.pop(elem, :implicit_owner)

        cond do
          last == 1 && implicit && id ->
            {add_implicit_item(implicit_acc, term, id, implicit, [], elem), [], implicit, id,
             elem}

          mod && (implicit || idx == last - 1) ->
            current = if implicit_owner, do: [elem | current], else: current
            items = Enum.reverse(current)
            implicit_acc = add_implicit_item(implicit_acc, term, last_id, mod, items, root_attrs)

            implicit_acc =
              if implicit && id do
                add_implicit_item(implicit_acc, term, id, implicit, [], elem)
              else
                implicit_acc
              end

            {implicit_acc, [], implicit, id, elem}

          !mod && implicit ->
            {implicit_acc, current, implicit, id, elem}

          implicit_owner ->
            {implicit_acc, [elem | current], mod, last_id, root_attrs}

          true ->
            {implicit_acc, current, mod, last_id, root_attrs}
        end
      end)
      |> elem(0)

    events =
      acc.elements
      |> Enum.sort()
      |> Enum.reduce(%{}, fn {_idx, elem}, events ->
        id = Keyword.get(elem, :id)
        change = Keyword.get(elem, :"br-change")
        if change, do: Map.put(events, id, %{change: change}), else: events
      end)

    elements =
      Enum.zip(Enum.sort(acc.elements), acc.dimensions)
      |> Enum.reduce(%{}, fn {{_idx, flags}, dims}, elements ->
        case Keyword.get(flags, :id) do
          nil -> elements
          id -> Map.put(elements, id, Viewport.from_dimensions(dims))
        end
      end)

    %{
      term
      | elements: elements,
        focusables: acc.focusables,
        implicit_state: implicits,
        events: events
    }
  end

  defp add_implicit_item(acc, term, id, mod, items, root_attrs) do
    last_state =
      case term.implicit_state[id] do
        {_mod, last_state} -> last_state
        _ -> %{}
      end

    last_state =
      case Map.get(term.elements, id) do
        nil -> last_state
        element -> Map.put(last_state, :__element__, element)
      end

    implicit_state =
      case Code.ensure_loaded(mod) do
        {:module, _module} ->
          cond do
            function_exported?(mod, :init, 3) ->
              mod.init(items, root_attrs, last_state)

            function_exported?(mod, :init, 2) ->
              mod.init(items, last_state)

            true ->
              raise ArgumentError, "implicit #{inspect(mod)} must implement init/2 or init/3"
          end

        {:error, reason} ->
          raise ArgumentError,
                "implicit #{inspect(mod)} could not be loaded (#{inspect(reason)})"
      end

    Map.put(acc, id, {mod, implicit_state})
  end

  defp dispatch_implicit_event(id, mod, implicit, payload, term, visited \\ MapSet.new()) do
    if MapSet.member?(visited, id) do
      {:noreply, false, term}
    else
      payload = Map.put(payload, "element", Map.get(term.elements, id))

      case mod.handle_event(:ignore_me, payload, implicit) do
        {{:change, event}, val} ->
          term = put_implicit_state(term, id, mod, val)

          {view_state, term} =
            case get_in(term.events, [id, :change]) do
              nil -> {:noreply, term}
              change -> normalize_result(term.view.handle_event(change, event, term), term)
            end

          {view_state, true, term}

        {{:delegate, target_id}, val} ->
          term = put_implicit_state(term, id, mod, val)

          case Map.get(term.implicit_state, target_id) do
            {target_mod, target_state} ->
              dispatch_implicit_event(
                target_id,
                target_mod,
                target_state,
                payload,
                term,
                MapSet.put(visited, id)
              )

            nil ->
              {:noreply, false, term}
          end

        {:noreply, val} ->
          {:noreply, true, put_implicit_state(term, id, mod, val)}
      end
    end
  end

  defp put_implicit_state(term, id, mod, implicit) do
    %{term | implicit_state: Map.put(term.implicit_state, id, {mod, implicit})}
  end

  defp reconcile_scroll_implicits(implicit_state, elements) do
    Enum.reduce(implicit_state, %{}, fn
      {id, {Breeze.Implicit.Scroll, state}}, acc ->
        next_state =
          case Map.get(elements, id) do
            nil -> state
            element -> Breeze.Implicit.Scroll.reconcile(element, state)
          end

        Map.put(acc, id, {Breeze.Implicit.Scroll, next_state})

      {id, value}, acc ->
        Map.put(acc, id, value)
    end)
  end

  defp normalize_result({:noreply, next_term}, _term), do: {:noreply, next_term}
  defp normalize_result({:stop, next_term}, _term), do: {:stop, next_term}

  defp notify_invalidate(term) do
    case Map.get(term.assigns, :__invalidate__) do
      fun when is_function(fun, 0) -> fun.()
      _ -> :ok
    end
  end
end
