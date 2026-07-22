try do
  :ok = :logger.set_handler_config(:default, :level, :emergency)
rescue
  _ -> :ok
end

defmodule CrashHandlerExample do
  use Breeze.View

  @tick_ms 1_000

  def mount(_opts, term) do
    Process.send_after(self(), :tick, @tick_ms)
    {:ok, term |> assign(counter: 0) |> focus("boom")}
  end

  def render(assigns) do
    ~H"""
    <box class="w-screen h-screen">
      <box class="h-1 font-bold">Crash Handler Demo</box>
      <box class="h-1">
      </box>
      <box>
        <box id="boom" focusable class="rounded w-32 h-5 focus:border-4">
          <box>Press c to raise</box>
          <box>Counter {@counter}</box>
        </box>
        <box class="h-1">
        </box>
        <box>q quits, r restarts after a crash</box>
        <box class="h-1">
        </box>
        <live
          id="logs"
          view={Breeze.Logger}
          start_opts={[title: "Captured logs", width: 72, height: 12, min_level: :debug, max_lines: 40, clear_key: nil]}
        >
        </live>
      </box>
    </box>
    """
  end

  def handle_event(_, %{"key" => "c"}, _term) do
    run_request_preview!("POST", "/api/demo", %{counter: :not_an_integer})
  end

  def handle_event(_, %{"key" => "Enter"}, term) do
    {:noreply, assign(term, counter: term.assigns.counter + 1)}
  end

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(:tick, term) do
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, assign(term, counter: term.assigns.counter + 1)}
  end

  def handle_info(_, term), do: {:noreply, term}

  defp run_request_preview!(method, path, params) do
    result =
      %{method: method, path: path, params: params}
      |> load_fixture_request!()

    {:ok, result}
  end

  defp load_fixture_request!(request) do
    request = Map.put(request, :fixture, "examples/crash_handler/request.json")
    result = authorize_preview!(request)
    Map.put(result, :fixture_loaded?, true)
  end

  defp authorize_preview!(request) do
    request = Map.put(request, :principal, %{id: 42, role: :developer})
    result = decode_preview_payload!(request)
    Map.put(result, :authorized?, true)
  end

  defp decode_preview_payload!(%{params: params} = request) do
    request = Map.put(request, :counter, Map.fetch!(params, :counter))
    result = render_preview_response!(request)
    Map.put(result, :decoded?, true)
  end

  defp render_preview_response!(request) do
    if is_integer(request.counter) do
      %{status: 200, body: "counter=#{request.counter}"}
    else
      raise """
      crash demo could not render request preview

      method=#{request.method}
      path=#{request.path}
      fixture=#{request.fixture}
      principal=#{inspect(request.principal)}
      counter=#{inspect(request[:counter])}
      """
    end
  end
end

Breeze.Example.run(
  view: CrashHandlerExample,
  hide_cursor: true,
  global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
)
