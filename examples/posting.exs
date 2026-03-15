# This is a UI copy of https://github.com/darrenburns/posting - if you want something good, use that instead.
defmodule Posting do
  use Breeze.View
  import Breeze.Blocks

  @methods ["GET", "POST", "PUT", "PATCH", "DELETE"]

  @collection [
    {"echo_get", "GET  echo"},
    {"echo_post", "POST echo post"},
    {"jp_root", "▼ jsonplaceholder/"},
    {"jp_posts", "    ▼ posts/"},
    {"jp_get_all", "        GET  get all"},
    {"jp_get_one", "        GET  get one"},
    {"jp_create", "        POST create"},
    {"jp_delete", "        DEL  delete a post"},
    {"jp_comments", "    ▼ comments/"},
    {"jp_get_c", "        GET  get comments"},
    {"jp_todos", "    ▼ todos/"},
    {"jp_t_all", "        GET  get all"},
    {"jp_t_one", "        GET  get one"},
    {"jp_users", "    ▼ users/"},
    {"jp_u_all", "        GET  get all"}
  ]

  def mount(_opts, term) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(term.terminal)
    url = "https://jsonplaceholder.typicode.com/posts"
    method = "POST"
    method_index = Enum.find_index(@methods, &(&1 == method)) || 0

    term =
      term
      |> focus("url")
      |> assign(
        url: url,
        url_cursor: String.length(url),
        method: method,
        method_index: method_index,
        methods: @methods,
        collection: @collection,
        screen_width: screen_width,
        screen_height: screen_height,
        url_width: screen_width - 18,
        request_tab: "headers",
        response_tab: "body",
        show_help: false,
        show_debug: false
      )

    {:ok, term}
  end

  def render(assigns) do
    assigns =
      Map.put(
        assigns,
        :url_display,
        " " <> String.pad_trailing(assigns.url, max((assigns.url_width || 1) - 1, 0))
      )

    ~H"""
    <box style="width-screen height-screen">
      <box style="grid grid-cols-1 width-screen height-full">
        <box style="height-3">
          <box style="height-1">Hello</box>
          <box style="height-1">
          </box>
          <box style="grid grid-cols-3 height-1">
            <.dropdown
              id="method"
              selected={@method}
              br-change="method_changed"
              style="bg-4 text-7 bold focus:inverse width-10"
              item_style="bg-7 text-0"
              menu_style="bg-7 text-0"
              menu_top={1}
            >
              <:item :for={method <- @methods} value={method}>{method}</:item>
            </.dropdown>
            <box
              focusable
              id="url"
              implicit={Breeze.Implicit.Input}
              input-value={@url}
              input-cursor={@url_cursor}
              br-change="url_changed"
              style="width-full focus:inverse"
            >
              {@url_display}
            </box>
            <box style="bg-4 text-7 bold width-8">  Send  </box>
          </box>
        </box>
        <box style="height-1">
        </box>
        <box style="grid grid-cols-2">
          <.list
            id="collection"
            list-scroll-padding={1}
            style="border-rounded height-full overflow-scroll focus:border-4 width-full"
            item_style="selected:bg-24 selected:text-0 focus:selected:text-7 focus:selected:bg-4 width-full"
          >
            <:item :for={{val, label} <- @collection} value={val}>{label}</:item>
          </.list>
          <box style="grid grid-cols-1 grid-rows-2">
            <box style="border-rounded overflow-hidden">
              <box style="grid grid-cols-1 grid-rows-3 height-full">
                <box style="height-1"> Headers  Body  Query  Auth  Info  Options </box>
                <.scroll
                  id="request-headers-scroll"
                  style="height-full overflow-scroll scrollbar-arrows-always"
                >
                  <box style="inline">
                    <box style="text-4 width-18">Content-Type</box>
                    <box>application/json</box>
                  </box>
                  <box style="inline">
                    <box style="text-4 width-18">Referer</box>
                    <box>https://example.com/</box>
                  </box>
                  <box style="inline">
                    <box style="text-4 width-18">Accept-Encoding</box>
                    <box>gzip</box>
                  </box>
                  <box style="inline">
                    <box style="text-4 width-18">Cache-Control</box>
                    <box>no-cache</box>
                  </box>
                  <box style="inline">
                    <box style="text-4 width-18">X-Test-Header</box>
                    <box>one</box>
                  </box>
                  <box style="inline">
                    <box style="text-4 width-18">X-Test-Header</box>
                    <box>two</box>
                  </box>
                  <box style="inline">
                    <box style="text-4 width-18">X-Test-Header</box>
                    <box>three</box>
                  </box>
                  <box style="inline">
                    <box style="text-4 width-18">X-Test-Header</box>
                    <box>four</box>
                  </box>
                </.scroll>
                <box style="grid grid-cols-3 height-1">
                  <box style="width-8">Name</box>
                  <box style="focus:inverse" focusable>{" Value input "}</box>
                  <box style="bg-7 text-0 bold width-7"> Add </box>
                </box>
              </box>
            </box>
            <box style="border-rounded overflow-hidden">
              <box style="inline">
                <box style="text-4 bold"> Body </box>
                <box> Headers  Cookies  Trace </box>
              </box>
              <box>{"  1  {"}</box>
              <box>{"  2    \"title\": \"foo\","}</box>
              <box>{"  3    \"body\": \"bar\","}</box>
              <box>{"  4    \"userId\": 1,"}</box>
              <box>{"  5    \"id\": 101"}</box>
              <box>{"  6  }"}</box>
            </box>
          </box>
        </box>
        <box style="inline height-1 width-screen">
          <box style="bg-7 text-0 bold"> ^j </box>
          <box> Send  </box>
          <box style="bg-7 text-0 bold"> ^t </box>
          <box> Method  </box>
          <box style="bg-7 text-0 bold"> Tab </box>
          <box> Next  </box>
          <box style="bg-7 text-0 bold"> F1 </box>
          <box> Help  </box>
          <box style="bg-7 text-0 bold"> F2 </box>
          <box> Debug  </box>
          <box style="bg-7 text-0 bold"> q </box>
          <box> Quit </box>
        </box>
      </box>
      <.modal :if={@show_help} id="help" width={56} height={15} br-change="help_closed">
        <:title>Keyboard Shortcuts</:title>
        <box>
        </box>
        <box style="inline">
          <box style="bg-7 text-0 bold width-8"> Tab </box>
          <box>Cycle focus within the active surface</box>
        </box>
        <box style="inline">
          <box style="bg-7 text-0 bold width-8"> ^t </box>
          <box>Cycle HTTP method</box>
        </box>
        <box style="inline">
          <box style="bg-7 text-0 bold width-8"> ←/→ </box>
          <box>Switch tabs</box>
        </box>
        <box style="inline">
          <box style="bg-7 text-0 bold width-8"> ↑/↓ </box>
          <box>Navigate list</box>
        </box>
        <box style="inline">
          <box style="bg-7 text-0 bold width-8"> ^j </box>
          <box>Send request</box>
        </box>
        <box style="inline">
          <box style="bg-7 text-0 bold width-8"> Escape </box>
          <box>Close this dialog</box>
        </box>
        <box style="inline">
          <box style="bg-7 text-0 bold width-8"> q </box>
          <box>Quit</box>
        </box>
        <box style="inline">
          <box style="bg-7 text-0 bold width-8"> F2 </box>
          <box>Toggle debug panel</box>
        </box>
      </.modal>
      <box :if={@show_debug} style="fixed right-0 bottom-0 width-34 height-18">
        <live id="debug" view={Breeze.Debug} start_opts={[width: 34, height: 18]}>
        </live>
      </box>
    </box>
    """
  end

  def handle_event("url_changed", %{value: value, cursor: cursor}, term) do
    {:noreply, assign(term, url: value, url_cursor: cursor)}
  end

  def handle_event("method_changed", %{value: method, index: index}, term),
    do: {:noreply, assign(term, method: method, method_index: index)}

  def handle_event(_, %{"key" => "\x14"}, term) do
    term =
      update_implicit(term, "method", fn
        {Breeze.Implicit.Dropdown, state} ->
          if state.open? do
            Breeze.Implicit.Dropdown.close(state)
          else
            Breeze.Implicit.Dropdown.open(state)
          end

        {_mod, state} ->
          state
      end)

    {:noreply, focus(term, "method")}
  end

  def handle_event("request_tab", %{value: tab}, term),
    do: {:noreply, assign(term, request_tab: tab)}

  def handle_event("response_tab", %{value: tab}, term),
    do: {:noreply, assign(term, response_tab: tab)}

  def handle_event("help_closed", _, term),
    do: {:noreply, term |> assign(show_help: false) |> focus("url")}

  def handle_event(_, %{"key" => "F1"}, %{assigns: %{show_help: true}} = term),
    do: {:noreply, term}

  def handle_event(_, %{"key" => "F1"}, term),
    do: {:noreply, term |> assign(show_help: true) |> focus("help")}

  def handle_event(_, %{"key" => "F2"}, term),
    do: {:noreply, assign(term, show_debug: !term.assigns.show_debug)}

  def handle_event(_, %{"key" => "q"}, term), do: {:stop, term}
  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(:resize, term) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(term.terminal)

    {:noreply,
     assign(term,
       url_width: screen_width - 18,
       screen_width: screen_width,
       screen_height: screen_height
     )}
  end

  def handle_info(_, term), do: {:noreply, term}
end

Breeze.Example.run(
  view: Posting,
  hide_cursor: true,
  global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
)
