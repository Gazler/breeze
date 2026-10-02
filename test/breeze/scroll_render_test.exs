defmodule Breeze.ScrollRenderTest do
  use ExUnit.Case, async: true
  import Breeze.TestSupport.ProcessHelpers
  alias Breeze.RuntimeTest.RecordingAdapter

  defmodule View do
    use Breeze.View
    def mount(_, term), do: {:ok, assign(term, mode: nil, offset: 0)}

    def handle_info({:change, mode, offset}, term) do
      {:noreply, assign(term, mode: mode, offset: offset)}
    end

    defp rows(offset),
      do:
        Enum.map_join(1..20, "\n", fn n -> String.pad_trailing("line #{n + offset} ", 75, ".") end)

    def render(assigns) do
      ~H"""
      <box id="shell" br-update={@mode} class="w-full h-full">{rows(@offset)}</box>
      """
    end
  end

  defmodule RepeatedView do
    use Breeze.View
    def mount(_, term), do: {:ok, assign(term, offset: 0)}
    def handle_info(:scroll, term), do: {:noreply, assign(term, offset: term.assigns.offset + 1)}

    defp rows(offset) do
      rows =
        Enum.map(1..15, &String.pad_trailing("line #{&1}", 75, ".")) ++
          List.duplicate(String.duplicate("x", 75), 5)

      (Enum.drop(rows, offset) ++ List.duplicate(String.duplicate("x", 75), offset))
      |> Enum.join("\n")
    end

    def render(assigns) do
      ~H"""
      <box br-update="scroll" class="w-full h-full">{rows(@offset)}</box>
      """
    end
  end

  defmodule ColorView do
    use Breeze.View
    def mount(_, term), do: {:ok, assign(term, mode: nil, color: 200)}

    def handle_info({:change, mode, color}, term),
      do: {:noreply, assign(term, mode: mode, color: color)}

    defp content(color),
      do:
        "\e[48;2;10;20;30;38;2;#{color};#{color};#{color}mtext" <>
          String.duplicate(" ", 70) <> "\e[0m"

    def render(assigns) do
      ~H"""
      <box class="w-full h-full">
        <box br-update={@mode}>Scroll opt-in</box>
        <box>{content(@color)}</box>
      </box>
      """
    end
  end

  test "any scroll container enables color cell patches, and removing it restores row output" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    {:ok, pid} = start_app_server(view: ColorView, terminal: terminal)
    view_pid = :sys.get_state(pid).view_pid
    drain()

    send(view_pid, {:change, nil, 100})
    assert_receive {:terminal_write, baseline}, 1000
    assert baseline =~ String.duplicate(" ", 70)

    send(view_pid, {:change, "scroll", 200})
    assert_receive {:terminal_write, optimized}, 1000
    assert byte_size(optimized) < byte_size(baseline)
    refute optimized =~ String.duplicate(" ", 70)

    send(view_pid, {:change, nil, 100})
    assert_receive {:terminal_write, restored}, 1000
    assert restored == baseline
  end

  defmodule ParentView do
    use Breeze.View
    def mount(_, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box class="w-full h-full">
        <live id="child" view={Breeze.ScrollRenderTest.View}>
        </live>
      </box>
      """
    end
  end

  test "identical consecutive scrolling payloads are both sent, including anonymous containers" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    {:ok, pid} = start_app_server(view: RepeatedView, terminal: terminal)
    view_pid = :sys.get_state(pid).view_pid
    drain()
    send(view_pid, :scroll)
    assert_receive {:terminal_write, first}, 1000
    assert first =~ "\e[1S"
    send(view_pid, :scroll)
    assert_receive {:terminal_write, second}, 1000
    assert first == second
  end

  test "live children can add and remove scroll eligibility during invalidation" do
    id = {__MODULE__, make_ref()}
    :ok = :telemetry.attach(id, [:breeze, :frame, :written], &__MODULE__.handle_frame/4, self())
    on_exit(fn -> :telemetry.detach(id) end)
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    {:ok, pid} = start_app_server(view: ParentView, terminal: terminal)
    child_pid = :sys.get_state(pid).children["child"].pid
    drain()
    send(child_pid, {:change, "scroll", 1})
    assert_receive {:frame_written, %{bytes: bytes}, %{server: ^pid, mode: :scroll}}, 1000
    assert_receive {:terminal_write, payload}, 1000
    assert bytes == byte_size(payload)
    send(child_pid, {:change, nil, 2})
    assert_receive {:frame_written, _, %{server: ^pid, mode: :default}}, 1000
    assert_receive {:terminal_write, _}, 1000
    send(child_pid, {:change, nil, 3})
    assert_receive {:frame_written, %{bytes: bytes}, %{server: ^pid, path: :child_patch}}, 1000
    assert_receive {:terminal_write, payload}, 1000
    assert bytes == byte_size(payload)
  end

  def handle_frame(_event, measurements, metadata, owner) do
    send(owner, {:frame_written, measurements, metadata})
  end

  test "container opt-in can be toggled, with telemetry reporting actual writes" do
    id = {__MODULE__, make_ref()}
    :ok = :telemetry.attach(id, [:breeze, :frame, :written], &__MODULE__.handle_frame/4, self())
    on_exit(fn -> :telemetry.detach(id) end)
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    {:ok, pid} = start_app_server(view: View, terminal: terminal)
    view_pid = :sys.get_state(pid).view_pid
    assert_receive {:frame_written, %{bytes: initial_bytes}, %{server: ^pid}}, 1000
    assert initial_bytes > 0
    drain()

    send(view_pid, {:change, "scroll", 1})

    assert_receive {:frame_written, %{bytes: bytes, baseline_bytes: baseline},
                    %{server: ^pid, mode: :scroll}},
                   1000

    assert_receive {:terminal_write, payload}, 1000
    assert bytes == byte_size(payload)
    assert bytes < baseline
    assert payload =~ "\e[1S"

    send(view_pid, {:change, nil, 2})

    assert_receive {:frame_written, %{bytes: bytes, baseline_bytes: bytes},
                    %{server: ^pid, mode: :default}},
                   1000

    assert_receive {:terminal_write, payload}, 1000
    assert bytes == byte_size(payload)
    refute payload =~ "\e[1S"
  end

  defp drain do
    receive do
      {:terminal_write, _} -> drain()
      {:frame_written, _, _} -> drain()
    after
      0 -> :ok
    end
  end
end
