defmodule Breeze.Term do
  @moduledoc false

  defstruct [
    :view,
    :terminal,
    :reader,
    assigns: %{},
    focused: nil,
    focusables: [],
    elements: %{},
    events: %{},
    implicit_state: %{},
    children: %{},
    frame_delay_ms: 16,
    render_timer: nil
  ]
end

defmodule Breeze.Server do
  @moduledoc """
  This module powers the GenServer responsible for running the application.

  Consider the following Breeze Application:

  ```
  defmodule Demo do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, counter: 0)}

    def render(assigns) do
      ~H"<box>Counter: <%= @counter %></box>"
    end

    def handle_event(_, %{"key" => "ArrowUp"}, term) do
      {:noreply, assign(term, counter: term.assigns.counter + 1)}
    end

    def handle_event(_, %{"key" => "ArrowDown"}, term) do
      {:noreply, assign(term, counter: term.assigns.counter - 1)}
    end

    def handle_event(_, %{"key" => "q"}, term) do
      {:stop, term}
    end

    def handle_event(_, _, term) do
      {:noreply, term}
    end
  end
  ```

  This can be started directly with:

  ```
  Breeze.Server.start_link(view: Focus)
  ```

  Or in a supervision tree:

  ```
  children = [
    {Breeze.Server, view: Demo}
  ]
  ```
  """

  use GenServer

  @doc """
  Start the Breeze application.

  Valid options are:

    * `:view` - the view to run. This is required
    * `:hide_cursor` - hide the cursor on start. Defaults to `false`

  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc false
  def init(opts) do
    view = Keyword.fetch!(opts, :view)
    frame_delay_ms = Keyword.get(opts, :frame_delay_ms, 16)
    {:ok, %Breeze.Term{view: view, frame_delay_ms: frame_delay_ms}, {:continue, {:start, opts}}}
  end

  @doc false
  def handle_continue({:start, opts}, state) do
    start_opts = Keyword.get(opts, :start_opts, [])
    terminal = Termite.Terminal.start()

    terminal =
      if Keyword.get(opts, :hide_cursor) do
        Termite.Screen.hide_cursor(terminal)
      else
        terminal
      end

    reader = terminal.reader
    state = %{state | terminal: terminal, reader: reader}
    {:ok, state} = state.view.mount(start_opts, state)
    terminal = Termite.Screen.clear_screen(state.terminal)
    state = render(%{state | terminal: terminal})
    {:noreply, state}
  end

  @doc false
  def handle_info({reader, {:data, data}}, %{reader: reader} = state) do
    case process_data(data, state) do
      {:stop, state} ->
        stop(state)

      {:noreply, state} ->
        case drain_keys(state) do
          {:stop, state} -> stop(state)
          {:noreply, state} -> {:noreply, render(state)}
        end
    end
  end

  def handle_info({reader, {:signal, :winch}}, %{reader: reader} = state) do
    state = %{state | terminal: Termite.Terminal.resize(state.terminal)}
    state = notify_children(state, :resize, state.terminal)

    case state.view.handle_info(:resize, state) do
      {:noreply, state} -> {:noreply, render(state)}
      {:stop, state} -> stop(state)
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    children =
      state.children
      |> Enum.reject(fn {_id, child} -> child.ref == ref end)
      |> Map.new()

    focused =
      case split_child_id(state.focused, children) do
        {_, _} -> nil
        nil -> state.focused
      end

    {:noreply, %{state | children: children, focused: focused}}
  end

  def handle_info(:render_frame, state) do
    {:noreply, render(%{state | render_timer: nil})}
  end

  def handle_info({:child_invalidated, _id}, state) do
    {:noreply, schedule_render(state)}
  end

  def handle_info(message, state) do
    case state.view.handle_info(message, state) do
      {:noreply, state} ->
        state = render(state)
        {:noreply, state}

      {:stop, state} ->
        stop(state)
    end
  end

  defp process_data("\t", state) do
    index = Enum.find_index(state.focusables, &(&1 == state.focused))

    new_focused =
      if index do
        Enum.at(state.focusables, index + 1)
      else
        hd(state.focusables)
      end

    {:noreply, %{state | focused: new_focused}}
  end

  defp process_data("\e[Z", state) do
    index = Enum.find_index(state.focusables, &(&1 == state.focused))

    new_focused =
      cond do
        index == 0 -> nil
        index == nil -> hd(Enum.reverse(state.focusables))
        true -> Enum.at(state.focusables, index - 1)
      end

    {:noreply, %{state | focused: new_focused}}
  end

  defp process_data("\e", state) do
    receive do
      {reader, {:data, data}} when reader == state.reader ->
        process_data("\e" <> data, state)
    after
      5 -> do_process_key("Escape", state)
    end
  end

  defp process_data("\eO", state) do
    receive do
      {reader, {:data, data}} when reader == state.reader ->
        do_process_key(convert_key_o(data), state)
    after
      5 -> do_process_key("Escape", state)
    end
  end

  defp process_data(raw_key, state) do
    key =
      cond do
        String.starts_with?(raw_key, "\eO") ->
          convert_key_o(String.trim_leading(raw_key, "\eO"))

        String.starts_with?(raw_key, Termite.Screen.escape_code()) ->
          convert_key(String.trim_leading(raw_key, Termite.Screen.escape_code()))

        true ->
          raw_key
      end

    do_process_key(key, state)
  end

  defp do_process_key(key, state) do
    selected_implicit = Enum.find(state.implicit_state, fn {id, _el} -> id == state.focused end)

    {view_state, implicit_consumed, state} =
      if selected_implicit do
        {id, {_mod, _selected}} = selected_implicit

        Breeze.RenderState.dispatch_implicit_event(
          state,
          id,
          %{"key" => key},
          fn state, id, change, event -> route_event(id, change, event, state) end
        )
      else
        {:noreply, false, state}
      end

    cond do
      view_state == :stop ->
        {:stop, state}

      implicit_consumed ->
        {:noreply, state}

      true ->
        case route_event(state.focused, :ignore_me, %{"key" => key}, state) do
          {:stop, state} -> {:stop, state}
          {:noreply, state} -> {:noreply, state}
        end
    end
  end

  defp drain_keys(state) do
    receive do
      {reader, {:data, data}} when reader == state.reader ->
        case process_data(data, state) do
          {:stop, state} -> {:stop, state}
          {:noreply, state} -> drain_keys(state)
        end
    after
      0 -> {:noreply, state}
    end
  end

  defp stop(state) do
    Enum.each(state.children, fn {_id, child} -> GenServer.stop(child.pid, :normal) end)

    state.terminal
    |> Termite.Screen.clear_screen()
    |> Termite.Screen.show_cursor()
    |> Termite.Screen.exit_alt_screen()

    System.halt()
  end

  defp render(state) do
    {state, _live_ids, visible_live_ids, {_acc, _box}} = render_view(state, state.implicit_state)
    state = sync_child_visibility(state, visible_live_ids)
    {state, _live_ids, _visible_live_ids, {acc, _box}} = render_view(state, state.implicit_state)

    implicits = Breeze.RenderState.build(state, acc).implicit_state

    events =
      acc.elements
      |> Enum.sort()
      |> Enum.reduce(%{}, fn {_idx, elem}, acc ->
        id = Keyword.get(elem, :id)
        change = Keyword.get(elem, :"br-change")

        if change do
          Map.put(acc, id, %{change: change})
        else
          acc
        end
      end)

    focused = state.focused

    {state, live_ids, _final_acc, output, dimensions, implicits} =
      render_final_view(%{state | focused: focused}, implicits)

    {state, live_ids} = prune_children(state, live_ids)
    implicits = prune_implicit_state(implicits, live_ids, state.children)

    screen_height = state.terminal.size.height
    output_lines = length(String.split(output, "\n"))
    trailing = String.duplicate("\n\e[K", max(screen_height - output_lines, 0))
    output = "\e[K" <> String.replace(output, "\n", "\n\e[K") <> trailing
    terminal = Termite.Terminal.write(state.terminal, "\e[H" <> output)

    %{
      state
      | terminal: terminal,
        elements: dimensions,
        focusables: acc.focusables,
        focused: focused,
        implicit_state: implicits,
        events: events
    }
  end

  defp render_final_view(state, implicits, attempts \\ 2) do
    {state, live_ids, _visible_live_ids, {final_acc, %{content: output}}} =
      render_view(state, implicits)

    dimensions = Breeze.RenderState.build_dimensions(final_acc)
    adjusted_implicits = Breeze.RenderState.reconcile_implicits(implicits, dimensions)

    if attempts > 0 and adjusted_implicits != implicits do
      render_final_view(state, adjusted_implicits, attempts - 1)
    else
      {state, live_ids, final_acc, output, dimensions, adjusted_implicits}
    end
  end

  defp render_view(state, implicit_state) do
    collector = self()
    token = make_ref()

    result =
      Breeze.Renderer.render(state.view, state.assigns,
        focused: state.focused,
        implicit_state: implicit_state,
        terminal: state.terminal,
        live_view: fn attrs, opts ->
          render_live_child(attrs, opts, state, implicit_state, collector, token)
        end
      )

    %{requested: live_ids, visible: visible_live_ids, missing: missing} =
      collect_render_tracking(token, %{requested: [], visible: [], missing: []})

    case ensure_children(state, missing) do
      {state, true} -> render_view(state, implicit_state)
      {state, false} -> {state, live_ids, visible_live_ids, result}
    end
  end

  defp convert_key_o("P"), do: "F1"
  defp convert_key_o("Q"), do: "F2"
  defp convert_key_o("R"), do: "F3"
  defp convert_key_o("S"), do: "F4"
  defp convert_key_o(key), do: key

  defp convert_key("11~"), do: "F1"
  defp convert_key("12~"), do: "F2"
  defp convert_key("13~"), do: "F3"
  defp convert_key("14~"), do: "F4"
  defp convert_key("A"), do: "ArrowUp"
  defp convert_key("B"), do: "ArrowDown"
  defp convert_key("C"), do: "ArrowRight"
  defp convert_key("D"), do: "ArrowLeft"
  defp convert_key("H"), do: "Home"
  defp convert_key("F"), do: "End"
  defp convert_key("1~"), do: "Home"
  defp convert_key("4~"), do: "End"
  defp convert_key("5~"), do: "PageUp"
  defp convert_key("6~"), do: "PageDown"
  defp convert_key(key), do: key

  defp handle_event(change, event, state) do
    state.view.handle_event(change, event, state)
  end

  defp render_live_child(attrs, opts, state, implicit_state, collector, token) do
    id = fetch_live_attr!(attrs, :id)
    full_id = live_id(Keyword.get(opts, :live_prefix), id)
    preload_only = fetch_live_attr(attrs, :preload_only, false)
    send(collector, {:breeze_live_track, token, :requested, full_id})

    if !preload_only do
      send(collector, {:breeze_live_track, token, :visible, full_id})
    end

    case Map.get(state.children, full_id) do
      nil ->
        send(collector, {:breeze_live_track, token, :missing, {full_id, attrs}})
        if preload_only, do: :preloaded, else: :missing

      %{pid: pid} ->
        if preload_only do
          :preloaded
        else
          local_focused = strip_live_prefix(state.focused, full_id)
          local_implicit_state = child_implicit_state(implicit_state, full_id)

          {:ok, child_acc, child_box} =
            Breeze.ChildServer.render(pid,
              focused: local_focused,
              implicit_state: local_implicit_state,
              terminal: state.terminal,
              live_prefix: full_id,
              live_view: fn child_attrs, child_opts ->
                render_live_child(
                  child_attrs,
                  child_opts,
                  state,
                  implicit_state,
                  collector,
                  token
                )
              end
            )

          {:rendered, id, child_acc, child_box}
        end
    end
  end

  defp ensure_children(state, missing) do
    Enum.reduce(missing, {state, false}, fn {id, attrs}, {state, started?} ->
      if Map.has_key?(state.children, id) do
        {state, started?}
      else
        child = start_child!(attrs, state.terminal)
        state = %{state | children: Map.put(state.children, id, child)}
        state = maybe_take_child_focus(state, id, child.pid)
        {state, true}
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
    %{pid: pid, ref: ref, view: view, persistent: persistent, visible: false}
  end

  defp maybe_take_child_focus(%{focused: nil} = state, id, pid) do
    case Breeze.ChildServer.metadata(pid) do
      %{focused: nil} -> state
      %{focused: focused} -> %{state | focused: namespace_live_id(id, focused)}
    end
  end

  defp maybe_take_child_focus(state, _id, _pid), do: state

  defp prune_children(state, live_ids) do
    live_ids = MapSet.new(live_ids)

    {keep, drop} =
      Enum.split_with(state.children, fn {id, child} ->
        MapSet.member?(live_ids, id) or child.persistent
      end)

    Enum.each(drop, fn {_id, child} ->
      Process.demonitor(child.ref, [:flush])
      GenServer.stop(child.pid, :normal)
    end)

    children = Map.new(keep)

    focused =
      case split_child_id(state.focused, children) do
        {_, _} -> state.focused
        nil -> if(child_focus_id?(state.focused), do: nil, else: state.focused)
      end

    {%{state | children: children, focused: focused}, MapSet.to_list(live_ids)}
  end

  defp prune_implicit_state(implicit_state, live_ids, children) do
    Enum.reduce(implicit_state, %{}, fn {id, value}, acc ->
      if keep_implicit_id?(id, live_ids, children), do: Map.put(acc, id, value), else: acc
    end)
  end

  defp keep_implicit_id?(id, live_ids, children) do
    not String.contains?(id, "::") or
      Enum.any?(live_ids ++ Map.keys(children), fn live_id ->
        String.starts_with?(id, live_id <> "::")
      end)
  end

  defp notify_children(state, message, terminal) do
    Enum.reduce(state.children, state, fn {id, child}, state ->
      case Breeze.ChildServer.dispatch_info(child.pid, message, terminal) do
        {:noreply, focused} -> update_child_focus(state, id, focused)
        {:stop, _focused} -> %{state | children: Map.delete(state.children, id)}
      end
    end)
  end

  defp route_event(id, change, event, state) do
    case split_child_id(id, state.children) do
      {child_id, local_id} ->
        dispatch_child_event(state, child_id, local_id, change, event)

      nil ->
        handle_event(change, event, state)
    end
  end

  defp dispatch_child_event(state, child_id, local_id, change, event) do
    %{pid: pid} = Map.fetch!(state.children, child_id)
    event = Map.put(event, "target", local_id)

    case Breeze.ChildServer.dispatch_event(pid, change, event) do
      {:noreply, focused} ->
        {:noreply, update_child_focus(state, child_id, focused)}

      {:stop, _focused} ->
        state = %{state | children: Map.delete(state.children, child_id)}
        {:noreply, clear_child_focus(state, child_id)}
    end
  end

  defp update_child_focus(state, _child_id, nil), do: state

  defp update_child_focus(state, child_id, focused),
    do: %{state | focused: namespace_live_id(child_id, focused)}

  defp clear_child_focus(%{focused: focused} = state, child_id) do
    if strip_live_prefix(focused, child_id) do
      %{state | focused: nil}
    else
      state
    end
  end

  defp child_implicit_state(implicit_state, live_id) do
    prefix = live_id <> "::"

    Enum.reduce(implicit_state, %{}, fn {id, value}, acc ->
      case String.starts_with?(id, prefix) do
        true -> Map.put(acc, String.replace_prefix(id, prefix, ""), value)
        false -> acc
      end
    end)
  end

  defp split_child_id(nil, _children), do: nil

  defp split_child_id(id, children) do
    children
    |> Map.keys()
    |> Enum.sort_by(&String.length/1, :desc)
    |> Enum.find_value(fn child_id ->
      prefix = child_id <> "::"

      if String.starts_with?(id, prefix) do
        {child_id, String.replace_prefix(id, prefix, "")}
      end
    end)
  end

  defp strip_live_prefix(nil, _live_id), do: nil

  defp strip_live_prefix(id, live_id) do
    prefix = live_id <> "::"

    if String.starts_with?(id, prefix) do
      String.replace_prefix(id, prefix, "")
    end
  end

  defp namespace_live_id(_live_id, nil), do: nil
  defp namespace_live_id(live_id, id), do: live_id <> "::" <> id

  defp live_id(nil, id), do: id
  defp live_id(prefix, id), do: prefix <> "::" <> id

  defp child_focus_id?(id) when is_binary(id), do: String.contains?(id, "::")
  defp child_focus_id?(_id), do: false

  defp fetch_live_attr!(attrs, key) do
    Map.get(attrs, key) || Map.fetch!(attrs, Atom.to_string(key))
  end

  defp fetch_live_attr(attrs, key, default) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key), default)
  end

  defp collect_render_tracking(token, acc) do
    receive do
      {:breeze_live_track, ^token, :requested, id} ->
        collect_render_tracking(token, %{acc | requested: acc.requested ++ [id]})

      {:breeze_live_track, ^token, :visible, id} ->
        collect_render_tracking(token, %{acc | visible: acc.visible ++ [id]})

      {:breeze_live_track, ^token, :missing, item} ->
        collect_render_tracking(token, %{acc | missing: acc.missing ++ [item]})
    after
      0 -> acc
    end
  end

  defp sync_child_visibility(state, visible_live_ids) do
    visible_live_ids = MapSet.new(visible_live_ids)

    children =
      Enum.reduce(state.children, %{}, fn {id, child}, acc ->
        visible? = MapSet.member?(visible_live_ids, id)

        case maybe_update_child_visibility(child, visible?) do
          {:keep, child} -> Map.put(acc, id, child)
          :drop -> acc
        end
      end)

    %{state | children: children}
  end

  defp maybe_update_child_visibility(child, visible?) do
    child =
      cond do
        child.visible == visible? ->
          child

        child.persistent ->
          case notify_child_visibility(child.pid, visible?) do
            {:noreply, _focused} -> %{child | visible: visible?}
            {:stop, _focused} -> :drop
          end

        true ->
          %{child | visible: visible?}
      end

    case child do
      :drop -> :drop
      child -> {:keep, child}
    end
  end

  defp notify_child_visibility(pid, true),
    do: Breeze.ChildServer.dispatch_info(pid, {:route_visibility, :visible})

  defp notify_child_visibility(pid, false),
    do: Breeze.ChildServer.dispatch_info(pid, {:route_visibility, :hidden})

  defp schedule_render(%{render_timer: nil, frame_delay_ms: delay} = state) do
    timer = Process.send_after(self(), :render_frame, delay)
    %{state | render_timer: timer}
  end

  defp schedule_render(state), do: state
end
