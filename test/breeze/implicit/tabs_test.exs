defmodule Breeze.Implicit.TabsTest do
  use ExUnit.Case, async: true

  alias Breeze.Implicit.Tabs

  defmodule ClickableTabsView do
    use Breeze.View
    import Breeze.Blocks

    def mount(opts, term),
      do:
        {:ok,
         assign(term, selected_tab: "overview", variant: Keyword.get(opts, :variant, "default"))}

    def render(assigns) do
      ~H"""
      <.tabs
        id="tabs"
        selected={@selected_tab}
        variant={@variant}
        br-change="select_tab"
        style="width-24 height-6"
        item_class="selected:bg-primary selected:text selected:bold width-10"
      >
        <:tab value="overview" label="Overview">
          <.scroll id="tabs-panel-overview" class="width-full height-full">
            <box :for={row <- 1..20}>overview {row}</box>
          </.scroll>
        </:tab>
        <:tab value="details" label="Details">
          <.scroll id="tabs-panel-details" class="width-full height-full">
            <box :for={row <- 1..20}>details {row}</box>
          </.scroll>
        </:tab>
      </.tabs>
      """
    end

    def handle_event("select_tab", %{value: value}, term) do
      {:noreply, assign(term, selected_tab: value)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  describe "init/3" do
    test "uses the root selected tab when provided" do
      children = [
        %{:"tab-label" => "Overview", value: "overview"},
        %{:"tab-label" => "Details", value: "details"}
      ]

      {:ok, state} = Tabs.init(children, %{:"tab-selected" => "details"}, %{})

      assert state.selected == "details"
      assert state.selected_index == 1
    end

    test "prefers the current root selected tab over stale last state" do
      children = [
        %{:"tab-label" => "Overview", value: "overview"},
        %{:"tab-label" => "Details", value: "details"}
      ]

      {:ok, state} =
        Tabs.init(children, %{:"tab-selected" => "details"}, %{
          selected: "overview",
          selected_index: 0
        })

      assert state.selected == "details"
      assert state.selected_index == 1
    end
  end

  describe "handle_event/3" do
    test "ignores horizontal navigation when there are no tabs" do
      state = %{
        values: [],
        widths: [],
        selected: nil,
        selected_index: 0,
        offset_x: 0,
        viewport_width: 20
      }

      assert Tabs.handle_event(nil, %{"key" => "ArrowRight"}, state) ==
               {:noreply, state}

      assert Tabs.handle_event(nil, %{"key" => "ArrowLeft"}, state) ==
               {:noreply, state}
    end

    test "leaves vertical navigation to generic event delegation" do
      state = %{
        values: ["overview", "details"],
        widths: [10, 9],
        selected: "overview",
        selected_index: 0,
        offset_x: 0,
        viewport_width: 20,
        target_prefix: "tabs-tab-"
      }

      assert Tabs.handle_event(nil, %{"key" => "ArrowDown"}, state) ==
               {:noreply, state, consumed: false}

      assert Tabs.handle_event(nil, %{"key" => "PageDown"}, state) ==
               {:noreply, state, consumed: false}
    end

    test "repeated horizontal navigation computes scroll offsets without crashing" do
      state = %{
        values: [
          "overview",
          "requests",
          "responses",
          "headers",
          "cookies",
          "timeline",
          "inspector",
          "settings",
          "shortcuts",
          "advanced"
        ],
        widths:
          Enum.map(
            ~w(Overview Requests Responses Headers Cookies Timeline Inspector Settings Shortcuts Advanced),
            &(String.length(&1) + 2)
          ),
        selected: "overview",
        selected_index: 0,
        offset_x: 0,
        viewport_width: 38,
        target_prefix: "tabs-tab-"
      }

      final_state =
        Enum.reduce(1..20, state, fn _, acc ->
          assert {{:change, _payload}, next_state} =
                   Tabs.handle_event(nil, %{"key" => "ArrowRight"}, acc)

          next_state
        end)

      assert is_integer(final_state.offset_x)
      assert final_state.offset_x >= 0
    end

    test "selects a tab when its label is clicked" do
      state = %{
        values: ["overview", "details"],
        widths: [10, 9],
        selected: "overview",
        selected_index: 0,
        offset_x: 0,
        viewport_width: 20,
        target_prefix: "tabs-tab-"
      }

      assert {{:change, %{value: "details", index: 1}}, next_state} =
               Tabs.handle_event(
                 nil,
                 %{
                   "mouse" => %{"button" => "left", "action" => "press"},
                   "target" => "tabs-tab-details"
                 },
                 state
               )

      assert next_state.selected == "details"
      assert next_state.selected_index == 1
    end

    for variant <- ["default", "underline"] do
      test "#{variant} tabs delegate scrolling to the current panel without moving focus" do
        session =
          Breeze.Test.start!(ClickableTabsView,
            size: {30, 10},
            start_opts: [variant: unquote(variant)]
          )

        on_exit(fn -> Breeze.Test.stop(session) end)
        Breeze.Test.focus(session, "tabs")

        for {down, up} <- [
              {"ArrowDown", "ArrowUp"},
              {"j", "k"},
              {"PageDown", "PageUp"},
              {"End", "Home"}
            ] do
          Breeze.Test.input(session, down)

          assert {Breeze.Implicit.Scroll, %{offset_y: offset}} =
                   Breeze.Test.metadata(session).implicit_state["tabs-panel-overview"]

          assert offset > 0
          Breeze.Test.input(session, up)

          assert {Breeze.Implicit.Scroll, %{offset_y: 0}} =
                   Breeze.Test.metadata(session).implicit_state["tabs-panel-overview"]

          assert Breeze.Test.focused(session) == "tabs"
        end

        Breeze.Test.input(session, "ArrowRight")
        assert Breeze.Test.metadata(session).assigns.selected_tab == "details"
        Breeze.Test.render!(session)
        Breeze.Test.input(session, "ArrowDown")

        assert {Breeze.Implicit.Scroll, %{offset_y: 1}} =
                 Breeze.Test.metadata(session).implicit_state["tabs-panel-details"]

        assert Breeze.Test.focused(session) == "tabs"

        Breeze.Test.input(session, "ArrowLeft")
        assert Breeze.Test.metadata(session).assigns.selected_tab == "overview"
        Breeze.Test.render!(session)
        Breeze.Test.input(session, "ArrowDown")

        assert {Breeze.Implicit.Scroll, %{offset_y: 1}} =
                 Breeze.Test.metadata(session).implicit_state["tabs-panel-overview"]
      end
    end

    test "clicking a rendered tab label updates the selected tab" do
      session = Breeze.Test.start!(ClickableTabsView, size: {30, 10})
      on_exit(fn -> Breeze.Test.stop(session) end)

      assert {_status, "tabs", _changed} =
               Breeze.Test.click(session, "tabs-tab-details")

      assert Breeze.Test.render_text!(session) =~ "details"

      assert %{implicit_state: %{"tabs" => {Breeze.Implicit.Tabs, state}}} =
               Breeze.Test.metadata(session)

      assert state.selected == "details"
      assert Breeze.Test.focused(session) == "tabs"
    end
  end
end
