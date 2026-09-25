defmodule Breeze.Clipboard.SessionTest do
  use ExUnit.Case, async: true
  import Breeze.TestSupport.ProcessHelpers
  import Breeze.TestSupport.WaitUntil

  defmodule Adapter do
    @behaviour Termite.Terminal.Adapter
    def start(opts), do: {:ok, %{reader: make_ref(), owner: Keyword.fetch!(opts, :owner)}}
    def reader(state), do: {:ok, state.reader}
    def resize(_), do: %{width: 80, height: 24}

    def write(state, data) do
      send(state.owner, {:terminal_write, state.reader, IO.iodata_to_binary(data)})
      {:ok, state}
    end
  end

  defmodule Leaf do
    use Breeze.View
    def mount(_, term), do: {:ok, term}
    def render(assigns), do: ~H"<box>leaf {@breeze.clipboard.osc52}</box>"
    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule Branch do
    use Breeze.View
    def mount(_, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box>
        <box>branch {@breeze.clipboard.osc52}</box>
        <live id="leaf" view={Breeze.Clipboard.SessionTest.Leaf}>
        </live>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule Root do
    use Breeze.View

    def mount(_, term),
      do:
        {:ok,
         assign(term, keys: [], late: false, mounted_clipboard: term.assigns.breeze.clipboard)}

    def render(assigns) do
      ~H"""
      <box>
        <box>root {@breeze.clipboard.osc52}</box>
        <live id="branch" view={Breeze.Clipboard.SessionTest.Branch}>
        </live>
        <live :if={@late} id="late" view={Breeze.Clipboard.SessionTest.Leaf}>
        </live>
      </box>
      """
    end

    def handle_event(_, %{"key" => "!"}, _term), do: raise("clipboard test crash")

    def handle_event(_, %{"key" => key}, term),
      do:
        {:noreply,
         assign(term, keys: term.assigns.keys ++ [key], late: term.assigns.late or key == "n")}

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defp start_session do
    owner = self()

    {:ok, router} =
      start_input_router(
        view: Root,
        terminal_opts: [adapter: Adapter, owner: owner],
        internal: [
          clipboard_probe_timer: fn pid, message, delay ->
            send(owner, {:probe_timer, pid, message, delay})
          end
        ]
      )

    runtime = Breeze.Server.runtime_pid(router)
    reader = :sys.get_state(router).reader
    assert_receive {:probe_timer, ^router, :clipboard_probe_timeout, 250}, 1_000
    assert_receive {:terminal_write, ^reader, "\e[c"}, 1_000
    {router, runtime, reader}
  end

  defp metadata(runtime), do: Breeze.ChildServer.metadata(:sys.get_state(runtime).view_pid)

  test "two terminal connections have independent results and share only within their views" do
    {first, runtime, reader} = start_session()
    {second, other_runtime, other_reader} = start_session()
    assert metadata(runtime).assigns.mounted_clipboard == %{osc52: :unknown, supported: false}
    send(first, {other_reader, {:data, "\e[?62;52c"}})
    assert metadata(runtime).assigns.breeze.clipboard == %{osc52: :unknown, supported: false}
    send(first, {reader, {:data, "x\e[?62;"}})
    send(first, {reader, {:data, "52cn"}})

    wait_until(fn ->
      metadata(runtime).assigns.breeze.clipboard == %{osc52: :supported, supported: true}
    end)

    wait_until(fn -> :sys.get_state(runtime).frame.base_output =~ "leaf supported" end)
    wait_until(fn -> metadata(runtime).assigns.keys == ["x", "n"] end)
    wait_until(fn -> Map.has_key?(:sys.get_state(runtime).children, "late") end)

    assert metadata(other_runtime).assigns.breeze.clipboard == %{
             osc52: :unknown,
             supported: false
           }

    assert :sys.get_state(second).clipboard_probe.clipboard == %{
             osc52: :unknown,
             supported: false
           }

    state = :sys.get_state(runtime)
    assert state.terminal_state.clipboard.capabilities == %{osc52: :supported, supported: true}

    for {_id, child} <- state.children do
      assert Breeze.ChildServer.metadata(child.pid).assigns.breeze.clipboard == %{
               osc52: :supported,
               supported: true
             }
    end
  end

  test "fallback probe completes and timeout stays unknown without swallowing normal input" do
    {router, runtime, reader} = start_session()
    send(router, {reader, {:data, "\e[?62;22c"}})
    assert_receive {:terminal_write, ^reader, "\eP+q4d73\e\\"}, 1_000
    encoded = Base.encode16("\e]52;%p1%s;%p2%s\a")
    send(router, {reader, {:data, "\eP1+r4d73=" <> encoded <> "\e\\"}})

    wait_until(fn ->
      metadata(runtime).assigns.breeze.clipboard == %{osc52: :supported, supported: true}
    end)

    {other, other_runtime, other_reader} = start_session()
    send(other, :clipboard_probe_timeout)
    assert :sys.get_state(other).clipboard_probe.phase == :done
    send(other, {other_reader, {:data, "\e[?62;52cx"}})
    wait_until(fn -> metadata(other_runtime).assigns.keys == ["x"] end)

    assert metadata(other_runtime).assigns.breeze.clipboard == %{
             osc52: :unknown,
             supported: false
           }
  end

  test "restoring a view snapshot cannot copy another terminal's capability" do
    {router, runtime, reader} = start_session()
    send(router, {reader, {:data, "\e[?62;52c"}})

    wait_until(fn ->
      metadata(runtime).assigns.breeze.clipboard == %{osc52: :supported, supported: true}
    end)

    {:ok, snapshot} = Breeze.Runtime.capture_state(runtime)

    {_other_router, other_runtime, _other_reader} = start_session()
    assert :ok = Breeze.Runtime.replace_state(other_runtime, snapshot)

    assert metadata(other_runtime).assigns.breeze.clipboard == %{
             osc52: :unknown,
             supported: false
           }

    assert :sys.get_state(other_runtime).frame.base_output =~ "leaf unknown"
  end

  test "probe result survives a crashed view and is present on restart" do
    ExUnit.CaptureLog.capture_log(fn ->
      {router, runtime, reader} = start_session()
      send(router, {reader, {:data, "!"}})
      wait_until(fn -> not is_nil(:sys.get_state(runtime).crash) end)
      send(router, {reader, {:data, "\e[?62;52c"}})

      wait_until(fn ->
        :sys.get_state(runtime).terminal_state.clipboard.capabilities == %{
          osc52: :supported,
          supported: true
        }
      end)

      send(router, {reader, {:data, "r"}})
      wait_until(fn -> is_nil(:sys.get_state(runtime).crash) end)
      assert metadata(runtime).assigns.breeze.clipboard == %{osc52: :supported, supported: true}
      assert metadata(runtime).assigns.mounted_clipboard == %{osc52: :supported, supported: true}
    end)
  end
end
