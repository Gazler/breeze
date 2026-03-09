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
    children: %{}
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
    {:ok, %Breeze.Term{view: view}, {:continue, {:start, opts}}}
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
        {id, {mod, selected}} = selected_implicit
        dispatch_implicit_event(id, mod, selected, %{"key" => key}, state)
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
    {state, _live_ids, {acc, _box}} = render_view(state, state.implicit_state)

    last = map_size(acc.elements)

    elements = Enum.sort(acc.elements)

    {implicits, _, _, _, _} =
      elements
      |> Enum.reduce({%{}, [], nil, nil, %{}}, fn {idx, elem},
                                                  {acc, current, mod, last_id, root_attrs} ->
        elem = Map.new(elem) |> Map.delete(:focusable)
        {implicit, elem} = Map.pop(elem, :implicit)
        {id, elem} = Map.pop(elem, :id)
        {implicit_owner, elem} = Map.pop(elem, :implicit_owner)

        # TODO: delete all br elements

        cond do
          # Handle a single implicit box with no children
          last == 1 && implicit && id ->
            {add_implicit_item(acc, state, id, implicit, [], elem), [], implicit, id, elem}

          mod && (implicit || idx == last - 1) ->
            current = if implicit_owner, do: [elem | current], else: current
            items = Enum.reverse(current)
            acc = add_implicit_item(acc, state, last_id, mod, items, root_attrs)

            # Handle an implicit box with no children as the last item
            acc =
              if implicit && id do
                add_implicit_item(acc, state, id, implicit, [], elem)
              else
                acc
              end

            {acc, [], implicit, id, elem}

          !mod && implicit ->
            {acc, current, implicit, id, elem}

          implicit_owner ->
            {acc, [elem | current], mod, last_id, root_attrs}

          true ->
            {acc, current, mod, last_id, root_attrs}
        end
      end)

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

    {state, live_ids, {final_acc, %{content: output}}} =
      render_view(%{state | focused: focused}, implicits)

    {state, live_ids} = prune_children(state, live_ids)
    implicits = prune_implicit_state(implicits, live_ids)

    screen_height = state.terminal.size.height
    output_lines = length(String.split(output, "\n"))
    trailing = String.duplicate("\n\e[K", max(screen_height - output_lines, 0))
    output = "\e[K" <> String.replace(output, "\n", "\n\e[K") <> trailing
    terminal = Termite.Terminal.write(state.terminal, "\e[H" <> output)

    final_elements = Enum.sort(final_acc.elements)

    dimensions =
      Enum.zip(final_elements, final_acc.dimensions)
      |> Enum.reduce(%{}, fn {{_, flags}, dims}, acc ->
        id = Keyword.get(flags, :id)

        if id do
          Map.put(acc, id, Breeze.Viewport.from_dimensions(dims))
        else
          acc
        end
      end)

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

  defp render_view(state, implicit_state) do
    Process.put(:breeze_live_requested, [])
    Process.put(:breeze_live_missing, [])

    result =
      Breeze.Renderer.render(state.view, state.assigns,
        focused: state.focused,
        implicit_state: implicit_state,
        terminal: state.terminal,
        live_view: fn attrs, opts -> render_live_child(attrs, opts, state, implicit_state) end
      )

    live_ids =
      Process.delete(:breeze_live_requested)
      |> List.wrap()
      |> Enum.reverse()

    missing =
      Process.delete(:breeze_live_missing)
      |> List.wrap()
      |> Enum.reverse()

    case ensure_children(state, missing) do
      {state, true} -> render_view(state, implicit_state)
      {state, false} -> {state, live_ids, result}
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

  defp dispatch_implicit_event(id, mod, implicit, payload, state, visited \\ MapSet.new()) do
    if MapSet.member?(visited, id) do
      {:noreply, false, state}
    else
      element = Map.get(state.elements, id)
      payload = Map.put(payload, "element", element)

      case mod.handle_event(:ignore_me, payload, implicit) do
        {{:change, event}, val} ->
          change = get_in(state.events, [id, :change])
          state = put_implicit_state(state, id, mod, val)

          {view_state, state} =
            if event && change do
              route_event(id, change, event, state)
            else
              {:noreply, state}
            end

          {view_state, true, state}

        {{:delegate, target_id}, val} ->
          state = put_implicit_state(state, id, mod, val)

          case Map.get(state.implicit_state, target_id) do
            {target_mod, target_state} ->
              dispatch_implicit_event(
                target_id,
                target_mod,
                target_state,
                payload,
                state,
                MapSet.put(visited, id)
              )

            nil ->
              {:noreply, false, state}
          end

        {:noreply, val} ->
          state = put_implicit_state(state, id, mod, val)
          {:noreply, false, state}
      end
    end
  end

  defp put_implicit_state(state, id, mod, implicit) do
    implicit_state = Map.put(state.implicit_state, id, {mod, implicit})
    %{state | implicit_state: implicit_state}
  end

  defp add_implicit_item(acc, state, id, mod, items, root_attrs) do
    last_state =
      case state.implicit_state[id] do
        {_mod, last_state} -> last_state
        _ -> %{}
      end

    element = Map.get(state.elements, id)
    last_state = if element, do: Map.put(last_state, :__element__, element), else: last_state

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

  defp render_live_child(attrs, opts, state, implicit_state) do
    id = fetch_live_attr!(attrs, :id)
    full_id = live_id(Keyword.get(opts, :live_prefix), id)
    put_process_list(:breeze_live_requested, full_id)

    case Map.get(state.children, full_id) do
      nil ->
        put_process_list(:breeze_live_missing, {full_id, attrs})
        :missing

      %{pid: pid} ->
        local_focused = strip_live_prefix(state.focused, full_id)
        local_implicit_state = child_implicit_state(implicit_state, full_id)

        {:ok, child_acc, child_box} =
          Breeze.ChildServer.render(pid,
            focused: local_focused,
            implicit_state: local_implicit_state,
            terminal: state.terminal,
            live_prefix: full_id,
            live_view: fn child_attrs, child_opts ->
              render_live_child(child_attrs, child_opts, state, implicit_state)
            end
          )

        {:rendered, full_id, child_acc, child_box}
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
    {:ok, pid} = Breeze.ChildServer.start(view: view, start_opts: start_opts, terminal: terminal)
    ref = Process.monitor(pid)
    %{pid: pid, ref: ref, view: view}
  end

  defp maybe_take_child_focus(%{focused: nil} = state, id, pid) do
    case Breeze.ChildServer.snapshot(pid) do
      %{focused: nil} -> state
      %{focused: focused} -> %{state | focused: namespace_live_id(id, focused)}
    end
  end

  defp maybe_take_child_focus(state, _id, _pid), do: state

  defp prune_children(state, live_ids) do
    live_ids = MapSet.new(live_ids)

    {keep, drop} =
      Enum.split_with(state.children, fn {id, _child} -> MapSet.member?(live_ids, id) end)

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

  defp prune_implicit_state(implicit_state, live_ids) do
    Enum.reduce(implicit_state, %{}, fn {id, value}, acc ->
      if keep_implicit_id?(id, live_ids), do: Map.put(acc, id, value), else: acc
    end)
  end

  defp keep_implicit_id?(id, live_ids) do
    not String.contains?(id, "::") or
      Enum.any?(live_ids, fn live_id ->
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

  defp put_process_list(key, value) do
    Process.put(key, [value | List.wrap(Process.get(key))])
  end
end
