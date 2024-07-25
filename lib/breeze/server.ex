defmodule Breeze.Term do
  defstruct [
    :view,
    :terminal,
    :reader,
    assigns: %{},
    focused: nil,
    focusables: [],
    events: %{},
    implicit_state: %{}
  ]
end

defmodule Breeze.Server do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    view = Keyword.fetch!(opts, :view)
    {:ok, %Breeze.Term{view: view}, {:continue, {:start, opts}}}
  end

  def handle_continue({:start, opts}, state) do
    start_opts = Keyword.get(opts, :start_opts, [])
    terminal = Termite.Terminal.start()

    terminal =
      if Keyword.get(opts, :hide_cursor) do
        Termite.Screen.run_escape_sequence(terminal, :cursor_hide)
      else
        terminal
      end

    reader = Termite.Terminal.reader(terminal)
    state = %{state | terminal: terminal, reader: reader}
    {:ok, state} = state.view.mount(start_opts, state)
    state = render(state)
    {:noreply, state}
  end

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

    state =
      if selected_implicit do
        {id, {mod, selected}} = selected_implicit
        {{:change, event}, val} = mod.handle_event(:ignore_me, %{"key" => key}, selected)
        change = get_in(state.events, [id, :change])

        state =
          if change do
            {:noreply, state} = state.view.handle_event(change, event, state)
            state
          end

        implicit_state = Map.put(state.implicit_state, id, {mod, val})
        %{state | implicit_state: implicit_state}
      else
        state
      end

    {:noreply, state} = state.view.handle_event(:ignore_me, %{"key" => key}, state)
    state = render(state)
    {:noreply, state}
  end

  def handle_info(message, state) do
    case state.view.handle_info(message, state) do
      {:noreply, state} ->
        state = render(state)
        {:noreply, state}

      {:stop, state} ->
        output =
          Termite.Screen.escape_sequence(:reset) <>
            Termite.Screen.escape_sequence(:screen_clear) <>
            Termite.Screen.escape_sequence(:cursor_show) <>
            Termite.Screen.escape_sequence(:screen_alt_exit)

        # TODO: synchronous write
        Termite.Terminal.write(state.terminal, output)
        :timer.sleep(1000)
        System.halt()
    end
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

    {implicits, _, _, _} =
      acc.elements
      |> Enum.sort()
      |> Enum.reduce({%{}, [], nil, nil}, fn {idx, elem}, {acc, current, mod, last_id} ->
        elem = Map.new(elem) |> Map.delete(:focusable)
        {implicit, elem} = Map.pop(elem, :implicit)
        {id, elem} = Map.pop(elem, :id)
        {implicit_id, elem} = Map.pop(elem, :implicit_id)

        # TODO: delete all br elements

        cond do
          mod && (implicit || idx == last - 1) ->
            last_state =
              case state.implicit_state[last_id] do
                {_mod, last_state} -> last_state
                _ -> %{}
              end

            current = if implicit_id, do: [elem | current], else: current

            items = Enum.reverse(current)
            {Map.put(acc, last_id, {mod, mod.init(items, last_state)}), [], implicit, id}

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

    %{state | focusables: acc.focusables, implicit_state: implicits, events: events}
  end

  defp convert_key("A"), do: "ArrowUp"
  defp convert_key("B"), do: "ArrowDown"
  defp convert_key("C"), do: "ArrowRight"
  defp convert_key("D"), do: "ArrowLeft"
end
