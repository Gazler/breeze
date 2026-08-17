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
    url = "https://jsonplaceholder.typicode.com/posts"
    method = "POST"
    method_index = Enum.find_index(@methods, &(&1 == method)) || 0
    user_host = current_user_host()

    term =
      term
      |> switch_theme(:gruvbox)
      |> focus("url")
      |> put_local_keybindings(base_keybindings())
      |> put_focus_keybindings("request-header-name", [{"Enter", "Next"}])
      |> put_focus_keybindings("request-header-value", [{"Enter", "Add header"}])
      |> put_focus_keybindings("request-header-add", [{"Enter", "Add header"}])

    term =
      assign(term,
        url: url,
        method: method,
        method_index: method_index,
        methods: @methods,
        collection: @collection,
        user_host: user_host,
        request_tab: "headers",
        response_tab: "body",
        show_debug: System.get_env("BREEZE_DEBUG") == "1",
        show_help: false,
        request_headers: [],
        request_header_name: "",
        request_header_value: ""
      )

    {:ok, term}
  end

  def render(assigns) do
    ~H"""
    <box class="grid grid-cols-1 grid-rows-2 w-screen h-screen bg">
      <box class="w-full h-full pl-2 pr-2">
        <box class="grid grid-cols-1 w-full h-full">
          <box class="h-3 pt-1 pb-1">
            <box class="inline w-full h-1">
              <box class="font-bold text-primary">Req It Ralph</box>
              <box class="text-muted"> 0.0.1</box>
              <box class="hidden md:block text-muted">
                {" "}{@breeze.theme.name}/{@breeze.theme.actual_mode} ({@breeze.theme.status})
              </box>
              <box class="hidden md:block md:w-full text-right text-muted">{@user_host}</box>
            </box>
          </box>
          <box class="h-2 pb-1">
            <box class="grid grid-cols-3 w-full h-full border-x border-edge border-primary">
              <.dropdown
                id="method"
                selected={@method}
                br-change="method_changed"
                class="w-10"
                item_class="bg-panel text"
                menu_class="bg-panel text"
              >
                <:item :for={method <- @methods} value={method}>{method}</:item>
              </.dropdown>
              <.input
                id="url"
                input-value={@url}
                input-placeholder="Enter URL"
                br-change="url_changed"
                class="w-full"
              />
              <.button class="w-8 pl-2" focusable="false">Send</.button>
            </box>
          </box>
          <box class="grid grid-cols-1 grid-rows-2 h-full">
            <box class="grid grid-cols-1 md:grid-cols-2 h-full">
              <box class="hidden md:block">
                <.panel id="collection-panel" class="h-full w-full overflow-hidden bg">
                  <box class="w-full h-full pr-1 pb-1 overflow-hidden">
                    <.list
                      id="collection"
                      variant="muted"
                      list-scroll-padding={1}
                      class="bg h-full w-full overflow-scroll border-0 focus:border-0"
                      item_class="w-full"
                    >
                      <:item :for={{val, label} <- @collection} value={val}>{label}</:item>
                    </.list>
                  </box>
                </.panel>
              </box>
              <box class="grid grid-cols-1 grid-rows-2 h-full">
                <.panel id="request-panel" class="h-full overflow-hidden bg focus:border-accent">
                  <.tabs
                    id="request-tabs"
                    selected={@request_tab}
                    variant="underline"
                    br-change="request_tab"
                    class="w-full h-full"
                  >
                    <:tab value="headers" label="Headers">
                      <box class="grid grid-cols-1 grid-rows-2 h-full">
                        <.scroll
                          id="request-tabs-panel-headers"
                          scroll-autoscroll="bottom"
                          class="h-full overflow-scroll bg"
                          style={%{scrollbar: %{arrows: true}}}
                        >
                          <box :if={@request_headers == []} class="w-full h-full bg overflow-hidden">
                            <box
                              class="absolute left-0 top-0 w-full h-full text-mute-70 overflow-hidden content-repeat"
                            >
                              ╱
                            </box>
                            <box class="absolute center text-center font-bold text-mute-40">
                              No Headers
                            </box>
                          </box>
                          <box :for={{name, value} <- @request_headers} class="inline w-full">
                            <box class="text-primary w-18">{name}</box>
                            <box>{value}</box>
                          </box>
                        </.scroll>
                        <box class="grid grid-cols-3 gap-x-1 h-1">
                          <.input
                            id="request-header-name"
                            input-value={@request_header_name}
                            input-placeholder="Header name"
                            br-change="request_header_name_changed"
                            class="w-20"
                          />
                          <.input
                            id="request-header-value"
                            input-value={@request_header_value}
                            input-placeholder="Header value"
                            br-change="request_header_value_changed"
                            class="w-full"
                          />
                          <.button id="request-header-add" class="w-7">Add</.button>
                        </box>
                      </box>
                    </:tab>
                    <:tab value="body" label="Body">
                      <box class="text-muted">No request body</box>
                    </:tab>
                    <:tab value="query" label="Query">
                      <box class="text-muted">No query parameters</box>
                    </:tab>
                    <:tab value="auth" label="Auth">
                      <box class="text-muted">No auth configured</box>
                    </:tab>
                    <:tab value="info" label="Info">
                      <box class="text-muted">Request metadata</box>
                    </:tab>
                    <:tab value="options" label="Options">
                      <box class="text-muted">No request options</box>
                    </:tab>
                  </.tabs>
                </.panel>
                <.panel id="response-panel" class="h-full overflow-hidden bg focus:border-accent">
                  <.tabs
                    id="response-tabs"
                    selected={@response_tab}
                    variant="underline"
                    br-change="response_tab"
                    class="w-full h-full"
                  >
                    <:tab value="body" label="Body">
                      <box>{"  1  {"}</box>
                      <box>{"  2    \"title\": \"foo\","}</box>
                      <box>{"  3    \"body\": \"bar\","}</box>
                      <box>{"  4    \"userId\": 1,"}</box>
                      <box>{"  5    \"id\": 101"}</box>
                      <box>{"  6  }"}</box>
                    </:tab>
                    <:tab value="headers" label="Headers">
                      <box class="text-muted">Response headers</box>
                    </:tab>
                    <:tab value="cookies" label="Cookies">
                      <box class="text-muted">No cookies</box>
                    </:tab>
                    <:tab value="trace" label="Trace">
                      <box class="text-muted">No trace data</box>
                    </:tab>
                  </.tabs>
                </.panel>
              </box>
            </box>
          </box>
        </box>
      </box>
      <box class="h-1 w-full bg-panel overflow-hidden">
        <.keybinding_bar keybindings={@breeze.keybindings}/>
      </box>
      <.modal :if={@show_help} screen-dim id="help" width={56} height={15} br-change="help_closed">
        <:title>Keyboard Shortcuts</:title>
        <box>
        </box>
        <box class="inline">
          <box class="w-8 bg-primary text-bg font-bold">{" Tab "}</box>
          <box>Cycle focus within the active surface</box>
        </box>
        <box class="inline">
          <box class="w-8 bg-primary text-bg font-bold">{" ^t "}</box>
          <box>Cycle HTTP method</box>
        </box>
        <box class="inline">
          <box class="w-8 bg-primary text-bg font-bold">{" ←/→ "}</box>
          <box>Switch tabs</box>
        </box>
        <box class="inline">
          <box class="w-8 bg-primary text-bg font-bold">{" ↑/↓ "}</box>
          <box>Navigate list</box>
        </box>
        <box class="inline">
          <box class="w-8 bg-primary text-bg font-bold">{" ^j "}</box>
          <box>Send request</box>
        </box>
        <box class="inline">
          <box class="w-8 bg-primary text-bg font-bold">{" Escape "}</box>
          <box>Close this dialog</box>
        </box>
        <box class="inline">
          <box class="w-8 bg-primary text-bg font-bold">{" q "}</box>
          <box>Quit</box>
        </box>
        <box class="inline">
          <box class="w-8 bg-primary text-bg font-bold">{" F2 "}</box>
          <box>Toggle debug panel</box>
        </box>
        <box class="inline">
          <box class="w-8 bg-primary text-bg font-bold">{" F3 "}</box>
          <box>Cycle theme</box>
        </box>
        <box class="inline">
          <box class="w-8 bg-primary text-bg font-bold">{" F4 "}</box>
          <box>Toggle inspector, then click an element to inspect it</box>
        </box>
        <box class="inline">
          <box class="w-8 bg-primary text-bg font-bold">{" PgUp "}</box>
          <box>Move inspector between bottom and top</box>
        </box>
        <box class="inline">
          <box class="w-8 bg-primary text-bg font-bold">{" Theme "}</box>
          <box>{@breeze.theme.name}</box>
        </box>
      </.modal>
      <box :if={@show_debug} style="fixed right-0 bottom-0 w-42 h-24 layer-50">
        <live id="debug" view={Breeze.Debug} start_opts={[width: 42, height: 24]}>
        </live>
      </box>
    </box>
    """
  end

  def handle_event("url_changed", %{value: value}, term) do
    {:noreply, assign(term, url: value)}
  end

  def handle_event("method_changed", %{value: method, index: index}, term),
    do: {:noreply, assign(term, method: method, method_index: index)}

  def handle_event("request_header_name_changed", %{value: value}, term),
    do: {:noreply, assign(term, request_header_name: value)}

  def handle_event("request_header_value_changed", %{value: value}, term),
    do: {:noreply, assign(term, request_header_value: value)}

  def handle_event(_, %{"key" => "\x14"} = event, term), do: toggle_method_dropdown(event, term)

  def handle_event("request_tab", %{value: tab}, term),
    do: {:noreply, assign(term, request_tab: tab)}

  def handle_event("response_tab", %{value: tab}, term),
    do: {:noreply, assign(term, response_tab: tab)}

  def handle_event(_, %{"key" => "Enter"}, %{focused: "request-header-name"} = term),
    do: {:noreply, focus(term, "request-header-value")}

  def handle_event(_, %{"key" => "Enter"}, %{focused: focused} = term)
      when focused in ["request-header-value", "request-header-add"] do
    {:noreply, add_request_header(term)}
  end

  def handle_event("help_closed", _, term),
    do: {:noreply, term |> assign(show_help: false) |> focus("url")}

  def handle_event(_, %{"key" => "F1"}, %{assigns: %{show_help: true}} = term),
    do: {:noreply, term |> assign(show_help: false) |> focus("url")}

  def handle_event(_, %{"key" => "F1"}, term),
    do: {:noreply, term |> assign(show_help: true) |> focus("help")}

  def handle_event(_, %{"key" => "F2"}, term),
    do: {:noreply, assign(term, show_debug: !term.assigns.show_debug)}

  def handle_event(_, %{"key" => "q"}, term), do: {:stop, term}
  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(_, term), do: {:noreply, term}

  defp add_request_header(term) do
    name = String.trim(term.assigns.request_header_name || "")
    value = String.trim(term.assigns.request_header_value || "")

    if name == "" or value == "" do
      term
    else
      assign(term,
        request_headers: term.assigns.request_headers ++ [{name, value}],
        request_header_name: "",
        request_header_value: ""
      )
      |> focus("request-header-name")
    end
  end

  defp current_user_host do
    case Application.get_env(:breeze, :example_user_host) do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        user = System.get_env("USER") || System.get_env("USERNAME") || "unknown"

        host =
          case :inet.gethostname() do
            {:ok, hostname} -> to_string(hostname)
            _ -> "localhost"
          end

        "#{user}@#{host}"
    end
  end

  defp base_keybindings do
    [
      {"^t", "Method", &toggle_method_dropdown/2},
      {"Tab", "Next"},
      {"F1", "Help"},
      {"F2", "Debug"},
      {"F3", "Theme"},
      {"F4", "Inspect"},
      {"PgUp", "Inspect Dock"},
      {"q", "Quit"}
    ]
  end

  defp toggle_method_dropdown(_event, term) do
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
end

Breeze.Example.run(
  view: Posting,
  reload: true,
  theme: Breeze.Theme.builtin(:gruvbox),
  hide_cursor: true,
  mouse: [mode: :motion],
  inspector: true,
  global_keybindings: [
    {"F3", "Cycle theme", &Breeze.View.cycle_theme/2},
    {"q", fn _event, term -> {:stop, term} end}
  ]
)
