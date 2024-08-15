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
    implicit_state: %{}
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
        Termite.Screen.run_escape_sequence(terminal, :cursor_hide)
      else
        terminal
      end

    reader = terminal.reader
    state = %{state | terminal: terminal, reader: reader}
    {:ok, state} = state.view.mount(start_opts, state)
    state = render(state)
    {:noreply, state}
  end

  @doc false
  def handle_info({reader, {:data, "\t"}}, %{reader: reader} = state) do
    index = Enum.find_index(state.focusables, &(&1 == state.focused))

    new_focused =
      if index do
        Enum.at(state.focusables, index + 1)
      else
        hd(state.focusables)
      end

    state = %{state | focused: new_focused}
    state = render(state)

    {:noreply, state}
  end

  def handle_info({reader, {:data, "\e[Z"}}, %{reader: reader} = state) do
    index = Enum.find_index(state.focusables, &(&1 == state.focused))

    new_focused =
      cond do
        index == 0 -> nil
        index == nil -> hd(Enum.reverse(state.focusables))
        true -> Enum.at(state.focusables, index - 1)
      end

    state = %{state | focused: new_focused}
    state = render(state)
    {:noreply, state}
  end

  def handle_info({reader, {:data, key}}, %{reader: reader} = state) do
    key =
      if String.starts_with?(key, Termite.Screen.escape_code()) do
        convert_key(String.trim_leading(key, Termite.Screen.escape_code()))
      else
        key
      end

    selected_implicit = Enum.find(state.implicit_state, fn {id, _el} -> id == state.focused end)

    {view_state, state} =
      if selected_implicit do
        {id, {mod, selected}} = selected_implicit

        element = Map.get(state.elements, id)

        {event, val} =
          case mod.handle_event(:ignore_me, %{"key" => key, "element" => element}, selected) do
            {{:change, event}, val} -> {event, val}
            {:noreply, val} -> {nil, val}
          end

        change = get_in(state.events, [id, :change])

        {view_state, state} =
          if event && change do
            handle_event(change, event, state)
          else
            {:noreply, state}
          end

        implicit_state = Map.put(state.implicit_state, id, {mod, val})
        {view_state, %{state | implicit_state: implicit_state}}
      else
        {:noreply, state}
      end

    case view_state == :stop || handle_event(:ignore_me, %{"key" => key}, state) do
      true -> stop(state)
      {:stop, state} -> stop(state)
      {:noreply, state} -> {:noreply, render(state)}
    end
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

  defp stop(state) do
    output =
      Termite.Screen.escape_sequence(:reset) <>
        Termite.Screen.escape_sequence(:screen_clear) <>
        Termite.Screen.escape_sequence(:cursor_show) <>
        Termite.Screen.escape_sequence(:screen_alt_exit)

    Termite.Terminal.write(state.terminal, output)
    System.halt()
  end

  defp render(state) do
    output =
      Termite.Screen.escape_sequence(:reset) <> Termite.Screen.escape_sequence(:screen_clear)

    {acc, %{content: view_output}} =
      Breeze.Renderer.render(state.view, state.assigns,
        focused: state.focused,
        implicit_state: state.implicit_state
      )

    Termite.Terminal.write(state.terminal, output <> view_output)

    last = map_size(acc.elements)

    elements = Enum.sort(acc.elements)

    dimensions =
      Enum.zip(elements, acc.dimensions)
      |> Enum.reduce(%{}, fn {{_, flags}, dims}, acc ->
        id = Keyword.get(flags, :id)
        if id, do: Map.put(acc, id, dims), else: acc
      end)

    {implicits, _, _, _} =
      elements
      |> Enum.reduce({%{}, [], nil, nil}, fn {idx, elem}, {acc, current, mod, last_id} ->
        elem = Map.new(elem) |> Map.delete(:focusable)
        {implicit, elem} = Map.pop(elem, :implicit)
        {id, elem} = Map.pop(elem, :id)
        {implicit_id, elem} = Map.pop(elem, :implicit_id)

        # TODO: delete all br elements

        cond do
          # Handle a single implicit box with no children
          last == 1 && implicit && id ->
            {add_implicit_item(acc, state, id, implicit, []), [], implicit, id}

          mod && (implicit || idx == last - 1) ->
            current = if implicit_id, do: [elem | current], else: current
            items = Enum.reverse(current)
            acc = add_implicit_item(acc, state, last_id, mod, items)

            # Handle an implicit box with no children as the last item
            acc =
              if implicit && id do
                add_implicit_item(acc, state, id, implicit, [])
              else
                acc
              end

            {acc, [], implicit, id}

          !mod && implicit ->
            {acc, current, implicit, id}

          implicit_id ->
            {acc, [elem | current], mod, last_id}

          true ->
            {acc, current, mod, last_id}
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

    %{
      state
      | elements: dimensions,
        focusables: acc.focusables,
        implicit_state: implicits,
        events: events
    }
  end

  defp convert_key("A"), do: "ArrowUp"
  defp convert_key("B"), do: "ArrowDown"
  defp convert_key("C"), do: "ArrowRight"
  defp convert_key("D"), do: "ArrowLeft"

  defp handle_event(change, event, state) do
    state.view.handle_event(change, event, state)
  end

  defp add_implicit_item(acc, state, id, mod, items) do
    last_state =
      case state.implicit_state[id] do
        {_mod, last_state} -> last_state
        _ -> %{}
      end

    Map.put(acc, id, {mod, mod.init(items, last_state)})
  end
end
