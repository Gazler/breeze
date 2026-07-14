defmodule Breeze.TestSupport.StorybookCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      import Breeze.TestSupport.WaitUntil
      import Breeze.TestSupport.StorybookHelpers

      alias Breeze.TestSupport.StorybookFakeAdapter, as: FakeAdapter
      alias Breeze.TestSupport.StorybookRecordingAdapter, as: RecordingAdapter
    end
  end
end

defmodule Breeze.TestSupport.StorybookFakeAdapter do
  @moduledoc false

  @behaviour Termite.Terminal.Adapter

  def start(_opts), do: {:ok, %{ref: make_ref(), size: %{width: 80, height: 24}}}
  def reader(term), do: {:ok, term.ref}
  def write(term, _str), do: {:ok, term}
  def resize(term), do: term.size
end

defmodule Breeze.TestSupport.StorybookRecordingAdapter do
  @moduledoc false

  @behaviour Termite.Terminal.Adapter

  def start(opts) do
    {:ok,
     %{
       ref: make_ref(),
       size: %{width: 80, height: 24},
       owner: Keyword.fetch!(opts, :owner)
     }}
  end

  def reader(term), do: {:ok, term.ref}

  def write(term, str) do
    send(term.owner, {:terminal_write, str})
    {:ok, term}
  end

  def resize(term), do: term.size
end

defmodule Breeze.TestSupport.StorybookHelpers do
  @moduledoc false

  import ExUnit.Assertions
  import Breeze.TestSupport.WaitUntil

  alias Breeze.TestSupport.StorybookRecordingAdapter, as: RecordingAdapter

  def select_story!(pid, story_id) do
    state = :sys.get_state(pid)
    stories = state.assigns.stories
    current = Enum.find_index(stories, &(&1.id == state.assigns.current_story_id))
    target = Enum.find_index(stories, &(&1.id == story_id))

    assert is_integer(current)
    assert is_integer(target)

    move_story!(pid, target - current)
    assert :sys.get_state(pid).assigns.current_story_id == story_id
  end

  def move_story!(_pid, 0), do: :ok

  def move_story!(pid, steps) do
    key = if steps > 0, do: "ArrowDown", else: "ArrowUp"

    1..abs(steps)
    |> Enum.each(fn _ ->
      assert {:noreply, "storybook-nav", true} = Breeze.ChildServer.dispatch_input(pid, key)
    end)
  end

  def drain_terminal_writes(writes \\ []) do
    receive do
      {:terminal_write, str} -> drain_terminal_writes([str | writes])
    after
      10 -> Enum.reverse(writes)
    end
  end

  def start_storybook_server!(file, opts \\ []) do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      [
        view: Breeze.Storybook,
        terminal: terminal,
        start_opts: [directory: "storybook", file: file]
      ]
      |> Keyword.merge(opts)
      |> Breeze.Server.start_app_link()

    ExUnit.Callbacks.on_exit(fn -> stop_server(pid) end)

    {terminal, pid}
  end

  def send_mouse(pid, reader, code, x, y) do
    send(pid, {reader, {:data, "\e[<#{code};#{x};#{y}M"}})
  end

  def stop_server(pid) do
    Breeze.TestSupport.ProcessHelpers.stop_gen_server(pid)
  end

  def wait_for_preview_child(pid, story_id) do
    %{module: expected_view} = Breeze.Storybook.Registry.story(story_id, "storybook")

    wait_until(
      fn ->
        state = :sys.get_state(pid)

        with %{pid: preview_pid, view: ^expected_view} <-
               Map.get(state.children, "storybook-preview"),
             %Breeze.Viewport{} = viewport <-
               Map.get(state.rendered.elements, "storybook-preview"),
             true <- Process.alive?(preview_pid) do
          {preview_pid, viewport}
        else
          _ -> false
        end
      end,
      100
    )
  end

  def patched_rows(writes, column) do
    pattern = ~r/\e\[(\d+);#{column}H/

    writes
    |> IO.iodata_to_binary()
    |> then(&Regex.scan(pattern, &1, capture: :all_but_first))
    |> Enum.map(fn [row] -> String.to_integer(row) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def redraw_or_full_viewport_patch?(writes, viewport) do
    payload = IO.iodata_to_binary(writes)

    String.contains?(payload, "\e[2J\e[H") or
      patched_rows(writes, viewport.left + 1) ==
        Enum.to_list((viewport.top + 1)..(viewport.top + viewport.height))
  end

  def await_terminal_writes(acc \\ []) do
    receive do
      {:terminal_write, str} -> drain_terminal_writes([str | acc])
    after
      200 -> flunk("expected terminal writes")
    end
  end
end
