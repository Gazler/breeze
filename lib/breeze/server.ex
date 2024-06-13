defmodule Breeze.Term do
  defstruct [:view, :terminal, :reader, assigns: %{}]
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
    render(state)
    {:noreply, state}
  end

  def handle_info({reader, {:data, key}}, %{reader: reader} = state) do
    key =
      if String.starts_with?(key, Termite.Screen.escape_code()) do
        convert_key(String.trim_leading(key, Termite.Screen.escape_code()))
      else
        key
      end

    {:noreply, state} = state.view.handle_event(:ignore_me, %{"key" => key}, state)
    render(state)
    {:noreply, state}
  end

  def handle_info(message, state) do
    case state.view.handle_info(message, state) do
      {:noreply, state} ->
        render(state)
        {:noreply, state}

      {:stop, state} ->
        output =
          Termite.Screen.escape_sequence(:reset) <>
            Termite.Screen.escape_sequence(:screen_clear) <>
            Termite.Screen.escape_sequence(:cursor_show) <>
            Termite.Screen.escape_sequence(:screen_alt_exit)

        # TODO: synchronous write
        Termite.Terminal.write(state.terminal, output)
        :timer.sleep(100)
        System.halt()
    end
  end

  defp render(state) do
    output =
      Termite.Screen.escape_sequence(:reset) <> Termite.Screen.escape_sequence(:screen_clear)

    view_outout =
      case state.view.render(state.assigns) do
        out when is_binary(out) -> out
        out when is_list(out) -> reduce_render(out, "")
      end

    Termite.Terminal.write(state.terminal, output <> view_outout)
  end

  defp reduce_render([], acc) do
    acc
  end

  defp reduce_render([bin | rest], acc) when is_binary(bin) do
    reduce_render(rest, acc <> bin)
  end

  defp reduce_render([{x, y, out} | rest], acc) do
    output =
      Termite.Screen.escape_sequence(:cursor_move, [x, y]) <> out

    reduce_render(rest, acc <> output)
  end

  defp convert_key("A"), do: "ArrowUp"
  defp convert_key("B"), do: "ArrowDown"
  defp convert_key("C"), do: "ArrowRight"
  defp convert_key("D"), do: "ArrowLeft"
end
