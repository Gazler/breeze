defmodule ListViewDemo do
  use Breeze.View
  import Breeze.Blocks

  @large_item_count 20_000
  @page_size 100
  @prefetch_pages 3

  def mount(_opts, term) do
    {:ok,
     term
     |> focus("languages")
     |> assign(
       large_items: 1..@large_item_count,
       mode: :default,
       selected: nil,
       lazy: %{
         total: @large_item_count,
         pages: %{},
         items: [],
         start: 0,
         cursor: 0,
         selected_index: 0,
         page_reads: 0
       }
     )}
  end

  def render(assigns) do
    ~H"""
    <box class="grid grid-cols-1 grid-rows-3 w-screen h-screen">
      <box class="h-4 pl-1 pr-1">
        <box class="font-bold">List view demo</box>
        <box>{mode_label(@mode)}</box>
        <box id="list-details" class="h-1 w-full text-muted">{list_details(@mode, @lazy)}</box>
        <box class="text-muted">d: default / v: virtual / l: lazy. Home / End jump to the edges.</box>
      </box>
      <box class="h-full pl-1 pr-1">
        <.list :if={@mode == :default} id="languages" br-change="change" class="focus:border-1 w-32">
          <:item value="elixir">Elixir</:item>
          <:item value="erlang">Erlang</:item>
          <:item value="rust">Rust</:item>
          <:item value="go">Go</:item>
          <:item value="zig">Zig</:item>
          <:item value="python">Python</:item>
          <:item value="lua">Lua</:item>
          <:item value="gleam">Gleam</:item>
          <:item value="haskell">Haskell</:item>
        </.list>
        <.list
          :if={@mode == :virtual}
          id="large-list"
          br-change="change"
          virtual
          class="focus:border-1 w-full h-full"
        >
          <:item :for={index <- @large_items} value={to_string(index)}>Item {index}</:item>
        </.list>
        <.list
          :if={@mode == :lazy}
          id="lazy-list"
          br-change="lazy_change"
          virtual
          total={@lazy.total}
          start_index={@lazy.start}
          selected_index={@lazy.selected_index}
          list-selected={to_string(@lazy.selected_index + 1)}
          list-notify-scroll
          loop={false}
          class="focus:border-1 w-full h-full"
        >
          <:item :for={item <- @lazy.items} value={to_string(item)}>
            <box class="h-1">Item {item}</box>
          </:item>
        </.list>
      </box>
      <box class="h-2 w-full bg-panel overflow-hidden">
        <box class="h-1 pl-1">Selected: {@selected || "none"}</box>
        <.keybinding_bar
          keybindings={@breeze.keybindings}
          class="inline h-1 w-full pl-1 overflow-hidden"
        />
      </box>
    </box>
    """
  end

  def handle_event("lazy_change", %{action: :scroll} = event, term) do
    %{offset: offset, viewport_height: height} = event
    {:noreply, load_lazy_window(term, offset + div(height, 2))}
  end

  def handle_event("lazy_change", %{index: index}, term) do
    {:noreply,
     term
     |> assign(lazy: %{term.assigns.lazy | selected_index: index}, selected: to_string(index + 1))
     |> load_lazy_window(index)}
  end

  def handle_event("change", %{value: value}, term), do: {:noreply, assign(term, selected: value)}
  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(_, term), do: {:noreply, term}

  def switch_list(%{"key" => key}, term) do
    {mode, focused} =
      case key do
        "d" -> {:default, "languages"}
        "v" -> {:virtual, "large-list"}
        "l" -> {:lazy, "lazy-list"}
      end

    select_list(mode, focused, term)
  end

  defp select_list(mode, _focused, %{assigns: %{mode: mode}} = term), do: {:noreply, term}

  defp select_list(mode, focused, term) do
    term = term |> assign(mode: mode, selected: nil) |> focus(focused)

    term =
      if mode == :lazy do
        load_lazy_window(term, term.assigns.lazy.cursor)
      else
        term
      end

    {:noreply, term}
  end

  # A real backend would return COUNT(*) and accept offset/limit here.
  # Generate only requested pages so no full dataset is ever materialized.
  defp fetch_page(page, total) do
    first = page * @page_size + 1
    Enum.to_list(first..min(first + @page_size - 1, total))
  end

  defp load_lazy_window(term, index) do
    lazy = term.assigns.lazy
    total = lazy.total
    page = div(min(max(index, 0), total - 1), @page_size)
    first = max(page - @prefetch_pages, 0)
    last = min(page + @prefetch_pages, div(total - 1, @page_size))
    window_pages = Enum.to_list(first..last)
    wanted = Enum.uniq([0] ++ window_pages ++ [div(total - 1, @page_size)])
    cached = Map.take(lazy.pages, wanted)

    {pages, reads} =
      Enum.reduce(wanted, {cached, lazy.page_reads}, fn page, {pages, reads} ->
        if Map.has_key?(pages, page) do
          {pages, reads}
        else
          {Map.put(pages, page, fetch_page(page, total)), reads + 1}
        end
      end)

    assign(term,
      lazy: %{
        lazy
        | pages: pages,
          cursor: index,
          start: first * @page_size,
          items: Enum.flat_map(window_pages, &Map.fetch!(pages, &1)),
          page_reads: reads
      }
    )
  end

  defp list_details(:lazy, lazy) do
    "Cached: #{cached_count(lazy.pages)} / #{lazy.total} | Page reads: #{lazy.page_reads} | Cache: #{cache_size_kb(lazy.pages)} KB | 3 each side + Home/End"
  end

  defp list_details(:virtual, _lazy), do: "All items available; only visible rows render."
  defp list_details(:default, _lazy), do: "A small, fully loaded list."

  # Estimate the cached pages' BEAM memory footprint in units of 1024 bytes.
  defp cache_size_kb(pages) do
    bytes = :erts_debug.flat_size(pages) * :erlang.system_info(:wordsize)
    :erlang.float_to_binary(bytes / 1024, decimals: 1)
  end

  defp cached_count(pages), do: Enum.sum(Enum.map(pages, fn {_, rows} -> length(rows) end))

  defp mode_label(:default), do: "Default list (9 items)"
  defp mode_label(:virtual), do: "Virtual list (#{@large_item_count} items)"
  defp mode_label(:lazy), do: "Lazy list (#{@large_item_count} items)"
end

Breeze.Example.run(
  [
    view: ListViewDemo,
    mouse: true,
    global_keybindings: [
      {"d", "Default list", &ListViewDemo.switch_list/2},
      {"v", "Virtual list", &ListViewDemo.switch_list/2},
      {"l", "Lazy list", &ListViewDemo.switch_list/2},
      {"q", "Quit", fn _event, term -> {:stop, term} end}
    ]
  ],
  keep_alive: :infinity
)
