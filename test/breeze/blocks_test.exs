defmodule Breeze.BlocksTest do
  use ExUnit.Case, async: true

  import Breeze.TestSupport.ProcessHelpers, only: [start_child_server: 1]

  alias Breeze.Blocks
  alias Breeze.ChildServer
  alias Breeze.Renderer

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

  defmodule ModalBackdropExample do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <box class="width-screen height-screen bg">
        <box>Background should stay put</box>
        <box class="height-1 width-full overflow-hidden">
          <.modal id="modal" width={24} height={7} dim>
            <:title>Dialog</:title>
            <box class="padding-left-2 padding-top-2">Modal body</box>
          </.modal>
        </box>
        <box>Footer should stay put</box>
        <box class="fixed right-0 bottom-0">CORNER</box>
      </box>
      """
    end
  end

  defmodule ButtonExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.button id="confirm" class="width-10">Confirm</.button>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule PanelFocusWithinExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.panel id="panel" class="width-16 height-4">
        <:title>Details</:title>
        <.button id="confirm" class="width-10">{" Confirm "}</.button>
      </.panel>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule UntitledPanelFocusWithinExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.panel id="panel" class="width-16 height-4">
        <.button id="confirm" class="width-10">{" Confirm "}</.button>
      </.panel>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule PanelFocusIndicatorOptOutExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.panel id="panel" hide_focus_indicator class="width-16 height-4">
        <:title>Details</:title>
        <.button id="confirm" class="width-10">{" Confirm "}</.button>
      </.panel>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule ScrollPanelFocusExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.panel id="panel" scroll class="width-16 height-4 overflow-hidden">Scroll body</.panel>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule PanelTitleOverlayExample do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <.panel id="panel" class="width-32 height-6 overflow-hidden bg-panel">
        <:title>Packages</:title>
        <box class="width-full bg-panel padding-left-1 padding-top-1">
          <box>Body</box>
          <box>Second</box>
          <box>Third</box>
          <box>Fourth</box>
          <box>Hidden</box>
        </box>
      </.panel>
      """
    end
  end

  defmodule FlashGroupExample do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <box class="width-screen height-screen">
        <box>Page body</box>
        <.flash_group id="flash-stack" flash={@flash} width={28} offset={0}/>
      </box>
      """
    end
  end

  defmodule FlashGapExample do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      assigns =
        assign(assigns,
          variant: Map.get(assigns, :variant, "default"),
          gap: Map.get(assigns, :gap, 1)
        )

      ~H"""
      <box class="width-screen height-screen bg">
        <box class="width-screen height-screen bg-primary content-repeat">.</box>
        <.flash_group
          id="flash-stack"
          flash={@flash}
          variant={@variant}
          width={20}
          offset={0}
          gap={@gap}
        />
      </box>
      """
    end
  end

  defmodule FlashSlotExample do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <box class="width-screen height-screen">
        <.flash_group
          flash={[%{id: "slot-flash", kind: :warning, highlight: "warning", message: "Careful now"}]}
          placement="top-left"
          width={24}
          offset={0}
        />
      </box>
      """
    end
  end

  defmodule FlashDefaultTopOffsetExample do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <box class="width-screen height-screen">
        <.flash_group
          id="flash-stack"
          flash={[%{id: "default-top-flash", kind: :info, message: "Offset once"}]}
          placement="top-left"
          width={24}
        />
      </box>
      """
    end
  end

  defmodule FlashTitledExample do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <box class="width-screen height-screen">
        <.flash_group
          flash={[
        %{
          id: "titled-flash",
          kind: :success,
          highlight: "accent",
          title: "Saved",
          message: "Draft persisted"
        }
      ]}
          placement="top-left"
          width={24}
          offset={0}
        />
      </box>
      """
    end
  end

  defmodule FlashSquareBorderExample do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <box class="width-screen height-screen">
        <.flash_group
          flash={[
        %{
          id: "square-flash",
          kind: :warning,
          highlight: "warning",
          title: "Saved #12",
          message: "Draft synced"
        }
      ]}
          placement="top-left"
          variant="square"
          width={25}
          offset={0}
        />
      </box>
      """
    end
  end

  defmodule FlashCustomColorExample do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <box class="width-screen height-screen">
        <.flash_group flash={@flash} placement="top-left" width={18} offset={0}/>
      </box>
      """
    end
  end

  defmodule FlashRoundedBorderExample do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <box class="width-screen height-screen">
        <.flash_group
          flash={[%{id: "rounded-flash", kind: :info, message: "Rounded"}]}
          placement="top-left"
          variant="rounded"
          width={20}
          offset={0}
        />
      </box>
      """
    end
  end

  defmodule MutedListExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.list id="items" variant="muted" style="width-12 height-4" list-selected="two">
        <:item value="one">One</:item>
        <:item value="two">Two</:item>
        <:item value="three">Three</:item>
      </.list>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule UnicodeMarkerListExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.list
        id="items"
        variant="muted"
        selected-indicator="🏡"
        style="width-12 height-4"
        list-selected="two"
      >
        <:item value="one">One</:item>
        <:item value="two">Two</:item>
        <:item value="three">Three</:item>
      </.list>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule UnselectedListExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.list id="items" variant="muted" style="width-12 height-4">
        <:item value="one">One</:item>
        <:item value="two">Two</:item>
        <:item value="three">Three</:item>
      </.list>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule VirtualListExample do
    use Breeze.View
    import Breeze.Blocks

    @items Enum.map(0..9, fn index ->
             id = "item-#{index}"
             %{id: id, label: "Item #{index}"}
           end)

    def mount(_opts, term) do
      {:ok, term |> focus("items") |> assign(selected: "item-5")}
    end

    def render(assigns) do
      assigns = assign(assigns, items: @items)

      ~H"""
      <.list
        id="items"
        list-selected={@selected}
        virtual_window={3}
        br-change="change"
        style="width-16 height-5"
      >
        <:item :for={item <- @items} value={item.id}>{item.label}</:item>
      </.list>
      """
    end

    def handle_event("change", %{value: value}, term),
      do: {:noreply, assign(term, selected: value)}

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule InferredStructuredVirtualListExample do
    use Breeze.View
    import Breeze.Blocks

    @items Enum.map(0..99, fn index ->
             id = "item-#{index}"
             %{id: id, label: "Item #{index}"}
           end)

    def mount(opts, term) do
      {:ok,
       term
       |> focus("items")
       |> assign(test_pid: Keyword.fetch!(opts, :test_pid), items: @items)}
    end

    def render(assigns) do
      ~H"""
      <box class="width-20 height-10">
        <.list id="items" list-selected="item-0" virtual class="width-full height-full">
          <:item :for={item <- @items} value={item.id}>
            <box class="bold">{render_label(item.label, @test_pid)}</box>
          </:item>
        </.list>
      </box>
      """
    end

    def render_label(label, test_pid) do
      send(test_pid, {:rendered_list_label, label})
      label
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule TreeExample do
    use Breeze.View
    import Breeze.Blocks

    @nodes [
      %{
        id: "root",
        label: "breeze",
        children: [
          %{
            id: "src",
            label: "src",
            children: [
              %{id: "lib", label: "lib"}
            ]
          },
          %{id: "mix", label: "mix.exs"}
        ]
      }
    ]

    def mount(_opts, term) do
      {:ok, term |> focus("files") |> assign(selected: "root", expanded: ["root"])}
    end

    def render(assigns) do
      assigns = assign(assigns, nodes: @nodes)

      ~H"""
      <.tree
        id="files"
        nodes={@nodes}
        selected={@selected}
        expanded={@expanded}
        br-change="change"
        style="width-20 height-6"
      />
      """
    end

    def handle_event("change", %{value: value, expanded: expanded}, term),
      do: {:noreply, assign(term, selected: value, expanded: expanded)}

    def handle_event("change", %{value: value}, term),
      do: {:noreply, assign(term, selected: value)}

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule VirtualTreeExample do
    use Breeze.View
    import Breeze.Blocks

    @nodes Enum.map(0..9, fn index ->
             label = "file-#{index}"
             %{id: label, label: label}
           end)

    def mount(_opts, term) do
      {:ok, term |> focus("files") |> assign(selected: "file-3")}
    end

    def render(assigns) do
      assigns = assign(assigns, nodes: @nodes)

      ~H"""
      <.tree
        id="files"
        nodes={@nodes}
        selected={@selected}
        virtual_window={2}
        br-change="change"
        style="width-20 height-4"
      />
      """
    end

    def handle_event("change", %{value: value}, term),
      do: {:noreply, assign(term, selected: value)}

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule VirtualUncontrolledTreeExample do
    use Breeze.View
    import Breeze.Blocks

    @nodes [
      %{
        id: "root",
        label: "root",
        children: [
          %{id: "src", label: "src", children: [%{id: "lib", label: "lib"}]},
          %{id: "mix", label: "mix.exs"}
        ]
      }
    ]

    def mount(_opts, term), do: {:ok, term |> focus("files") |> assign(selected: "root")}

    def render(assigns) do
      assigns = assign(assigns, nodes: @nodes)

      ~H"""
      <.tree
        id="files"
        nodes={@nodes}
        selected={@selected}
        default_expanded={["root"]}
        virtual_window={4}
        br-change="change"
        style="width-20 height-6"
      />
      """
    end

    def handle_event("change", %{value: value}, term),
      do: {:noreply, assign(term, selected: value)}

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule WrappedVirtualUncontrolledTreeExample do
    use Breeze.View
    import Breeze.Blocks

    @nodes [
      %{
        id: "root",
        label: "root",
        children: [
          %{id: "src", label: "src", children: [%{id: "lib", label: "lib"}]},
          %{id: "mix", label: "mix.exs"}
        ]
      }
    ]

    def mount(_opts, term), do: {:ok, term |> focus("files") |> assign(selected: "root")}

    def tree_wrapper(assigns) do
      ~H"""
      <.tree
        id="files"
        nodes={@nodes}
        selected={@selected}
        default_expanded={["root"]}
        virtual_window={4}
        br-change="change"
        style="width-20 height-6"
      />
      """
    end

    def render(assigns) do
      assigns = assign(assigns, nodes: @nodes)

      ~H"""
      <.tree_wrapper nodes={@nodes} selected={@selected}/>
      """
    end

    def handle_event("change", %{value: value}, term),
      do: {:noreply, assign(term, selected: value)}

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule EmptyTreeExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term |> focus("files")}

    def render(assigns) do
      ~H"""
      <.tree id="files" nodes={[]} style="width-20 height-4"/>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule EmptyTreeSlotExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term |> focus("files")}

    def render(assigns) do
      ~H"""
      <.tree id="files" nodes={[]} style="width-20 height-4">
        <:empty>
          <box class="text-accent">Nothing here</box>
        </:empty>
      </.tree>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule TableExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term) do
      {:ok, term |> focus("cities") |> assign(selected_city: "delhi")}
    end

    def render(assigns) do
      rows = [
        %{id: "tokyo", rank: "1", city: "Tokyo", country: "Japan", population: "37.2m"},
        %{id: "delhi", rank: "2", city: "Delhi", country: "India", population: "32.0m"},
        %{id: "shanghai", rank: "3", city: "Shanghai", country: "China", population: "28.5m"}
      ]

      assigns = assign(assigns, rows: rows)

      ~H"""
      <.table id="cities" rows={@rows} selected={@selected_city} br-change="city_changed">
        <:col :let={city} label="#" width={4} align="right">{city.rank}</:col>
        <:col :let={city} label="City" width={12}>{city.city}</:col>
        <:col :let={city} label="Country" width={12} align="center">{city.country}</:col>
        <:col :let={city} label="Pop." width={10} align={:right}>
          <box class="text-muted">{city.population}</box>
        </:col>
      </.table>
      """
    end

    def handle_event("city_changed", %{value: value}, term) do
      {:noreply, assign(term, selected_city: value)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule InferredTableExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term |> focus("packages")}

    def render(assigns) do
      rows = [
        %{id: "jason", name: "jason", version: "1.5.0-alpha.2", downloads: "202.6m"}
      ]

      assigns = assign(assigns, rows: rows)

      ~H"""
      <.table id="packages" rows={@rows}>
        <:col :let={package} label="Name">{package.name}</:col>
        <:col :let={package} label="Latest">{package.version}</:col>
        <:col :let={package} label="Downloads" align="right">{package.downloads}</:col>
      </.table>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule StretchTableExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term |> focus("packages")}

    def render(assigns) do
      rows = [
        %{id: "jason", name: "jason", version: "1.5.0-alpha.2", downloads: "202.6m"}
      ]

      assigns = assign(assigns, rows: rows)

      ~H"""
      <.table id="packages" rows={@rows} class="width-60 height-4 border-none">
        <:col :let={package} label="Name">{package.name}</:col>
        <:col :let={package} label="Latest">{package.version}</:col>
        <:col :let={package} label="Downloads" align="right">{package.downloads}</:col>
      </.table>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defp rendered_cell!(box, point) do
    rendered_cell(box, point) || flunk("expected rendered cell at #{inspect(point)}")
  end

  defp rendered_cell(box, point) do
    layer_cell(Map.get(box, :fixed_layer_map), point) ||
      layer_cell(Map.get(box, :layer_map), point)
  end

  defp layer_cell(layer_map, point) when is_map(layer_map) do
    Map.get(layer_map, point) || default_fill_cell(Map.get(layer_map, :__default_fill__), point)
  end

  defp layer_cell(_layer_map, _point), do: nil

  defp default_fill_cell(nil, _point), do: nil

  defp default_fill_cell({_cell, _left, _top, _right, _bottom} = fill, point) do
    default_fill_cell([fill], point)
  end

  defp default_fill_cell(fills, {y, x}) when is_list(fills) do
    Enum.find_value(fills, fn
      {cell, left, top, right, bottom}
      when left <= x and x <= right and top <= y and y <= bottom ->
        cell

      _fill ->
        nil
    end)
  end

  describe "merge_class/2" do
    test "matches merge_style semantics" do
      assert Blocks.merge_class("border width-24 height-8", "width-32 bg-4") ==
               "border width-32 height-8 bg-4"
    end

    test "matches Tailwind utilities with their legacy aliases" do
      assert Blocks.merge_class(
               "width-full height-8 padding-left-1 bold border-rounded layer-1",
               "w-32 h-4 pl-2 font-normal rounded-none z-2"
             ) == "w-32 h-4 pl-2 font-normal rounded-none z-2"

      assert Blocks.merge_class("w-full h-8", "width-32 height-4") ==
               "width-32 height-4"
    end

    test "keeps border shape and color utilities independent" do
      assert Blocks.merge_class("rounded border-stroke", "border-primary") ==
               "rounded border-primary"
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
    {:ok, pid} = start_child_server(view: UnderlineTabsExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "tabs", implicit_state: %{})

    assert box.content =~ "Overview"
    assert box.content =~ "Details"
    assert box.content =~ ~r/\e\[[0-9;]*38;5;4m/
    assert box.content =~ "48;5;4;"
    assert box.content =~ "Overview body"
  end

  test "tabs accepts a configurable highlight color" do
    {:ok, pid} = start_child_server(view: HighlightTabsExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "tabs", implicit_state: %{})

    assert box.content =~ "Overview"
    assert box.content =~ ~r/\e\[[0-9;]*38;5;1m/
    assert box.content =~ "48;5;1;"
    assert box.content =~ "Overview body"
  end

  test "tabs allow an individual tab highlight override" do
    {:ok, pid} = start_child_server(view: PerTabHighlightTabsExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "tabs", implicit_state: %{})

    assert box.content =~ "Overview"
    assert box.content =~ "Details"
    assert box.content =~ ~r/\e\[[0-9;]*38;5;5m/
    assert box.content =~ "48;5;1;"
    assert box.content =~ "Details body"
  end

  test "tabs render on the panel background by default" do
    {:ok, pid} =
      start_child_server(
        view: UnderlineTabsExample,
        start_opts: [],
        theme: Breeze.Theme.builtin(:gruvbox)
      )

    {:ok, _acc, box} = ChildServer.render(pid, implicit_state: %{})

    assert box.content =~ "48;2;50;48;47;"
  end

  test "dimmed modal preserves background content" do
    {_acc, box} =
      Renderer.render(ModalBackdropExample, %{},
        terminal: %Termite.Terminal{size: %{width: 48, height: 16}},
        theme: :system,
        theme_source: :system
      )

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")

    assert plain_content =~ "Dialog"
    assert plain_content =~ "Modal body"
    assert plain_content =~ "Background should stay put"
    assert plain_content =~ "Footer should stay put"
    assert plain_content =~ "CORNER"

    lines = String.split(plain_content, "\n")

    assert lines |> Enum.at(0) |> String.starts_with?("Background should stay put")
    assert lines |> Enum.at(2) |> String.starts_with?("Footer should stay put")
  end

  test "button renders with primary styling and a focused inverse state" do
    {:ok, pid} = start_child_server(view: ButtonExample, start_opts: [])

    {:ok, acc, box} = ChildServer.render(pid, focused: "confirm", implicit_state: %{})

    assert acc.focusables == ["confirm"]
    assert box.content =~ "Confirm"
    assert box.content =~ ~r/\e\[[0-9;]*7;[0-9;]*m/
  end

  test "panel highlights when a descendant is focused" do
    {:ok, pid} = start_child_server(view: PanelFocusWithinExample, start_opts: [])

    {:ok, _acc, unfocused_box} =
      ChildServer.render(pid, focused: "not-focused", implicit_state: %{})

    {:ok, _acc, box} = ChildServer.render(pid, focused: "confirm", implicit_state: %{})

    unfocused_content = BackBreeze.Utils.strip_escape_chars(unfocused_box.content)
    focused_content = BackBreeze.Utils.strip_escape_chars(box.content)

    assert box.content =~ "Confirm"
    assert box.content =~ "Details"
    assert box.content =~ ~r/\e\[[0-9;]*38;5;4m[╭│╰]/
    assert box.content =~ ~r/\e\[[0-9;]*38;5;4m╭▶/
    assert box.content =~ ~r/\e\[[0-9;]*38;5;4mDetails/
    assert unfocused_content =~ "╭─Details"
    refute unfocused_content =~ "▶"
    assert focused_content =~ "╭▶Details"
    assert String.replace(focused_content, "▶", "─") == unfocused_content
  end

  test "panel focus marker remains visible without a title and does not move content" do
    {:ok, pid} = start_child_server(view: UntitledPanelFocusWithinExample, start_opts: [])

    {:ok, _acc, unfocused_box} =
      ChildServer.render(pid, focused: "not-focused", implicit_state: %{})

    {:ok, _acc, focused_box} = ChildServer.render(pid, focused: "confirm", implicit_state: %{})

    unfocused_content = BackBreeze.Utils.strip_escape_chars(unfocused_box.content)
    focused_content = BackBreeze.Utils.strip_escape_chars(focused_box.content)

    refute unfocused_content =~ "▶"
    assert focused_content =~ "╭▶"
    assert String.replace(focused_content, "▶", "─") == unfocused_content
  end

  test "panel focus marker can be disabled without disabling focused panel styling" do
    {:ok, pid} = start_child_server(view: PanelFocusIndicatorOptOutExample, start_opts: [])

    {:ok, _acc, unfocused_box} =
      ChildServer.render(pid, focused: "not-focused", implicit_state: %{})

    {:ok, _acc, focused_box} = ChildServer.render(pid, focused: "confirm", implicit_state: %{})

    unfocused_content = BackBreeze.Utils.strip_escape_chars(unfocused_box.content)
    focused_content = BackBreeze.Utils.strip_escape_chars(focused_box.content)

    refute unfocused_content =~ "▶"
    refute focused_content =~ "▶"
    assert unfocused_content =~ "╭─Details"
    assert focused_content == unfocused_content
    assert focused_box.content =~ ~r/\e\[[0-9;]*38;5;4m[╭│╰]/
    assert focused_box.content =~ ~r/\e\[[0-9;]*38;5;4mDetails/
  end

  test "panel focus marker follows the focus owner of a clipped scroll panel" do
    {:ok, pid} = start_child_server(view: ScrollPanelFocusExample, start_opts: [])

    {:ok, _acc, unfocused_box} =
      ChildServer.render(pid, focused: "not-focused", implicit_state: %{})

    {:ok, _acc, focused_box} = ChildServer.render(pid, focused: "panel", implicit_state: %{})

    unfocused_content = BackBreeze.Utils.strip_escape_chars(unfocused_box.content)
    focused_content = BackBreeze.Utils.strip_escape_chars(focused_box.content)

    refute unfocused_content =~ "▶"
    assert focused_content =~ "╭▶"
    assert String.replace(focused_content, "▶", "─") == unfocused_content
  end

  test "panel title renders above full-size panel content" do
    {_acc, box} =
      Renderer.render(PanelTitleOverlayExample, %{},
        terminal: %Termite.Terminal{size: %{width: 40, height: 8}},
        theme: Breeze.Theme.builtin(:nebula)
      )

    content = BackBreeze.Utils.strip_escape_chars(box.content)

    assert content =~ "╭─Packages"
    assert content =~ "Body"
    refute content =~ "Hidden"
    assert box.content =~ ~r/\e\[[0-9;]*48;2;31;70;98[0-9;]*mPackages/
  end

  test "flash_group renders a fixed bottom-right stack with custom highlights" do
    flash = [
      %{id: "saved", kind: :success, message: "Saved draft", highlight: "accent"},
      %{id: "publish-error", kind: :error, title: "Publish failed", message: "Try again"}
    ]

    {acc, box} =
      Renderer.render(FlashGroupExample, %{flash: flash},
        terminal: %Termite.Terminal{size: %{width: 60, height: 12}}
      )

    stack = Map.fetch!(acc.boxes, "flash-stack")
    assert stack.position == :fixed
    assert stack.right == 0
    assert stack.bottom == 0

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "Page body"
    assert plain_content =~ "Saved draft"
    assert plain_content =~ "Publish failed"
    assert plain_content =~ "Try again"
    assert box.content =~ ~r/\e\[[0-9;]*48;5;5(?:;|m)/
  end

  test "flash item component stays private" do
    Code.ensure_loaded!(Breeze.Blocks)

    assert function_exported?(Breeze.Blocks, :flash_group, 1)
    refute function_exported?(Breeze.Blocks, :flash, 1)
    refute :flash in Breeze.Blocks.__breeze_components__()
  end

  test "flash_group leaves gaps transparent over existing content" do
    flash = [
      %{id: "one", kind: :info, message: "One"},
      %{id: "two", kind: :info, message: "Two"}
    ]

    {_acc, box} =
      Renderer.render(FlashGapExample, %{flash: flash},
        terminal: %Termite.Terminal{size: %{width: 30, height: 10}}
      )

    assert {".", gap_style} = rendered_cell!(box, {6, 10})
    assert gap_style =~ "48;5;4"
  end

  test "square flash_group subtracts one row from the configured gap" do
    flash = [
      %{id: "one", kind: :info, message: "One"},
      %{id: "two", kind: :info, message: "Two"}
    ]

    {_acc, box} =
      Renderer.render(FlashGapExample, %{flash: flash, variant: "square"},
        terminal: %Termite.Terminal{size: %{width: 30, height: 12}}
      )

    assert {"▔", bottom_border_style} = rendered_cell!(box, {6, 10})
    refute bottom_border_style =~ "49m"

    {_acc, box} =
      Renderer.render(FlashGapExample, %{flash: flash, variant: "square", gap: 2},
        terminal: %Termite.Terminal{size: %{width: 30, height: 12}}
      )

    assert {".", gap_style} = rendered_cell!(box, {6, 10})
    assert gap_style =~ "48;5;4"

    assert {"▁", top_border_style} = rendered_cell!(box, {1, 10})
    refute top_border_style =~ "49m"
    assert top_border_style =~ ~r/48;(?:5|2);/
  end

  test "flash_group renders message content and semantic warning highlight" do
    {acc, box} = Renderer.render(FlashSlotExample, %{})

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "Careful now"
    assert box.content =~ ~r/\e\[[0-9;]*48;5;3(?:;|m)/

    flash_box = Map.fetch!(acc.boxes, "slot-flash")
    inline_box = hd(flash_box.children)
    [highlight_box, body_box] = inline_box.children

    assert flash_box.style.border.top == "─"
    assert flash_box.style.border.top_left == "┌"
    assert highlight_box.style.width == 1
    assert body_box.style.width == 21
  end

  test "flash_group applies the default top offset once" do
    {acc, box} = Renderer.render(FlashDefaultTopOffsetExample, %{})

    stack_box = Map.fetch!(acc.boxes, "flash-stack")
    flash_box = Map.fetch!(acc.boxes, "default-top-flash")

    assert stack_box.top == 1
    assert flash_box.top == 0
    assert {"┌", _style} = rendered_cell!(box, {1, 1})
    refute match?({"┌", _style}, rendered_cell(box, {2, 1}))
  end

  test "flash highlight fills the message content height" do
    {_acc, box} = Renderer.render(FlashTitledExample, %{})

    assert {" ", first_row_style} = rendered_cell!(box, {1, 1})
    assert {" ", second_row_style} = rendered_cell!(box, {2, 1})

    assert first_row_style =~ "48;5;5"
    assert second_row_style =~ "48;5;5"
  end

  test "flash_group can use square block borders with a padded color strip" do
    {acc, box} = Renderer.render(FlashSquareBorderExample, %{})

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "▁▁▁▁▁"
    assert plain_content =~ "▔▔▔▔▔"
    assert plain_content =~ "Saved #12"
    assert plain_content =~ "Draft synced"

    flash_box = Map.fetch!(acc.boxes, "square-flash")
    assert flash_box.style.border == BackBreeze.Border.none()

    assert {"▌", border_strip_style} = rendered_cell!(box, {1, 0})
    assert {" ", inner_strip_style} = rendered_cell!(box, {1, 1})
    assert {"▌", text_row_strip_style} = rendered_cell!(box, {2, 0})

    assert border_strip_style =~ "48;5;3"
    assert border_strip_style =~ "38;5;7"
    assert inner_strip_style =~ "48;5;3"
    assert text_row_strip_style =~ "48;5;3"

    assert {"▁", top_border_style} = rendered_cell!(box, {0, 0})
    assert {"▔", bottom_border_style} = rendered_cell!(box, {5, 0})

    refute top_border_style =~ "49m"
    refute bottom_border_style =~ "49m"
    assert top_border_style =~ ~r/48;(?:5|2);/
    assert bottom_border_style =~ ~r/48;(?:5|2);/
  end

  test "square flash_group block borders use the active theme background" do
    {_acc, box} =
      Renderer.render(FlashSquareBorderExample, %{}, theme: Breeze.Theme.builtin(:gruvbox))

    assert {"▁", top_border_style} = rendered_cell!(box, {0, 0})

    refute top_border_style =~ "49m"
    assert top_border_style =~ "48;2;40;40;40"

    assert {"▐", right_border_style} = rendered_cell!(box, {1, 24})
    assert right_border_style =~ "48;2;50;48;47"
  end

  test "flash_group supports custom hex and RGB tuple highlight colors" do
    {_acc, hex_box} =
      Renderer.render(FlashCustomColorExample, %{
        flash: [%{id: "hex-flash", kind: :info, message: "Hex", highlight: "#f0a"}]
      })

    assert {" ", hex_highlight_style} = rendered_cell!(hex_box, {1, 1})
    assert hex_highlight_style =~ "48;2;255;0;170"

    {_acc, rgb_box} =
      Renderer.render(FlashCustomColorExample, %{
        flash: [%{id: "rgb-flash", kind: :info, message: "RGB", color: {1, 2, 3}}]
      })

    assert {" ", rgb_highlight_style} = rendered_cell!(rgb_box, {1, 1})
    assert rgb_highlight_style =~ "48;2;1;2;3"
  end

  test "flash_group can use rounded borders" do
    {acc, box} = Renderer.render(FlashRoundedBorderExample, %{})

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "Rounded"

    flash_box = Map.fetch!(acc.boxes, "rounded-flash")
    assert flash_box.style.border.top == "─"
    assert flash_box.style.border.top_left == "╭"
    assert flash_box.style.border.bottom_right == "╯"
  end

  test "list can render muted while unfocused and restore active colors on focus" do
    {:ok, pid} =
      start_child_server(
        view: MutedListExample,
        start_opts: [],
        theme: Breeze.Theme.builtin(:gruvbox)
      )

    {:ok, _acc, unfocused_box} =
      ChildServer.render(pid, focused: nil, implicit_state: %{}, allow_unfocused: true)

    {:ok, _acc, focused_box} = ChildServer.render(pid, focused: "items", implicit_state: %{})

    assert unfocused_box.content =~ "Two"
    assert focused_box.content =~ "Two"
    assert unfocused_box.content =~ "48;2;40;40;40;"
    assert unfocused_box.content =~ "38;2;188;175;142"
    assert unfocused_box.content =~ "48;2;105;132;122;"
    assert focused_box.content =~ "38;2;131;165;152m┌"
    assert focused_box.content =~ "38;2;40;40;40m>Two"
  end

  test "list items render their labels" do
    {:ok, pid} = start_child_server(view: MutedListExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "items", implicit_state: %{})

    assert box.content =~ "One"
    assert box.content =~ "Two"
  end

  test "list supports wide unicode selected markers" do
    {:ok, pid} = start_child_server(view: UnicodeMarkerListExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "items", implicit_state: %{})

    assert box.content =~ "🏡Two"
    assert box.content =~ "  One"
  end

  test "list does not mark every item selected when nothing is selected" do
    {:ok, pid} = start_child_server(view: UnselectedListExample, start_opts: [])

    {:ok, _acc, box} =
      ChildServer.render(pid, focused: nil, implicit_state: %{}, allow_unfocused: true)

    refute box.content =~ ">One"
    refute box.content =~ ">Two"
    refute box.content =~ ">Three"
    assert box.content =~ " One"
    assert box.content =~ " Two"
  end

  test "list virtual window derives the item slice from selection" do
    {:ok, pid} =
      start_child_server(
        view: VirtualListExample,
        start_opts: [],
        theme: Breeze.Theme.builtin(:gruvbox)
      )

    {:ok, acc, box} = ChildServer.render(pid, focused: "items", implicit_state: %{})

    assert box.content =~ "Item 4"
    assert box.content =~ "Item 5"
    assert box.content =~ "Item 6"
    refute box.content =~ "Item 3"
    refute box.content =~ "Item 7"
    assert map_size(acc.elements) <= 3

    assert {">", selected_style} = rendered_cell!(box, {2, 1})
    assert selected_style =~ "48;2;131;165;152"
    assert selected_style =~ "38;2;40;40;40"
  end

  test "structured virtual lists learn their rendered viewport and keep a bounded window" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 40}}

    {:ok, pid} =
      start_child_server(
        view: InferredStructuredVirtualListExample,
        start_opts: [test_pid: self()],
        terminal: terminal
      )

    {:ok, _acc, _box} =
      ChildServer.render(pid, terminal: terminal, focused: "items", implicit_state: %{})

    metadata = ChildServer.metadata(pid)

    assert {Breeze.Implicit.List, %{viewport_height: 8}} = metadata.implicit_state["items"]

    drain_rendered_list_labels(MapSet.new())

    {_acc, box} =
      Renderer.render(InferredStructuredVirtualListExample, metadata.assigns,
        terminal: terminal,
        focused: "items",
        implicit_state: metadata.implicit_state
      )

    rendered_labels = drain_rendered_list_labels(MapSet.new())

    assert MapSet.size(rendered_labels) == 12
    assert MapSet.member?(rendered_labels, "Item 0")
    assert MapSet.member?(rendered_labels, "Item 11")
    refute MapSet.member?(rendered_labels, "Item 12")
    assert box.content =~ "Item 0"
    assert box.content =~ "Item 7"
    refute box.content =~ "Item 8"
  end

  test "list virtual window scrolls to a changed controlled selection" do
    {:ok, pid} = start_child_server(view: VirtualListExample, start_opts: [])

    {:ok, _acc, _box} = ChildServer.render(pid, focused: "items", implicit_state: %{})

    assert {Breeze.Implicit.List, %{selected: "item-5", offset: 4}} =
             ChildServer.metadata(pid).implicit_state["items"]

    assert :ok = ChildServer.update_assigns(pid, selected: "item-0")
    {:ok, _acc, box} = ChildServer.render(pid, focused: "items", implicit_state: %{})

    assert box.content =~ "Item 0"
    assert box.content =~ "Item 1"
    assert box.content =~ "Item 2"
    refute box.content =~ "Item 3"

    assert {Breeze.Implicit.List, %{selected: "item-0", offset: 0}} =
             ChildServer.metadata(pid).implicit_state["items"]
  end

  defp drain_rendered_list_labels(labels) do
    receive do
      {:rendered_list_label, label} ->
        drain_rendered_list_labels(MapSet.put(labels, label))
    after
      0 -> labels
    end
  end

  test "tree renders visible rows with collapsed and expanded prefixes" do
    {:ok, pid} = start_child_server(view: TreeExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "files", implicit_state: %{})
    content = BackBreeze.Utils.strip_escape_chars(box.content)

    assert content =~ "⌄breeze"
    assert content =~ "│  >src"
    assert content =~ "│   mix.exs"
    refute content =~ "lib"
  end

  test "tree expands selected rows through the implicit lifecycle" do
    {:ok, pid} = start_child_server(view: TreeExample, start_opts: [])

    {:ok, _acc, _box} = ChildServer.render(pid, focused: "files", implicit_state: %{})

    assert {:noreply, "files", true} = ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "files", true} = ChildServer.dispatch_input(pid, "Enter")

    {:ok, _acc, box} = ChildServer.render(pid, focused: "files", implicit_state: %{})

    assert box.content =~ "⌄src"
    assert box.content =~ "lib"
  end

  test "tree virtual window derives the row slice from selection" do
    {:ok, pid} = start_child_server(view: VirtualTreeExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "files", implicit_state: %{})

    assert box.content =~ "file-2"
    assert box.content =~ "file-3"
    refute box.content =~ "file-1"
    refute box.content =~ "file-4"
    refute box.content =~ "file-5"
  end

  test "tree virtual window scrolls to a changed controlled selection" do
    {:ok, pid} = start_child_server(view: VirtualTreeExample, start_opts: [])

    {:ok, _acc, _box} = ChildServer.render(pid, focused: "files", implicit_state: %{})

    assert {Breeze.Implicit.Tree, %{selected: "file-3", offset: 2}} =
             ChildServer.metadata(pid).implicit_state["files"]

    assert :ok = ChildServer.update_assigns(pid, selected: "file-0")
    {:ok, _acc, box} = ChildServer.render(pid, focused: "files", implicit_state: %{})

    assert box.content =~ "file-0"
    assert box.content =~ "file-1"
    refute box.content =~ "file-2"

    assert {Breeze.Implicit.Tree, %{selected: "file-0", offset: 0}} =
             ChildServer.metadata(pid).implicit_state["files"]
  end

  test "tree virtual window can use implicit-owned expanded state" do
    {:ok, pid} = start_child_server(view: VirtualUncontrolledTreeExample, start_opts: [])

    {:ok, _acc, _box} = ChildServer.render(pid, focused: "files", implicit_state: %{})

    assert {:noreply, "files", true} = ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "files", true} = ChildServer.dispatch_input(pid, "Enter")

    {:ok, _acc, box} = ChildServer.render(pid, focused: "files", implicit_state: %{})

    assert box.content =~ "⌄src"
    assert box.content =~ "lib"
  end

  test "wrapped virtual tree can use implicit-owned expanded state" do
    {:ok, pid} = start_child_server(view: WrappedVirtualUncontrolledTreeExample, start_opts: [])

    {:ok, _acc, _box} = ChildServer.render(pid, focused: "files", implicit_state: %{})

    assert {:noreply, "files", true} = ChildServer.dispatch_input(pid, "ArrowDown")
    assert {:noreply, "files", true} = ChildServer.dispatch_input(pid, "Enter")

    {:ok, _acc, box} = ChildServer.render(pid, focused: "files", implicit_state: %{})

    assert box.content =~ "⌄src"
    assert box.content =~ "lib"
  end

  test "tree renders no empty content by default" do
    {:ok, pid} = start_child_server(view: EmptyTreeExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "files", implicit_state: %{})

    refute box.content =~ "No items"
  end

  test "tree supports an empty slot" do
    {:ok, pid} = start_child_server(view: EmptyTreeSlotExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "files", implicit_state: %{})

    assert box.content =~ "Nothing here"
  end

  test "table renders headers, rows, and selectable cells" do
    {:ok, pid} = start_child_server(view: TableExample, start_opts: [])

    {:ok, acc, box} = ChildServer.render(pid, focused: "cities", implicit_state: %{})

    assert acc.focusables == ["cities"]
    assert box.content =~ "City"
    assert box.content =~ "Tokyo"
    assert box.content =~ "Delhi"
    assert box.content =~ "India"
    assert box.content =~ ~r/\e\[[0-9;]*48;5;4/
  end

  test "table inferred widths include full text and cell padding" do
    {:ok, pid} = start_child_server(view: InferredTableExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "packages", implicit_state: %{})
    content = BackBreeze.Utils.strip_escape_chars(box.content)

    assert content =~ "Downloads"
    assert content =~ "1.5.0-alpha.2"
    assert content =~ "202.6m"
    refute content =~ "Down "
  end

  test "table distributes unbounded columns across the available row width" do
    {:ok, pid} = start_child_server(view: StretchTableExample, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: "packages", implicit_state: %{})
    lines = box.content |> BackBreeze.Utils.strip_escape_chars() |> String.split("\n")
    header = Enum.find(lines, &String.contains?(&1, "Downloads"))
    row = Enum.find(lines, &String.contains?(&1, "202.6m"))

    assert text_column(header, "Downloads") >= 48
    assert text_column(row, "202.6m") >= 52
  end

  test "table emits change events from keyboard navigation" do
    {:ok, pid} = start_child_server(view: TableExample, start_opts: [])

    assert {:ok, _acc, _box} = ChildServer.render(pid, focused: "cities", implicit_state: %{})
    assert {:noreply, "cities", true} = ChildServer.dispatch_input(pid, "ArrowDown")

    term = :sys.get_state(pid)
    assert term.assigns.selected_city == "shanghai"
  end

  defp text_column(line, text) do
    line
    |> String.split(text, parts: 2)
    |> hd()
    |> BackBreeze.Utils.string_length()
  end
end
