defmodule Breeze.ChildServer do
  @moduledoc false

  use GenServer

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
    {acc, box} = Breeze.Renderer.render(term.view, term.assigns, opts)
    {:reply, {:ok, acc, box}, term}
  end

  def handle_call({:event, change, event}, _from, term) do
    reply_from_result(term.view.handle_event(change, event, term), term)
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

  defp notify_invalidate(term) do
    case Map.get(term.assigns, :__invalidate__) do
      fun when is_function(fun, 0) -> fun.()
      _ -> :ok
    end
  end
end
