defmodule Breeze.TestSupport.LiveViewCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Breeze.{ChildServer, Renderer, Template}

      alias Breeze.LiveViewTest.{
        AlternateChild,
        AnimatedChild,
        AssignEchoChild,
        BufferedScrollView,
        CounterChild,
        CrashingView,
        CustomErrorView,
        DebugPaneRoot,
        DebugToggleRoot,
        DecoratedDebugChild,
        DecoratedDebugRoot,
        DualLiveExample,
        FakeAdapter,
        FakeWatcher,
        FastDecoration,
        FasterDecorationRoot,
        FocusableLiveRootExample,
        FocusedChild,
        GrowingRoot,
        HeaderedLiveChild,
        HeaderedLiveRoot,
        InlineLivePatchRoot,
        KeybindingChild,
        KeybindingErrorView,
        KeybindingFooterRoot,
        LiveAssignsRoot,
        LiveThenSiblingExample,
        MouseScrollLiveParent,
        NestedReloadChild,
        NestedReloadLeaf,
        ParentLiveExample,
        PersistentToggleRoot,
        PrivateUseGlyphRoot,
        RecordingAdapter,
        ReloadableView,
        ReloadConfigView,
        ReloadStateView,
        RenderOnlyChild,
        ResizeAdapter,
        RootCounterChild,
        RootReloadWithNestedChild,
        SnapshotCrashingChild,
        SnapshotCrashingRoot,
        SpinnerChild,
        SwitchableLiveRoot,
        ThemeBranchLiveChild,
        ThemeLeafLiveChild,
        ThemeSwitchingParent
      }

      import ExUnit.CaptureLog
    end
  end
end

defmodule Breeze.TestSupport.LiveViewHelpers do
  @moduledoc false

  import ExUnit.Assertions

  def drain_terminal_writes(writes \\ []) do
    receive do
      {:terminal_write, str} -> drain_terminal_writes([str | writes])
    after
      10 -> Enum.reverse(writes)
    end
  end

  def wait_until(fun, attempts \\ 20)

  def wait_until(fun, attempts) when attempts > 0 do
    case fun.() do
      false ->
        Process.sleep(10)
        wait_until(fun, attempts - 1)

      nil ->
        Process.sleep(10)
        wait_until(fun, attempts - 1)

      value ->
        value
    end
  end

  def wait_until(_fun, 0), do: flunk("condition not met")

  def wheel_event(button, bounds) do
    {x, y} = mouse_center(bounds)

    %{
      "mouse" => %{
        button: button,
        action: :press,
        modifiers: [],
        x: x,
        y: y
      }
    }
  end

  def mouse_center(bounds) do
    {div(bounds.left + bounds.right, 2) + 1, div(bounds.top + bounds.bottom, 2) + 1}
  end
end
