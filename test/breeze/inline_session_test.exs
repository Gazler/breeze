defmodule Breeze.InlineSessionTest do
  use ExUnit.Case, async: true

  import Breeze.TestSupport.ProcessHelpers, only: [start_server: 1]
  import Breeze.TestSupport.WaitUntil

  defmodule Adapter do
    @behaviour Termite.Terminal.Adapter

    def start(opts) do
      {:ok,
       %{reader: make_ref(), recipient: self(), owner: opts[:owner], geometry: opts[:geometry]}}
    end

    def reader(terminal), do: {:ok, terminal.reader}
    def resize(terminal), do: Agent.get(terminal.geometry, & &1.size)

    def write(terminal, content) do
      send(terminal.owner, {:terminal_write, content})

      Agent.update(terminal.geometry, fn geometry ->
        case {Map.get(geometry, :track_cursor?, false),
              Regex.run(~r/\e\[(\d+);1H\e\[\?2026l$/, content)} do
          {true, [_, row]} -> %{geometry | cursor: {String.to_integer(row), 1}}
          _ -> geometry
        end
      end)

      if content == "\e[6n" do
        case Agent.get(terminal.geometry, & &1.cursor) do
          nil ->
            :ok

          {row, col} ->
            send(terminal.recipient, {terminal.reader, {:data, "\e[#{row};"}})
            send(terminal.recipient, {terminal.reader, {:data, "#{col}R"}})
        end
      end

      {:ok, terminal}
    end
  end

  defmodule View do
    use Breeze.View

    def mount(opts, term), do: {:ok, assign(term, owner: opts[:owner], lines: ["ready"])}

    def render(assigns) do
      ~H"""
      <box>
        <box :for={line <- @lines}>{line}</box>
      </box>
      """
    end

    def handle_info({:lines, lines}, term), do: {:noreply, assign(term, lines: lines)}

    def handle_info(:resize, term) do
      send(term.assigns.owner, {:resized, term.terminal.size})
      {:noreply, term}
    end

    def handle_info(_, term), do: {:noreply, term}

    def handle_event(_, %{"key" => "p"}, term),
      do: {:noreply, append_scrollback(term, "completed")}

    def handle_event(_, %{"key" => "a"}, term),
      do: {:noreply, term |> append_scrollback("atomic history") |> assign(lines: ["updated"])}

    def handle_event(_, %{"key" => "s"}, term),
      do: {:noreply, append_scrollback(term, "quiet history"), invalidate: false}

    def handle_event(_, %{"key" => "v"}, term),
      do: {:noreply, append_scrollback(term, IO.ANSI.format([:yellow, "callback color"], true))}

    def handle_event(_, %{"key" => "q"}, term),
      do: {:stop, append_scrollback(term, "finished")}

    def handle_event(_, %{"key" => "b"}, term) do
      term = append_scrollback(term, "queued first\nqueued second")
      send(term.assigns.owner, {:history_queued, self()})

      receive do
        :continue -> {:noreply, assign(term, lines: ["updated"])}
      end
    end

    def handle_event(_, event, term) do
      send(term.assigns.owner, {:input, event})
      {:noreply, term}
    end
  end

  defp session(opts \\ []) do
    {:ok, geometry} =
      start_supervised({Agent, fn -> %{size: %{width: 30, height: 10}, cursor: {5, 1}} end})

    {:ok, session} =
      start_server(
        Keyword.merge(
          [
            view: View,
            start_opts: [owner: self()],
            screen: :inline,
            enhanced_keyboard: false,
            terminal_opts: [adapter: Adapter, owner: self(), geometry: geometry],
            internal: [at_exit_register: fn _ -> :ok end]
          ],
          opts
        )
      )

    runtime = Breeze.Server.runtime_pid(session)
    state = :sys.get_state(runtime)
    {session, runtime, state.terminal_state.reader, geometry}
  end

  test "startup, redraw and stop preserve earlier terminal output" do
    {session, runtime, reader, _} = session()
    initial = writes()
    assert initial =~ "\e[5;1Hready"
    assert :sys.get_state(runtime).terminal_state.inline.height == 1
    refute_cleared(initial)

    send(session, {reader, {:event, {:lines, ["one", "two", "three"]}}})
    wait_until(fn -> :sys.get_state(runtime).terminal_state.inline.height == 3 end)
    assert writes() =~ "\e[7;1Hthree"

    send(session, {reader, {:event, {:lines, ["short"]}}})
    wait_until(fn -> :sys.get_state(runtime).terminal_state.inline.height == 1 end)
    shrunk = writes()
    assert shrunk =~ "\e[6;1H\e[6;1H\e[K"
    refute_cleared(shrunk)

    Breeze.Server.stop(session)
    stopped = writes()
    assert String.ends_with?(stopped, "\e[0m\r\n")
    refute_cleared(stopped)
  end

  test "external and callback history writes redraw the live region below output" do
    {session, runtime, reader, _} = session(inline_height: 2)
    writes()
    assert :ok = Breeze.Server.append_scrollback(session, "first\nsecond")
    state = :sys.get_state(runtime)
    assert state.terminal_state.inline.top == 6
    assert state.terminal_state.inline.height == 2
    assert state.terminal_state.terminal.size.height == 2
    output = writes()
    assert output =~ "first\r\nsecond\r\n"
    assert output =~ "\e[7;1Hready"
    refute_cleared(output)

    send(session, {reader, {:data, "p"}})

    wait_until(fn ->
      inline = :sys.get_state(runtime).terminal_state.inline
      inline.top == 7 and inline.pending_output == ""
    end)

    assert writes() =~ "completed\r\n"

    ref = Process.monitor(session)
    send(session, {reader, {:data, "q"}})
    assert_receive {:DOWN, ^ref, :process, ^session, :normal}
    output = writes()
    assert output =~ "finished\r\n"
    refute_cleared(output)
  end

  test "resize reanchors drawing and keeps fixed height bounded by the terminal" do
    {session, runtime, reader, geometry} = session(inline_height: 4)
    writes()
    Agent.update(geometry, fn _ -> %{size: %{width: 15, height: 3}, cursor: {3, 1}} end)
    send(session, {reader, {:signal, :winch}})
    assert_receive {:resized, %{width: 15, height: 3}}, 1000
    state = :sys.get_state(runtime)
    assert state.terminal_state.inline.top == 0
    assert state.terminal_state.inline.height == 3
    output = writes()
    assert output =~ "\e[1;1Hready"
    refute_cleared(output)
  end

  test "fullscreen sessions reject history writes" do
    {session, _, _, _} = session(screen: :fullscreen)
    assert Breeze.Server.append_scrollback(session, "history") == {:error, :not_inline}
  end

  test "external and callback history preserve ANSI colors from chardata" do
    {session, runtime, reader, _} = session()
    writes()
    content = IO.ANSI.format([:green, "first", :reset, "\n", :blue, "second"], true)
    assert :ok = Breeze.Server.append_scrollback(session, content)
    output = writes()
    assert output =~ "\e[32mfirst\e[0m\r\n\e[34msecond\e[0m\r\n"
    assert output =~ "\e[7;1Hready"

    send(session, {reader, {:data, "v"}})

    wait_until(fn ->
      inline = :sys.get_state(runtime).terminal_state.inline
      inline.top == 7 and not Breeze.Server.Inline.pending_output?(inline)
    end)

    output = writes()
    assert output =~ "\e[33mcallback color\e[0m\r\n"
    assert output =~ "\e[8;1Hready"
    refute_cleared(output)
  end

  test "external history closes hyperlinks before redrawing the live frame" do
    {session, _, _, _} = session()
    writes()

    assert :ok =
             Breeze.Server.append_scrollback(
               session,
               "\e]8;;https://hexdocs.pm/breeze/\aBreeze docs"
             )

    output = writes()
    assert output =~ "\e]8;;https://hexdocs.pm/breeze/\e\\Breeze docs\e]8;;\e\\\r\n"
    assert output =~ "\e[6;1Hready"
  end

  for cursor_reply? <- [true, false] do
    test "resize flushes queued callback history before querying the cursor (reply: #{cursor_reply?})" do
      {session, runtime, reader, geometry} = session()
      writes()
      send(session, {reader, {:data, "b"}})
      assert_receive {:history_queued, callback}

      wait_until(fn ->
        state = :sys.get_state(runtime)
        state.input.pending_ref != nil and state.terminal_state.inline.pending_output != ""
      end)

      Agent.update(geometry, fn geometry ->
        geometry
        |> Map.put(:track_cursor?, unquote(cursor_reply?))
        |> Map.put(:cursor, if(unquote(cursor_reply?), do: {5, 1}))
      end)

      send(session, {reader, {:signal, :winch}})
      assert_receive {:terminal_write, first_write}, 1000
      send(callback, :continue)
      assert first_write =~ "queued first\r\nqueued second\r\n"
      assert_receive {:terminal_write, "\e[6n"}, 1000
      assert_receive {:resized, %{width: 30, height: 10}}, 1000

      wait_until(fn ->
        state = :sys.get_state(runtime)

        is_nil(state.input.pending_ref) and state.frame.base_output =~ "updated" and
          state.terminal_state.inline.pending_output == ""
      end)

      inline = :sys.get_state(runtime).terminal_state.inline
      assert inline.top == if(unquote(cursor_reply?), do: 6, else: 9)
      output = writes()
      assert output =~ "\e[#{inline.top + 1};1Hupdated"
      refute output =~ "queued first"
      refute_cleared(first_write <> output)
    end
  end

  test "layout overrides preserve physical geometry at startup and after resize" do
    {session, runtime, reader, geometry} =
      session(
        internal: [
          at_exit_register: fn _ -> :ok end,
          terminal_size_override: fn size -> %{size | height: size.height - 1} end
        ]
      )

    state = :sys.get_state(runtime)
    assert state.terminal_state.inline.physical_size.height == 10
    assert state.terminal_state.terminal.size.height == 9
    writes()

    Agent.update(geometry, fn _ -> %{size: %{width: 20, height: 6}, cursor: {5, 1}} end)
    send(session, {reader, {:signal, :winch}})
    assert_receive {:resized, %{width: 20, height: 5}}, 1000
    state = :sys.get_state(runtime)
    assert state.terminal_state.inline.physical_size.height == 6
    assert state.terminal_state.inline.top == 4
    writes()

    send(session, {reader, {:event, {:lines, ["ready", "second"]}}})
    wait_until(fn -> :sys.get_state(runtime).terminal_state.inline.height == 2 end)
    assert :sys.get_state(runtime).terminal_state.inline.top == 4
    assert writes() =~ "\e[6;1Hsecond"

    send(session, {reader, {:event, {:lines, Enum.map(1..8, &"line #{&1}")}}})
    wait_until(fn -> :sys.get_state(runtime).terminal_state.inline.height == 5 end)
    output = writes()
    assert output =~ "line 5"
    refute output =~ "line 6"
  end

  test "external history arriving immediately after resize cannot block the cursor query" do
    {session, runtime, reader, geometry} = session(inline_height: 4)
    writes()
    Agent.update(geometry, fn _ -> %{size: %{width: 20, height: 10}, cursor: {5, 1}} end)

    # Queue both messages before the server can issue its cursor query.
    :ok = :sys.suspend(runtime)

    append =
      Task.async(fn ->
        send(session, {reader, {:signal, :winch}})
        Breeze.Server.append_scrollback(session, "external history")
      end)

    try do
      wait_until(fn ->
        {:messages, messages} = Process.info(runtime, :messages)

        Enum.any?(messages, fn
          {:"$gen_call", _from, {:append_scrollback, "external history"}} -> true
          _ -> false
        end)
      end)

      # The append caller is waiting, but the router must keep forwarding input.
      send(session, {reader, {:event, :after_append}})

      wait_until(fn ->
        {:messages, messages} = Process.info(runtime, :messages)
        {reader, {:event, :after_append}} in messages
      end)
    after
      :sys.resume(runtime)
    end

    assert Task.await(append) == :ok
    assert_receive {:resized, %{width: 20, height: 4}}, 1000
    assert :sys.get_state(runtime).terminal_state.inline.top == 5
    output = writes()
    assert output =~ "external history\r\n"
    refute output =~ String.duplicate("\n", 10)
    refute_cleared(output)
  end

  test "input arriving immediately after resize cannot block the cursor query" do
    {session, runtime, reader, geometry} = session(inline_height: 4)
    writes()
    Agent.update(geometry, fn _ -> %{size: %{width: 20, height: 10}, cursor: {5, 1}} end)
    send(session, {reader, {:signal, :winch}})
    send(session, {reader, {:data, "x"}})
    assert_receive {:resized, %{width: 20, height: 4}}, 1000
    assert_receive {:input, %{"key" => "x"}}, 1000
    assert :sys.get_state(runtime).terminal_state.inline.top == 4
    refute_cleared(writes())
  end

  test "history insertion and the new live frame are written as one synchronized update" do
    {session, runtime, reader, _} = session()
    writes()
    send(session, {reader, {:data, "a"}})

    wait_until(fn ->
      state = :sys.get_state(runtime)
      state.frame.base_output =~ "updated" and state.terminal_state.inline.pending_output == ""
    end)

    assert_receive {:terminal_write, payload}
    assert payload =~ "atomic history\r\n"
    assert payload =~ "updated"
    refute payload =~ "ready"
    assert String.starts_with?(payload, "\e[?2026h")
    assert String.ends_with?(payload, "\e[?2026l")
    refute_cleared(payload)
  end

  test "history still flushes when a callback disables invalidation" do
    {session, runtime, reader, _} = session()
    writes()
    send(session, {reader, {:data, "s"}})

    wait_until(fn ->
      state = :sys.get_state(runtime)
      state.terminal_state.inline.top == 5 and state.terminal_state.inline.pending_output == ""
    end)

    assert writes() =~ "quiet history\r\n"
  end

  defp refute_cleared(output) do
    refute output =~ "\e[2J"
    refute output =~ "\e[3J"
    refute output =~ "\e[?1049"
  end

  defp writes(acc \\ []) do
    receive do
      {:terminal_write, content} -> writes([content | acc])
    after
      5 -> acc |> Enum.reverse() |> IO.iodata_to_binary()
    end
  end
end
