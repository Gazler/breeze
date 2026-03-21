# This is a UI copy of https://github.com/darrenburns/posting - if you want something good, use that instead.
defmodule Posting do
  use Breeze.View
  import Breeze.Blocks

  alias Breeze.Theme

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

    term = term |> Breeze.View.put_theme(Theme.builtin(:gruvbox)) |> focus("url")

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
        theme_mode: :gruvbox,
        actual_theme_mode: term.theme.mode,
        theme_status: Breeze.Theme.probe_status(term.theme) || :ready,
        show_debug: System.get_env("BREEZE_DEBUG") == "1",
        show_help: false
      )

    {:ok, term}
  end

  def render(assigns) do
    ~H"""
    <box class="width-screen height-screen bg padding-top-1">
      <box class="grid grid-cols-1 width-full height-full padding-left-2 padding-right-2">
        <box class="height-3 padding-top-1 padding-bottom-1">
          <box class="inline width-full height-1">
            <box class="bold text-primary">Req It Ralph</box>
            <box class="text-muted"> 0.0.1</box>
            <box class="text-muted"> {@theme_mode}/{@actual_theme_mode} ({@theme_status})</box>
            <box class="width-full text-right text-muted">{@user_host}</box>
          </box>
        </box>
        <box style="grid grid-cols-5 height-2 padding-bottom-1">
          <box style="text-primary width-1">▐</box>
          <.dropdown
            id="method"
            selected={@method}
            br-change="method_changed"
            class="width-10"
            item_style="bg-panel text"
            menu_style="bg-panel text"
            menu_top={1}
          >
            <:item :for={method <- @methods} value={method}>{method}</:item>
          </.dropdown>
          <.input
            id="url"
            input-value={@url}
            input-placeholder="Enter URL"
            br-change="url_changed"
            style="width-full"
          />
          <box class="width-8 bg-primary text-bg bold">{"  Send "}</box>
          <box style="bg-primary text-bg width-1">▐</box>
        </box>
        <box style="grid grid-cols-1 grid-rows-2 height-full">
          <box style="grid grid-cols-2 height-full">
            <.list
              id="collection"
              list-scroll-padding={1}
              class="bg border-rounded height-full overflow-scroll focus:border-accent width-full"
              item_style="selected:bg-primary selected:text focus:selected:text focus:selected:bg-accent width-full"
            >
              <:item :for={{val, label} <- @collection} value={val}>{label}</:item>
            </.list>
            <box style="grid grid-cols-1 grid-rows-2 height-full">
              <box style="border-rounded overflow-hidden" class="bg">
                <box style="grid grid-cols-1 grid-rows-3 height-full">
                  <box class="height-1 text-primary"> Headers  Body  Query  Auth  Info  Options </box>
                  <.scroll
                    id="request-headers-scroll"
                    class="height-full overflow-scroll bg"
                    style={%{scrollbar: %{arrows: true}}}
                  >
                    <box class="inline width-full">
                      <box class="text-primary width-18">Content-Type</box>
                      <box>application/json</box>
                    </box>
                    <box class="inline width-full">
                      <box class="text-primary width-18">Referer</box>
                      <box>https://example.com/</box>
                    </box>
                    <box class="inline width-full">
                      <box class="text-primary width-18">Accept-Encoding</box>
                      <box>gzip</box>
                    </box>
                    <box class="inline width-full">
                      <box class="text-primary width-18">Cache-Control</box>
                      <box>no-cache</box>
                    </box>
                    <box class="inline width-full">
                      <box class="text-primary width-18">X-Test-Header</box>
                      <box>one</box>
                    </box>
                    <box class="inline width-full">
                      <box class="text-primary width-18">X-Test-Header</box>
                      <box>two</box>
                    </box>
                    <box class="inline width-full">
                      <box class="text-primary width-18">X-Test-Header</box>
                      <box>three</box>
                    </box>
                    <box class="inline width-full">
                      <box class="text-primary width-18">X-Test-Header</box>
                      <box>four</box>
                    </box>
                  </.scroll>
                  <box style="grid grid-cols-3 height-1">
                    <box class="width-8 text-muted">Name</box>
                    <box class="focus:inverse" focusable>{" Value input "}</box>
                    <box class="width-7 bg-primary text-bg bold">{" Add "}</box>
                  </box>
                </box>
              </box>
              <box style="border-rounded overflow-hidden" class="bg">
                <box style="inline">
                  <box class="text-primary bold"> Body </box>
                  <box class="text-muted"> Headers  Cookies  Trace </box>
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
          <box style="inline height-1 width-full bg-panel overflow-hidden">
            <box class="bg-primary text-bg bold">{" ^j "}</box>
            <box> Send  </box>
            <box class="bg-primary text-bg bold">{" ^t "}</box>
            <box> Method  </box>
            <box class="bg-primary text-bg bold">{" Tab "}</box>
            <box> Next  </box>
            <box class="bg-primary text-bg bold">{" F1 "}</box>
            <box> Help  </box>
            <box class="bg-primary text-bg bold">{" F2 "}</box>
            <box> Debug  </box>
            <box class="bg-primary text-bg bold">{" F3 "}</box>
            <box> Theme  </box>
            <box class="bg-primary text-bg bold">{" F4 "}</box>
            <box> Inspect  </box>
            <box class="bg-primary text-bg bold">{" PgUp "}</box>
            <box> Inspect Dock  </box>
            <box class="bg-primary text-bg bold">{" q "}</box>
            <box> Quit </box>
          </box>
        </box>
      </box>
      <.modal :if={@show_help} id="help" width={56} height={15} br-change="help_closed">
        <:title>Keyboard Shortcuts</:title>
        <box>
        </box>
        <box class="inline">
          <box class="width-8 bg-primary text-bg bold">{" Tab "}</box>
          <box>Cycle focus within the active surface</box>
        </box>
        <box class="inline">
          <box class="width-8 bg-primary text-bg bold">{" ^t "}</box>
          <box>Cycle HTTP method</box>
        </box>
        <box class="inline">
          <box class="width-8 bg-primary text-bg bold">{" ←/→ "}</box>
          <box>Switch tabs</box>
        </box>
        <box class="inline">
          <box class="width-8 bg-primary text-bg bold">{" ↑/↓ "}</box>
          <box>Navigate list</box>
        </box>
        <box class="inline">
          <box class="width-8 bg-primary text-bg bold">{" ^j "}</box>
          <box>Send request</box>
        </box>
        <box class="inline">
          <box class="width-8 bg-primary text-bg bold">{" Escape "}</box>
          <box>Close this dialog</box>
        </box>
        <box class="inline">
          <box class="width-8 bg-primary text-bg bold">{" q "}</box>
          <box>Quit</box>
        </box>
        <box class="inline">
          <box class="width-8 bg-primary text-bg bold">{" F2 "}</box>
          <box>Toggle debug panel</box>
        </box>
        <box class="inline">
          <box class="width-8 bg-primary text-bg bold">{" F3 "}</box>
          <box>Cycle theme</box>
        </box>
        <box class="inline">
          <box class="width-8 bg-primary text-bg bold">{" F4 "}</box>
          <box>Toggle inspector, then click an element to inspect it</box>
        </box>
        <box class="inline">
          <box class="width-8 bg-primary text-bg bold">{" PgUp "}</box>
          <box>Move inspector between bottom and top</box>
        </box>
        <box class="inline">
          <box class="width-8 bg-primary text-bg bold">{" Theme "}</box>
          <box>{@theme_mode}</box>
        </box>
      </.modal>
      <box :if={@show_debug} style="fixed right-0 bottom-0 width-42 height-24">
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
    do: {:noreply, term |> assign(show_help: false) |> focus("url")}

  def handle_event(_, %{"key" => "F1"}, term),
    do: {:noreply, term |> assign(show_help: true) |> focus("help")}

  def handle_event(_, %{"key" => "F2"}, term),
    do: {:noreply, assign(term, show_debug: !term.assigns.show_debug)}

  def handle_event(_, %{"key" => "F3"}, term) do
    {theme_mode, theme} =
      next_theme(term.assigns.theme_mode || :solarized_dark)

    term = Breeze.View.put_theme(term, theme)

    {:noreply,
     term
     |> assign(
       theme_mode: theme_mode,
       actual_theme_mode: term.theme.mode,
       theme_status: Breeze.Theme.probe_status(term.theme) || :ready
     )}
  end

  def handle_event(_, %{"key" => "q"}, term), do: {:stop, term}
  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(:resize, term), do: {:noreply, term}

  def handle_info(_, term), do: {:noreply, term}

  defp next_theme(:system16), do: {:system, :system}
  defp next_theme(:system), do: {:nebula, Theme.builtin(:nebula)}
  defp next_theme(:nebula), do: {:catppuccin, Theme.builtin(:catppuccin)}
  defp next_theme(:catppuccin), do: {:dracula, Theme.builtin(:dracula)}
  defp next_theme(:dracula), do: {:gruvbox, Theme.builtin(:gruvbox)}
  defp next_theme(:gruvbox), do: {:nord, Theme.builtin(:nord)}
  defp next_theme(:nord), do: {:solarized_light, Theme.builtin(:solarized, :light)}
  defp next_theme(:solarized_light), do: {:solarized_dark, Theme.builtin(:solarized, :dark)}
  defp next_theme(_theme_mode), do: {:system16, :system16}

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
end

Breeze.Example.run(
  view: Posting,
  reload: true,
  theme: Breeze.Theme.builtin(:gruvbox),
  hide_cursor: true,
  mouse: [mode: :motion],
  inspector: true,
  global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
)
