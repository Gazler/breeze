defmodule Breeze.BlocksTest do
  use ExUnit.Case, async: true

  alias Breeze.Blocks
  alias Breeze.ChildServer

  defmodule UnderlineTabsExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.tabs id="tabs" selected="overview" variant="underline" style="width-24 height-5">
        <:tab value="overview" label="Overview">
          <box>Overview body</box>
        </:tab>
        <:tab value="details" label="Details">
          <box>Details body</box>
        </:tab>
      </.tabs>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule HighlightTabsExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.tabs id="tabs" selected="overview" highlight="error" style="width-24 height-5">
        <:tab value="overview" label="Overview">
          <box>Overview body</box>
        </:tab>
        <:tab value="details" label="Details">
          <box>Details body</box>
        </:tab>
      </.tabs>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule PerTabHighlightTabsExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.tabs id="tabs" selected="details" highlight="accent" style="width-24 height-5">
        <:tab value="overview" label="Overview">
          <box>Overview body</box>
        </:tab>
        <:tab value="details" label="Details" highlight="error">
          <box>Details body</box>
        </:tab>
      </.tabs>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  describe "merge_class/2" do
    test "matches merge_style semantics" do
      assert Blocks.merge_class("border width-24 height-8", "width-32 bg-4") ==
               "border width-32 height-8 bg-4"
    end
  end

  describe "merge_style/2" do
    test "nil override returns default unchanged" do
      assert Blocks.merge_style("border width-24", nil) == "border width-24"
    end

    test "empty string override returns default unchanged" do
      assert Blocks.merge_style("border width-24", "") == "border width-24"
    end

    test "override replaces a numeric-suffixed token" do
      assert Blocks.merge_style("border width-24 height-8", "width-32") ==
               "border width-32 height-8"
    end

    test "override replaces a non-numeric-suffixed token" do
      assert Blocks.merge_style("border overflow-scroll", "overflow-hidden") ==
               "border overflow-hidden"
    end

    test "new token from override is appended" do
      assert Blocks.merge_style("border width-24", "bg-4") == "border width-24 bg-4"
    end

    test "state-prefixed tokens are matched by their full prefix" do
      assert Blocks.merge_style("border focus:border-3", "focus:border-2") ==
               "border focus:border-2"
    end

    test "multiple overrides are applied in one call" do
      assert Blocks.merge_style(
               "border width-24 height-8 overflow-scroll focus:border-3",
               "width-32 focus:border-2"
             ) ==
               "border width-32 height-8 overflow-scroll focus:border-2"
    end
  end

  test "tabs supports an underline variant" do
    {:ok, pid} = ChildServer.start(view: UnderlineTabsExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "tabs", implicit_state: %{})

    assert box.content =~ "Overview"
    assert box.content =~ "Details"
    assert box.content =~ ~r/\e\[[0-9;]*38;5;4m/
    assert box.content =~ "48;5;4;"
    assert box.content =~ "Overview body"
  end

  test "tabs accepts a configurable highlight color" do
    {:ok, pid} = ChildServer.start(view: HighlightTabsExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "tabs", implicit_state: %{})

    assert box.content =~ "Overview"
    assert box.content =~ ~r/\e\[[0-9;]*38;5;1m/
    assert box.content =~ "48;5;1;"
    assert box.content =~ "Overview body"
  end

  test "tabs allow an individual tab highlight override" do
    {:ok, pid} = ChildServer.start(view: PerTabHighlightTabsExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "tabs", implicit_state: %{})

    assert box.content =~ "Overview"
    assert box.content =~ "Details"
    assert box.content =~ ~r/\e\[[0-9;]*38;5;5m/
    assert box.content =~ "48;5;1;"
    assert box.content =~ "Details body"
  end

  test "tabs render on the panel background by default" do
    {:ok, pid} =
      ChildServer.start(
        view: UnderlineTabsExample,
        start_opts: [],
        theme: Breeze.Theme.builtin(:gruvbox)
      )

    {:ok, _acc, box} = ChildServer.render(pid, implicit_state: %{})

    assert box.content =~ "48;2;50;48;47;"
  end
end
