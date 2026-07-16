defmodule Breeze.RemoteInspector.Page do
  @moduledoc """
  Behaviour for custom remote inspector pages.

  An inspected application registers pages with its server:

      Breeze.Server.start_link(
        view: MyApp.View,
        inspector: [pages: [MyApp.TimelinePage]]
      )

  App-registered pages are published with the inspector snapshot and shown
  while that app is the active source. The page module must also be available
  to the inspector node. If it is missing, the tab remains visible and reports
  which package needs to be added to the inspector project.

  Register page modules directly in the inspector configuration:

      inspector: [
        pages: [
          MyApp.TimelinePage,
          MyApp.ToolsPage
        ]
      ]

  Each page defines its display label and optional initial assigns through
  `page/0`. Assigns accept a map or keyword list:

      def page do
        [label: "Runtime tools", assigns: %{mode: :compact, limit: 200}]
      end

  `render/1` receives the standard `:breeze` assigns, the active source server
  PID, page-specific assigns, and page state. Pages can explicitly request
  optional source details with `request/3`:

      {:ok, snapshot} = Breeze.RemoteInspector.Page.request(assigns, :snapshot)

      {:ok, tree} =
        Breeze.RemoteInspector.Page.request(assigns, :render_tree,
          kind: :rendered,
          limit: 200
        )

  This keeps the default page contract small and avoids coupling every page to
  the inspector's internal caches.

  Interactive pages can return `{:noreply, state}` from `handle_event/3` or
  `handle_info/2`. That state is scoped to the page id and inspected source,
  then merged into future render assigns. Asynchronous page messages should
  use `message/2` so replies retain that source:

      send(inspector_pid, Breeze.RemoteInspector.Page.message(assigns, result))

  Use this module to define a page with Breeze template support:

      defmodule MyApp.TimelinePage do
        use Breeze.RemoteInspector.Page

        def page, do: [label: "Timeline"]

        def render(assigns) do
          ~H"<box>Timeline</box>"
        end
      end
  """

  @callback page() :: keyword() | map()
  @callback render(map()) :: any()
  @callback handle_event(term(), map(), map()) :: {:noreply, map()} | :noreply
  @callback handle_info(term(), map()) :: {:noreply, map()} | :noreply

  @optional_callbacks handle_event: 3, handle_info: 2

  @type detail :: :snapshot | :render_tree | :stats

  @doc """
  Returns the active source server PID from page assigns.
  """
  @spec source_server_pid(map()) :: pid() | nil
  def source_server_pid(assigns) when is_map(assigns) do
    case Map.get(assigns, :source_server_pid) do
      pid when is_pid(pid) -> pid
      _pid -> nil
    end
  end

  @doc """
  Wraps an asynchronous message for this page and inspected source.
  """
  @spec message(map(), term()) :: {:remote_inspector_page, term(), term()}
  def message(assigns, message) when is_map(assigns) do
    page_ref = Map.get(assigns, :page_ref, Map.get(assigns, :id))
    {:remote_inspector_page, page_ref, message}
  end

  @doc """
  Requests optional details from the active source application.

  Supported requests are `:snapshot`, `:render_tree`, and `:stats`.
  """
  @spec request(map(), detail(), keyword()) :: {:ok, term()} | {:error, term()}
  def request(assigns, detail, opts \\ [])

  def request(assigns, :snapshot, _opts) do
    request_source(assigns, &Breeze.Server.Diagnostics.inspector_snapshot/1)
  end

  def request(assigns, :render_tree, opts) when is_list(opts) do
    request_source(assigns, &Breeze.Server.inspector_render_tree(&1, opts))
  end

  def request(assigns, :stats, _opts) do
    request_source(assigns, &Breeze.Server.Diagnostics.stats/1)
  end

  def request(_assigns, detail, _opts), do: {:error, {:unsupported_request, detail}}

  @doc """
  Requests source details and raises if they are unavailable.
  """
  @spec request!(map(), detail(), keyword()) :: term()
  def request!(assigns, detail, opts \\ []) do
    case request(assigns, detail, opts) do
      {:ok, value} -> value
      {:error, reason} -> raise "remote inspector page request failed: #{inspect(reason)}"
    end
  end

  defp request_source(assigns, fun) do
    case source_server_pid(assigns) do
      pid when is_pid(pid) ->
        {:ok, fun.(pid)}

      _pid ->
        {:error, :no_active_source}
    end
  catch
    :exit, reason -> {:error, {:source_exit, reason}}
  end

  defmacro __using__(_opts) do
    quote do
      use Breeze.Component
      @behaviour Breeze.RemoteInspector.Page
    end
  end
end
